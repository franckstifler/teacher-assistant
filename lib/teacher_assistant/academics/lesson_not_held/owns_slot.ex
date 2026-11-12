defmodule TeacherAssistant.Academics.LessonNotHeld.OwnsSlot do
  @moduledoc """
  Roll call outside the timetable (spec 2026-11-12): the actor may mark a lesson
  « déplacé » only when the class's timetable slot at that period, on that weekday, is
  theirs — its teaching context has them as teacher, or belongs to their combined
  course. Read without an actor: the policy decides, the slot is a fact.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias TeacherAssistant.Academics.{SchoolCalendar, TimetableSlot}

  @impl true
  def describe(_opts), do: "the actor teaches the class's timetable slot at that period"

  @impl true
  def match?(%{id: actor_id}, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    class_group_id = Ash.Changeset.get_attribute(changeset, :class_group_id)
    period_id = Ash.Changeset.get_attribute(changeset, :period_id)
    date = Ash.Changeset.get_attribute(changeset, :date)

    with true <- is_binary(class_group_id) and is_binary(period_id) and match?(%Date{}, date),
         day when not is_nil(day) <- SchoolCalendar.weekday(date) do
      TimetableSlot
      |> Ash.Query.filter(
        class_group_id == ^class_group_id and period_id == ^period_id and day == ^day
      )
      |> Ash.Query.load(teaching_context: [:combined_course])
      |> Ash.read!(tenant: changeset.tenant, authorize?: false)
      |> Enum.any?(fn %{teaching_context: tc} ->
        tc != nil and
          (tc.teacher_user_id == actor_id or
             (tc.combined_course != nil and tc.combined_course.teacher_user_id == actor_id))
      end)
    else
      _ -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
