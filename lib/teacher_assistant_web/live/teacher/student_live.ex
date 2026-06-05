defmodule TeacherAssistantWeb.Teacher.StudentLive do
  use TeacherAssistantWeb, :live_view

  require Ash.Query

  alias TeacherAssistant.Academics.Classroom
  alias TeacherAssistant.Academics.ClassroomStudent
  alias TeacherAssistant.Academics.PersonalWorkspace

  @impl true
  def mount(_params, _session, socket) do
    classrooms = list_classrooms(socket.assigns.scope)
    selected_classroom_id = classrooms |> List.first() |> then(&(&1 && &1.id))

    {:ok,
     socket
     |> assign(:page_title, gettext("Personal students"))
     |> assign(:classrooms, classrooms)
     |> assign(:selected_classroom_id, selected_classroom_id)
     |> assign(:student_form, to_form(%{}, as: :student))
     |> assign(
       :import_form,
       to_form(%{"classroom_id" => selected_classroom_id, "csv" => ""}, as: :import)
     )
     |> assign(:import_result, nil)
     |> load_students()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="personal-students" class="space-y-6">
        <.header>
          {gettext("Personal students")}
          <:subtitle>
            {gettext("Manage the private roster used by your personal marks and attendance tools.")}
          </:subtitle>
          <:actions>
            <.link
              id="open-personal-setup"
              navigate={~p"/teacher/setup"}
              class="btn btn-secondary btn-sm"
            >
              <.icon name="hero-cog-6-tooth" class="size-4" />
              {gettext("Setup")}
            </.link>
          </:actions>
        </.header>

        <div :if={@classrooms == []} id="personal-students-empty" class="ta-panel p-8 text-center">
          <.icon name="hero-user-group" class="mx-auto size-10 text-base-content/30" />
          <p class="mt-3 text-sm text-base-content/60">
            {gettext("Complete your personal setup before adding students.")}
          </p>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary btn-sm mt-4">
            {gettext("Complete setup")}
          </.link>
        </div>

        <div :if={@classrooms != []} class="grid gap-6 lg:grid-cols-[minmax(18rem,24rem)_1fr]">
          <aside class="space-y-4">
            <.form for={@import_form} id="classroom-selector-form" phx-change="select_classroom">
              <.input
                field={@import_form[:classroom_id]}
                type="select"
                label={gettext("Class")}
                options={classroom_options(@classrooms)}
              />
            </.form>

            <.form
              for={@student_form}
              id="personal-student-form"
              phx-submit="create_student"
              class="ta-panel space-y-3 p-4"
            >
              <input type="hidden" name="student[classroom_id]" value={@selected_classroom_id} />
              <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-1">
                <.input field={@student_form[:first_name]} label={gettext("First name")} />
                <.input field={@student_form[:last_name]} label={gettext("Last name")} />
              </div>
              <.input field={@student_form[:matricule]} label={gettext("Matricule")} />
              <.input
                field={@student_form[:gender]}
                type="select"
                label={gettext("Gender")}
                options={[{gettext("Male"), "male"}, {gettext("Female"), "female"}]}
              />
              <.button class="btn btn-primary btn-sm w-full">
                <.icon name="hero-plus" class="size-4" />
                {gettext("Add student")}
              </.button>
            </.form>

            <.form
              for={@import_form}
              id="student-import-form"
              phx-submit="import_students"
              class="ta-panel space-y-3 p-4"
            >
              <input type="hidden" name="import[classroom_id]" value={@selected_classroom_id} />
              <.input
                field={@import_form[:csv]}
                type="textarea"
                label={gettext("CSV exported from Excel")}
                placeholder="first_name,last_name,matricule,gender\nAlice,Fotso,A001,female"
              />
              <.button class="btn btn-secondary btn-sm w-full">
                <.icon name="hero-arrow-up-tray" class="size-4" />
                {gettext("Import CSV")}
              </.button>
            </.form>

            <div :if={@import_result} id="student-import-result" class="alert alert-info text-sm">
              <.icon name="hero-information-circle" class="size-5" />
              <span>
                {gettext("Imported %{count} students", count: length(@import_result.created))}
                <%= if @import_result.invalid != [] do %>
                  · {gettext("%{count} rows need attention", count: length(@import_result.invalid))}
                <% end %>
              </span>
            </div>
          </aside>

          <section class="ta-panel overflow-hidden">
            <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
              <h2 class="text-base font-semibold">{gettext("Roster")}</h2>
              <span id="personal-student-count" class="badge badge-primary">
                {length(@students)}
              </span>
            </div>

            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>{gettext("Name")}</th>
                    <th>{gettext("Matricule")}</th>
                    <th class="text-right">{gettext("Actions")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@students == []}>
                    <td colspan="3" class="py-8 text-center text-sm text-base-content/55">
                      {gettext("No students in this class yet.")}
                    </td>
                  </tr>
                  <tr :for={student <- @students} id={"personal-student-#{student.id}"}>
                    <td class="font-medium">{student.full_name}</td>
                    <td>{student.matricule}</td>
                    <td class="text-right">
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="delete_student"
                        phx-value-id={student.id}
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("select_classroom", %{"import" => %{"classroom_id" => classroom_id}}, socket) do
    {:noreply,
     socket
     |> assign(:selected_classroom_id, classroom_id)
     |> assign(:import_form, to_form(%{"classroom_id" => classroom_id, "csv" => ""}, as: :import))
     |> load_students()}
  end

  def handle_event("create_student", %{"student" => params}, socket) do
    classroom_id = params["classroom_id"] || socket.assigns.selected_classroom_id

    case PersonalWorkspace.create_student(socket.assigns.scope, classroom_id, params) do
      {:ok, _student} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Student added"))
         |> assign(:student_form, to_form(%{}, as: :student))
         |> load_students()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Student could not be added"))}
    end
  end

  def handle_event("import_students", %{"import" => params}, socket) do
    classroom_id = params["classroom_id"] || socket.assigns.selected_classroom_id

    case PersonalWorkspace.import_students(
           socket.assigns.scope,
           classroom_id,
           params["csv"] || ""
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Student import completed"))
         |> assign(:import_result, result)
         |> assign(
           :import_form,
           to_form(%{"classroom_id" => classroom_id, "csv" => ""}, as: :import)
         )
         |> load_students()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Students could not be imported"))}
    end
  end

  def handle_event("delete_student", %{"id" => student_id}, socket) do
    case PersonalWorkspace.delete_student(socket.assigns.scope, student_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Student removed"))
         |> load_students()}

      _error ->
        {:noreply, put_flash(socket, :error, gettext("Student could not be removed"))}
    end
  end

  defp list_classrooms(scope) do
    Classroom
    |> Ash.Query.load(level_option: [:full_name])
    |> Ash.read!(scope: scope)
  end

  defp load_students(%{assigns: %{selected_classroom_id: nil}} = socket) do
    assign(socket, :students, [])
  end

  defp load_students(socket) do
    students =
      ClassroomStudent
      |> Ash.Query.filter(classroom_id == ^socket.assigns.selected_classroom_id)
      |> Ash.Query.load(student: [:full_name])
      |> Ash.read!(scope: socket.assigns.scope)
      |> Enum.map(& &1.student)
      |> Enum.sort_by(&to_string(&1.full_name))

    assign(socket, :students, students)
  end

  defp classroom_options(classrooms) do
    Enum.map(classrooms, fn classroom ->
      {classroom.level_option.full_name, classroom.id}
    end)
  end
end
