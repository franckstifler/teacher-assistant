defmodule TeacherAssistant.MarksFixtures do
  @moduledoc """
  A verified school with one class, one course taught by a plain teacher, an
  assessment in the first séquence and two students — the D3 (journal, lock,
  corrections) world.
  """
  alias TeacherAssistant.{Assessment, Enrollment, Organization, TeacherFixtures}

  def marks_world(attrs \\ %{}) do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()

    %{scope: t, teaching_context: tc, class_group: cg} =
      TeacherFixtures.school_teacher_fixture(head)

    [seq | _] = Organization.list_sequences(head, year)

    {:ok, s1} = Enrollment.add_student(head, cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Enrollment.add_student(head, cg, %{full_name: "Beti", sex: :f})

    {:ok, a} =
      Assessment.create_assessment(t, tc, seq, %{
        label: attrs[:label] || "Devoir 1",
        max_score: Decimal.new(20)
      })

    %{head: head, t: t, tc: tc, cg: cg, year: year, seq: seq, a: a, s1: s1, s2: s2}
  end

  @doc """
  Moves the world's first séquence so its grade-entry deadline is `deadline` (before
  the test clock's date = locked). The end date moves too, since a deadline never
  precedes it.
  """
  def lock!(%{head: head, seq: seq}, %Date{} = deadline) do
    end_date = Enum.max([seq.start_date, Date.add(deadline, -1)], Date)

    {:ok, seq} =
      seq
      |> Ash.Changeset.for_update(:update, %{end_date: end_date, entry_deadline: deadline},
        scope: head
      )
      |> Ash.update()

    seq
  end

  @doc """
  Starts every séquence of `year` that the test clock has not reached yet (its start
  moves to today, its end stays), so a test can record marks across the whole year.
  Returns the séquences, in order.
  """
  def start_sequences!(scope, year) do
    today = TeacherAssistant.Academics.Reference.today()

    for seq <- Organization.list_sequences(scope, year) do
      if Date.after?(seq.start_date, today) do
        {:ok, seq} =
          seq
          |> Ash.Changeset.for_update(:update, %{start_date: today}, scope: scope)
          |> Ash.update()

        seq
      else
        seq
      end
    end
  end
end
