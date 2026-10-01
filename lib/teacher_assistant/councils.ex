defmodule TeacherAssistant.Councils do
  @moduledoc """
  Trimester class councils (spec I3): the council's header, a decision per student
  (distinction choice, conduct warning, appreciation), holding and reopening. A council
  is created by its first save. While the class's trimester is published (I2), every
  write is refused with `{:error, :locked}`.
  """
  require Ash.Query

  alias TeacherAssistant.Academics.{
    ClassCouncil,
    ClassGroup,
    ConductWarning,
    CouncilDecision,
    CouncilDistinctionChoice,
    Term
  }

  alias TeacherAssistant.{ReportCards, Scope}

  @doc "The stored council (decisions loaded) or an unsaved default."
  def council(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term) do
    stored(scope, cg, term) ||
      %ClassCouncil{
        class_group_id: cg.id,
        term_id: term.id,
        status: :open,
        held_on: term.class_council_date,
        decisions: []
      }
  end

  @doc "The term's councils by class id, in one query."
  def for_term(%Scope{} = scope, %Term{id: term_id}) do
    ClassCouncil
    |> Ash.Query.for_read(:for_term, %{term_id: term_id}, scope: scope)
    |> Ash.read!()
    |> Map.new(&{&1.class_group_id, &1})
  end

  @doc "Whether the class's council for the term is held."
  def held?(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term),
    do: match?(%ClassCouncil{status: :held}, stored(scope, cg, term))

  @doc "Whether the council is locked: the class's trimester report cards are published."
  def locked?(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term),
    do: ReportCards.current_publication(scope, cg, {:trimester, term}) != nil

  @doc "Saves the header (`held_on`, `chair`, `attendees`, `observations`), creating the council."
  def save_header(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term, %{} = params) do
    attrs = Map.take(params, ~w(held_on chair attendees observations))

    with :ok <- unlocked(scope, cg, term),
         {:ok, council} <- ensure(scope, cg, term) do
      council |> Ash.Changeset.for_update(:edit, attrs, scope: scope) |> Ash.update()
    end
  end

  @doc """
  Records the council's decision for a student. `""` (or a missing key) means no choice /
  no warning; the appreciation is trimmed and limited to 300 characters.
  """
  def set_decision(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term, student_id, params) do
    with :ok <- unlocked(scope, cg, term),
         {:ok, choice} <- cast(CouncilDistinctionChoice, params["distinction_choice"]),
         {:ok, warning} <- cast(ConductWarning, params["conduct_warning"]),
         {:ok, council} <- ensure(scope, cg, term) do
      CouncilDecision
      |> Ash.Changeset.for_create(
        :record,
        %{
          class_council_id: council.id,
          student_id: student_id,
          distinction_choice: choice,
          conduct_warning: warning,
          appreciation: params["appreciation"]
        },
        scope: scope
      )
      |> Ash.create()
    end
  end

  @doc "Marks the council held (creating it if needed); holding a held council is a no-op."
  def hold(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term) do
    with :ok <- unlocked(scope, cg, term),
         {:ok, council} <- ensure(scope, cg, term) do
      case council.status do
        :held -> {:ok, council}
        :open -> council |> Ash.Changeset.for_update(:hold, %{}, scope: scope) |> Ash.update()
      end
    end
  end

  @doc "Reopens a held council; with nothing stored there is nothing to reopen."
  def reopen(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term) do
    with :ok <- unlocked(scope, cg, term) do
      case stored(scope, cg, term) do
        nil -> {:ok, council(scope, cg, term)}
        council -> council |> Ash.Changeset.for_update(:reopen, %{}, scope: scope) |> Ash.update()
      end
    end
  end

  @doc """
  Each graded student's council outcome: the council's distinction choice (`:none` → nil)
  or the I1 proposal, the conduct warning and the appreciation. Decisions for students no
  longer in the results are ignored.
  """
  def outcomes(_council, nil), do: %{}

  def outcomes(%ClassCouncil{} = council, %{per_student: per_student}) do
    decisions = Map.new(council.decisions || [], &{&1.student_id, &1})

    Map.new(per_student, fn {student_id, data} ->
      decision = Map.get(decisions, student_id)

      {student_id,
       %{
         distinction: distinction(decision, data.distinction),
         conduct_warning: decision && decision.conduct_warning,
         appreciation: decision && decision.appreciation
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

  defp distinction(%CouncilDecision{distinction_choice: :none}, _proposal), do: nil
  defp distinction(%CouncilDecision{distinction_choice: nil}, proposal), do: proposal
  defp distinction(%CouncilDecision{distinction_choice: choice}, _proposal), do: choice
  defp distinction(nil, proposal), do: proposal

  defp stored(scope, cg, term) do
    ClassCouncil
    |> Ash.Query.for_read(:for_class_term, %{class_group_id: cg.id, term_id: term.id},
      scope: scope
    )
    |> Ash.read_one!()
  end

  defp ensure(scope, cg, term) do
    case stored(scope, cg, term) do
      %ClassCouncil{} = council -> {:ok, council}
      nil -> create(scope, cg, term)
    end
  end

  defp create(scope, cg, term) do
    ClassCouncil
    |> Ash.Changeset.for_create(
      :open,
      %{class_group_id: cg.id, term_id: term.id, held_on: term.class_council_date},
      scope: scope
    )
    |> Ash.create()
    |> case do
      # Another page created it at the same time: the unique identity refused this one.
      {:error, %Ash.Error.Invalid{}} = error ->
        case stored(scope, cg, term) do
          nil -> error
          council -> {:ok, council}
        end

      other ->
        other
    end
  end

  defp unlocked(scope, cg, term),
    do: if(locked?(scope, cg, term), do: {:error, :locked}, else: :ok)

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
