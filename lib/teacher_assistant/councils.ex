defmodule TeacherAssistant.Councils do
  @moduledoc """
  Class councils (spec I3, I4): one per class and period — a trimester
  (`{:trimester, term}`) or the year (`{:annual, year}`) — keyed by the period's
  `Organization.period_param/1`. The council's header, a decision per student
  (distinction choice, conduct warning, appreciation, and for the year a passage
  decision), holding and reopening. A council is created by its first save. While the
  class's report cards for the period are published (I2), every write is refused with
  `{:error, :locked}`.
  """

  require Ash.Query

  alias TeacherAssistant.Academics.{
    AcademicYear,
    ClassCouncil,
    ClassGroup,
    ConductWarning,
    CouncilDecision,
    CouncilDistinctionChoice,
    PassageDecision,
    PassageRules,
    Term
  }

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, Organization, ReportCards, Scope}

  @doc "The stored council (decisions loaded) or an unsaved default."
  def council(%Scope{} = scope, %ClassGroup{} = cg, period) do
    stored(scope, cg, period) ||
      %ClassCouncil{
        class_group_id: cg.id,
        academic_year_id: year_id(period),
        term_id: term_id(period),
        period_key: Organization.period_param(period),
        status: :open,
        held_on: default_date(scope, period),
        decisions: []
      }
  end

  @doc "The period's councils by class id, in one query."
  def for_period(%Scope{} = scope, period) do
    ClassCouncil
    |> Ash.Query.for_read(:for_period, %{period_key: Organization.period_param(period)},
      scope: scope
    )
    |> Ash.read!()
    |> Map.new(&{&1.class_group_id, &1})
  end

  @doc "Whether the class's council for the period is held."
  def held?(%Scope{} = scope, %ClassGroup{} = cg, period),
    do: match?(%ClassCouncil{status: :held}, stored(scope, cg, period))

  @doc "Whether the council is locked: the class's report cards for the period are published."
  def locked?(%Scope{} = scope, %ClassGroup{} = cg, period),
    do: ReportCards.current_publication(scope, cg, period) != nil

  @doc "Saves the header (`held_on`, `chair`, `attendees`, `observations`), creating the council."
  def save_header(%Scope{} = scope, %ClassGroup{} = cg, period, %{} = params) do
    attrs = Map.take(params, ~w(held_on chair attendees observations))

    with :ok <- unlocked(scope, cg, period),
         {:ok, council} <- ensure(scope, cg, period) do
      council |> Ash.Changeset.for_update(:edit, attrs, scope: scope) |> Ash.update()
    end
  end

  @doc """
  Records the council's decision for a student. `""` (or a missing key) means no choice /
  no warning / keep the passage proposal; the appreciation is trimmed and limited to 300
  characters.
  """
  def set_decision(%Scope{} = scope, %ClassGroup{} = cg, period, student_id, params) do
    with :ok <- unlocked(scope, cg, period),
         {:ok, choice} <- cast(CouncilDistinctionChoice, params["distinction_choice"]),
         {:ok, warning} <- cast(ConductWarning, params["conduct_warning"]),
         {:ok, passage} <- cast(PassageDecision, params["passage_decision"]),
         {:ok, council} <- ensure(scope, cg, period) do
      CouncilDecision
      |> Ash.Changeset.for_create(
        :record,
        %{
          class_council_id: council.id,
          student_id: student_id,
          distinction_choice: choice,
          conduct_warning: warning,
          appreciation: params["appreciation"],
          passage_decision: passage
        },
        scope: scope
      )
      |> Ash.create()
    end
  end

  @doc "Marks the council held (creating it if needed); holding a held council is a no-op."
  def hold(%Scope{} = scope, %ClassGroup{} = cg, period) do
    with :ok <- unlocked(scope, cg, period),
         {:ok, council} <- ensure(scope, cg, period) do
      case council.status do
        :held -> {:ok, council}
        :open -> council |> Ash.Changeset.for_update(:hold, %{}, scope: scope) |> Ash.update()
      end
    end
  end

  @doc "Reopens a held council; with nothing stored there is nothing to reopen."
  def reopen(%Scope{} = scope, %ClassGroup{} = cg, period) do
    with :ok <- unlocked(scope, cg, period) do
      case stored(scope, cg, period) do
        nil -> {:ok, council(scope, cg, period)}
        council -> council |> Ash.Changeset.for_update(:reopen, %{}, scope: scope) |> Ash.update()
      end
    end
  end

  @doc "Trimester outcomes (no passage); see `outcomes/3`."
  def outcomes(council, results), do: outcomes(council, results, nil)

  @doc """
  Each graded student's council outcome: the council's distinction choice (`:none` → nil)
  or the I1 proposal, the conduct warning and the appreciation. With `passage`
  (`%{rules: %PassageRules{}, students: %{student_id => inputs}}`, annual council), also
  the passage decision — the council's, or the engine's proposal — with the proposal's
  reason when it stands, and always the engine's `proposal` and `proposal_reason`. Decisions for students no longer in the results are ignored.
  """
  def outcomes(_council, nil, _passage), do: %{}

  def outcomes(%ClassCouncil{} = council, %{per_student: per_student}, passage) do
    decisions = Map.new(council.decisions || [], &{&1.student_id, &1})

    Map.new(per_student, fn {student_id, data} ->
      decision = Map.get(decisions, student_id)

      outcome = %{
        distinction: distinction(decision, data.distinction),
        conduct_warning: decision && decision.conduct_warning,
        appreciation: decision && decision.appreciation
      }

      {student_id,
       add_passage(
         outcome,
         decision,
         data,
         Map.get(passage_students(passage), student_id),
         passage
       )}
    end)
  end

  @doc "Spec KLM1 (M3): the student's end-of-year passage decisions, by class group."
  def annual_decisions(%Scope{} = scope, student_id) do
    CouncilDecision
    |> Ash.Query.filter(
      student_id == ^student_id and class_council.period_key == "annee" and
        not is_nil(passage_decision)
    )
    |> Ash.Query.load(:class_council)
    |> Ash.read!(scope: scope)
    |> Map.new(&{&1.class_council.class_group_id, &1.passage_decision})
  end

  @doc """
  The passage engine's inputs for the class's students over the year, read once for the
  class: the enrollment's repeater flag, the annual note de conduite and the unjustified
  absence hours, keyed by student id.
  """
  def passage_inputs(%Scope{} = scope, %ClassGroup{} = cg, {:annual, %AcademicYear{}} = period) do
    discipline = Discipline.class_discipline(scope, cg, period)
    attendance = Attendance.class_conduct(scope, cg, period)

    scope
    |> Enrollment.list_roster(cg)
    |> Map.new(fn %{student: s, enrollment: e} ->
      {s.id,
       %{
         repeater?: e.repeater,
         conduct: discipline |> Map.get(e.id, %{}) |> Map.get(:note_de_conduite),
         unjustified_hours: attendance |> Map.get(e.id, %{}) |> Map.get(:unjustified_hours)
       }}
    end)
  end

  @doc "The trimester whose séquences cover `today`, else the first; nil without terms."
  def default_term([], _today), do: nil

  def default_term([first | _] = terms, %Date{} = today) do
    Enum.find(terms, first, fn term ->
      Enum.any?(term.sequences, fn s ->
        Date.compare(s.start_date, today) != :gt and Date.compare(today, s.end_date) != :gt
      end)
    end)
  end

  defp add_passage(outcome, _decision, _data, _inputs, nil), do: outcome

  defp add_passage(outcome, decision, data, inputs, %{rules: %PassageRules{} = rules}) do
    {proposal, reason} =
      PassageRules.propose(Map.merge(inputs || %{}, %{average: data.moyenne_generale}), rules) ||
        {nil, nil}

    chosen = decision && decision.passage_decision

    Map.merge(outcome, %{
      passage: chosen || proposal,
      passage_reason: if(chosen, do: nil, else: reason),
      proposal: proposal,
      proposal_reason: reason
    })
  end

  defp passage_students(nil), do: %{}
  defp passage_students(%{students: students}), do: students

  defp distinction(%CouncilDecision{distinction_choice: :none}, _proposal), do: nil
  defp distinction(%CouncilDecision{distinction_choice: nil}, proposal), do: proposal
  defp distinction(%CouncilDecision{distinction_choice: choice}, _proposal), do: choice
  defp distinction(nil, proposal), do: proposal

  defp stored(scope, cg, period) do
    ClassCouncil
    |> Ash.Query.for_read(
      :for_class_period,
      %{class_group_id: cg.id, period_key: Organization.period_param(period)},
      scope: scope
    )
    |> Ash.read_one!()
  end

  defp ensure(scope, cg, period) do
    case stored(scope, cg, period) do
      %ClassCouncil{} = council -> {:ok, council}
      nil -> create(scope, cg, period)
    end
  end

  defp create(scope, cg, period) do
    ClassCouncil
    |> Ash.Changeset.for_create(
      :open,
      %{
        class_group_id: cg.id,
        academic_year_id: year_id(period),
        term_id: term_id(period),
        period_key: Organization.period_param(period),
        held_on: default_date(scope, period)
      },
      scope: scope
    )
    |> Ash.create()
    |> case do
      # Another page created it at the same time: the unique identity refused this one.
      {:error, %Ash.Error.Invalid{}} = error ->
        case stored(scope, cg, period) do
          nil -> error
          council -> {:ok, council}
        end

      other ->
        other
    end
  end

  defp term_id({:trimester, %Term{id: id}}), do: id
  defp term_id({:annual, _}), do: nil

  defp year_id({:trimester, %Term{academic_year_id: id}}), do: id
  defp year_id({:annual, %AcademicYear{id: id}}), do: id

  defp default_date(_scope, {:trimester, %Term{} = term}), do: term.class_council_date

  # The annual council meets with the last trimester's council by default.
  defp default_date(scope, {:annual, %AcademicYear{} = year}) do
    case scope |> Organization.list_terms(year) |> List.last() do
      nil -> nil
      term -> term.class_council_date
    end
  end

  defp unlocked(scope, cg, period),
    do: if(locked?(scope, cg, period), do: {:error, :locked}, else: :ok)

  defp cast(_enum, value) when value in [nil, ""], do: {:ok, nil}

  defp cast(enum, value) when is_binary(value) do
    case Enum.find(enum.values(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_choice}
      atom -> {:ok, atom}
    end
  end

  defp cast(enum, value) when is_atom(value),
    do: if(value in enum.values(), do: {:ok, value}, else: {:error, :invalid_choice})
end
