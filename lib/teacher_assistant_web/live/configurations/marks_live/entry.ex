defmodule TeacherAssistantWeb.Configurations.MarksLive.Entry do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistantWeb.TeacherMarksLive.Entry, as: TeacherEntry

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.scope

    active_year =
      Ash.read!(TeacherAssistant.Academics.AcademicYear,
        action: :get_active_year,
        scope: scope
      )
      |> List.first()

    academic_year =
      case active_year do
        nil -> nil
        year ->
          Ash.get!(TeacherAssistant.Academics.AcademicYear, year.id,
            load: [terms: [:sequences]],
            scope: scope
          )
      end

    assignments =
      if academic_year do
        Ash.read!(TeacherAssistant.Academics.SchoolYearSubjectTeacher,
          load: [classroom: [], level_option_subject: :subject],
          scope: scope
        )
        |> Enum.filter(fn assignment ->
          assignment.classroom.academic_year_id == academic_year.id
        end)
      else
        []
      end

    filters = %{
      "academic_year_id" => academic_year && academic_year.id,
      "term_id" => nil,
      "sequence_id" => nil,
      "classroom_id" => nil,
      "level_option_subject_id" => nil
    }

    {:ok,
     socket
     |> assign(:page_title, gettext("Manage Marks"))
     |> assign(:academic_year, academic_year)
     |> assign(:assignments, assignments)
     |> assign(:filters, filters)
     |> assign(:students, [])
     |> assign(:marks_by_student, %{})}
  end

  @impl true
  def render(assigns), do: TeacherEntry.render(assigns)

  @impl true
  def handle_event(event, params, socket), do: TeacherEntry.handle_event(event, params, socket)
end
