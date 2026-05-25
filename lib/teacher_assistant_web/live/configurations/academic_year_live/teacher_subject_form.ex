defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.TeacherSubjectForm do
  use TeacherAssistantWeb, :live_view

  require Ash.Query
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mb-6">
        <.link
          navigate={~p"/configurations/academic_years/#{@classroom.academic_year_id}"}
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-arrow-left" /> {gettext("Back to Academic Year")}
        </.link>
      </div>

      <.header>
          <span>
            {gettext("Academic Year")}: {@academic_year.name}
          </span>
          <span class="mx-2 text-base-content/50">•</span>
          <span>
            {gettext("Classroom")}: {@level_option_name}
          </span>
      </.header>

      <div class="card bg-base-100 shadow-xl mt-6">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">
            <.icon name="hero-academic-cap" class="w-6 h-6" />
            {gettext("Teacher Assignments")}
          </h2>

          <div class="overflow-x-auto">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="w-1/3">{gettext("Subject")}</th>
                  <th class="w-1/6 text-center">{gettext("Coefficient")}</th>
                  <th class="w-1/3">{gettext("Assigned Teacher")}</th>
                  <th class="w-1/6 text-center">{gettext("Actions")}</th>
                </tr>
              </thead>
              <tbody>
                <%= for subject <- @subjects do %>
                  <tr class="hover">
                    <td>
                      <div class="flex items-center gap-2">
                        <.icon name="hero-book-open" class="w-5 h-5 text-primary" />
                        <span class="font-semibold">{subject.subject.name}</span>
                      </div>
                    </td>
                    <td class="text-center">
                      <span class="badge badge-primary badge-lg">{subject.coefficient}</span>
                    </td>
                    <td>
                      <%= if assignment = find_assignment(@assignments, subject.id) do %>
                        <div class="flex items-center gap-2">
                          <.icon name="hero-user" class="w-5 h-5 text-success" />
                          <span class="text-success font-medium">{assignment.teacher.email}</span>
                        </div>
                      <% else %>
                        <span class="text-base-content/50 italic">{gettext("Not assigned")}</span>
                      <% end %>
                    </td>
                    <td class="text-center">
                      <%= if assignment = find_assignment(@assignments, subject.id) do %>
                        <button
                          phx-click="remove_assignment"
                          phx-value-id={assignment.id}
                          class="btn btn-error btn-sm"
                        >
                          <.icon name="hero-trash" class="w-4 h-4" />
                          {gettext("Remove")}
                        </button>
                      <% else %>
                        <button
                          phx-click="show_assign_modal"
                          phx-value-subject-id={subject.id}
                          class="btn btn-primary btn-sm"
                        >
                          <.icon name="hero-plus" class="w-4 h-4" />
                          {gettext("Assign")}
                        </button>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%= if Enum.empty?(@subjects) do %>
            <div class="alert alert-warning mt-4">
              <.icon name="hero-exclamation-triangle" />
              <span>
                {gettext(
                  "No subjects configured for this level/option. Please configure subjects first."
                )}
              </span>
            </div>
          <% end %>
        </div>
      </div>

      <%= if @show_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg mb-4">
              {gettext("Assign Teacher to")} {@selected_subject_name}
            </h3>

            <.form for={@assign_form} id="assign-teacher-form" phx-submit="assign_teacher">
              <input type="hidden" name="level_option_subject_id" value={@selected_subject_id} />

              <div class="form-control w-full">
                <label class="label">
                  <span class="label-text font-semibold">{gettext("Select Teacher")}</span>
                </label>
                <select name="teacher_id" class="select select-bordered w-full" required>
                  <option value="">{gettext("Choose a teacher...")}</option>
                  <%= for teacher <- @teachers do %>
                    <option value={teacher.id}>{teacher.email}</option>
                  <% end %>
                </select>
              </div>

              <div class="modal-action">
                <button type="submit" class="btn btn-primary">
                  <.icon name="hero-check" class="w-5 h-5" />
                  {gettext("Assign")}
                </button>
                <button type="button" phx-click="close_modal" class="btn">
                  {gettext("Cancel")}
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => classroom_id}, _session, socket) do
    classroom =
      Ash.get!(TeacherAssistant.Academics.Classroom, classroom_id,
        load: [:academic_year, level_option: [:full_name]],
        scope: socket.assigns.scope
      )

    academic_year = classroom.academic_year
    level_option = classroom.level_option

    subjects =
      TeacherAssistant.Academics.LevelOptionSubject
      |> Ash.Query.filter(level_option_id: level_option.id)
      |> Ash.read!(load: [:subject], scope: socket.assigns.scope)

    assignments =
      TeacherAssistant.Academics.TeachingAssignment
      |> Ash.Query.filter(classroom_id: classroom_id)
      |> Ash.read!(
        load: [:teacher, :level_option_subject],
        scope: socket.assigns.scope
      )

    teachers =
      Ash.read!(TeacherAssistant.Accounts.User, scope: socket.assigns.scope)

    {:ok,
     socket
     |> assign(:classroom, classroom)
     |> assign(:academic_year, academic_year)
     |> assign(:level_option_name, level_option.full_name)
     |> assign(:subjects, subjects)
     |> assign(:assignments, assignments)
     |> assign(:teachers, teachers)
     |> assign(:show_modal, false)
     |> assign(:selected_subject_id, nil)
     |> assign(:selected_subject_name, nil)
     |> assign(:assign_form, to_form(%{}))}
  end

  @impl true
  def handle_event("show_assign_modal", %{"subject-id" => subject_id}, socket) do
    subject = Enum.find(socket.assigns.subjects, &(&1.id == subject_id))

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:selected_subject_id, subject_id)
     |> assign(:selected_subject_name, subject.subject.name)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:selected_subject_id, nil)
     |> assign(:selected_subject_name, nil)}
  end

  def handle_event(
        "assign_teacher",
        %{"teacher_id" => teacher_id, "level_option_subject_id" => subject_id},
        socket
      ) do
    params = %{
      classroom_id: socket.assigns.classroom.id,
      level_option_subject_id: subject_id,
      teacher_id: teacher_id
    }

    case Ash.create(TeacherAssistant.Academics.TeachingAssignment, params,
           scope: socket.assigns.scope
         ) do
      {:ok, _assignment} ->
        assignments =
          TeacherAssistant.Academics.TeachingAssignment
          |> Ash.Query.filter(classroom_id: socket.assigns.classroom.id)
          |> Ash.read!(
            load: [:teacher, :level_option_subject],
            scope: socket.assigns.scope
          )

        {:noreply,
         socket
         |> assign(:assignments, assignments)
         |> assign(:show_modal, false)
         |> assign(:selected_subject_id, nil)
         |> assign(:selected_subject_name, nil)
         |> put_flash(:info, gettext("Teacher assigned successfully"))}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Failed to assign teacher"))}
    end
  end

  def handle_event("remove_assignment", %{"id" => assignment_id}, socket) do
    assignment = Enum.find(socket.assigns.assignments, &(&1.id == assignment_id))

    case Ash.destroy(assignment, scope: socket.assigns.scope) do
      :ok ->
        assignments =
          TeacherAssistant.Academics.TeachingAssignment
          |> Ash.Query.filter(classroom_id: socket.assigns.classroom.id)
          |> Ash.read!(
            load: [:teacher, :level_option_subject],
            scope: socket.assigns.scope
          )
        {:noreply,
         socket
         |> assign(:assignments, assignments)
         |> put_flash(:info, gettext("Teacher assignment removed"))}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Failed to remove assignment"))}
    end
  end

  defp find_assignment(assignments, subject_id) do
    Enum.find(assignments, &(&1.level_option_subject_id == subject_id))
  end
end
