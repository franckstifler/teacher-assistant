defmodule TeacherAssistant.Academics.AcademicYear.PrefillHolidays do
  @moduledoc "Spec J1: a new academic year starts with the national holidays that fall inside it."
  use Ash.Resource.Change

  alias TeacherAssistant.Academics.{Holiday, SchoolCalendar}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, year ->
      year.start_date
      |> SchoolCalendar.national_holidays(year.end_date)
      |> Enum.each(fn h ->
        Holiday
        |> Ash.Changeset.for_create(:create, Map.put(h, :academic_year_id, year.id),
          tenant: year.workspace_id,
          authorize?: false
        )
        |> Ash.create!()
      end)

      {:ok, year}
    end)
  end
end
