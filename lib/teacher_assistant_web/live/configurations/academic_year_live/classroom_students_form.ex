defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.ClassroomStudentsForm do
  use TeacherAssistantWeb, :live_view

  require Ash.Query

  @impl true
  def mount(%{"id" => _academic_year_id, "classroom_id" => classroom_id}, _session, socket) do
    scope = socket.assigns.scope

    classroom =
      TeacherAssistant.Academics.Classroom
      |> Ash.Query.filter(id: classroom_id)
      |> Ash.Query.load([:academic_year, level_option: [:full_name]])
      |> Ash.read_one!(scope: scope)

    query =
      Ash.Query.filter(
        TeacherAssistant.Academics.Student,
        classrooms_students.classroom_id == ^classroom_id
      )

    {:ok,
     socket
     |> assign(:page_title, gettext("Manage classroom students"))
     |> assign(:classroom, classroom)
     |> assign(:academic_year, classroom.academic_year)
     |> assign(:students_in_classroom_query, query)}
  end

  @impl true
  def handle_event("add_student", %{"id" => student_id}, socket) do
    %{classroom: classroom, scope: scope} = socket.assigns

    _ =
      Ash.create!(
        TeacherAssistant.Academics.ClassroomStudent,
        %{
          classroom_id: classroom.id,
          student_id: student_id
        },
        # upsert?: true,
        # upsert_identity: :classroom_student,
        scope: scope
      )


    {:noreply,
     Cinder.Table.Refresh.refresh_tables(socket, ["all_students", "students_in_classroom"])}
  end

  def handle_event("remove_student", %{"id" => student_id}, socket) do
    %{classroom: classroom, scope: scope} = socket.assigns

    classroom_student =
      TeacherAssistant.Academics.ClassroomStudent
      |> Ash.Query.filter(classroom_id: classroom.id, student_id: student_id)
      |> Ash.read_one!(scope: scope)

    Ash.destroy!(classroom_student, scope: scope)

    {:noreply,
     Cinder.Table.Refresh.refresh_tables(socket, ["all_students", "students_in_classroom"])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {gettext("Manage classroom students")}
        <:actions>
          <.button navigate={~p"/configurations/academic_years/#{@academic_year}"}>
            <.icon name="hero-arrow-left" /> {gettext("Back to academic year")}
          </.button>
        </:actions>
      </.header>

      <div class="grid gap-6 md:grid-cols-2">
        <div>
          <h3 class="card-title text-sm font-semibold">
            {gettext("All students")}
          </h3>

          <div class="mt-3 max-h-[28rem] overflow-y-auto">
            <Cinder.Table.table
              query_opts={[load: [:full_name]]}
              resource={TeacherAssistant.Academics.Student}
              scope={@scope}
              id="all_students"
            >
              <:col :let={student} field="full_name" filter sort>{student.full_name}</:col>
              <:col :let={student} field="matricule" filter>{student.matricule}</:col>
              <:col :let={student} class="text-right">
                <button
                  type="button"
                  class="btn btn-xs btn-secondary"
                  phx-click="add_student"
                  phx-value-id={student.id}
                  phx-disable-with={gettext("Adding...")}
                >
                  {gettext("Add")}
                </button>
              </:col>
            </Cinder.Table.table>
          </div>
        </div>

        <div>
          <h3 class="ctext-sm font-semibold">
            {gettext("Students in %{classroom}", classroom: @classroom.level_option.full_name)}
          </h3>

          <div class="mt-3 max-h-[28rem] overflow-y-auto">
            <Cinder.Table.table
              query_opts={[load: [:full_name]]}
              query={@students_in_classroom_query}
              scope={@scope}
              id="students_in_classroom"
            >
              <:col :let={student} field="full_name" filter sort>{student.full_name}</:col>
              <:col :let={student} field="matricule" filter>{student.matricule}</:col>
              <:col :let={student} class="text-right">
                <button
                  type="button"
                  class="btn btn-xs btn-danger"
                  phx-click="remove_student"
                  phx-value-id={student.id}
                  phx-disable-with={gettext("Removing...")}
                >
                  {gettext("Remove")}
                </button>
              </:col>
            </Cinder.Table.table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
