defmodule TeacherAssistantWeb.Configurations.StudentLive.Form do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="student-form" phx-change="validate" phx-submit="save">
        <div class="grid grid-cols-1 gap-x-4 md:grid-cols-2">
          <.input field={@form[:first_name]} type="text" label={gettext("First name")} />
          <.input field={@form[:last_name]} type="text" label={gettext("Last name")} />
        </div>

        <div class="grid grid-cols-1 gap-x-4 md:grid-cols-3">
          <.input field={@form[:matricule]} type="text" label={gettext("Matricule")} />
          <.input field={@form[:date_of_birth]} type="date" label={gettext("Date of birth")} />
          <.input field={@form[:place_of_birth]} type="text" label={gettext("Place of birth")} />
        </div>

        <.input
          field={@form[:gender]}
          type="select"
          label={gettext("Gender")}
          prompt={gettext("Select gender")}
          options={gender_options()}
        />

        <footer class="mt-4 flex gap-2">
          <.button variant="primary" phx-disable-with="Saving...">
            {gettext("Save Student")}
          </.button>

          <.button navigate={return_path(@return_to, @student)}>
            {gettext("Cancel")}
          </.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    student = Ash.get!(TeacherAssistant.Academics.Student, id, scope: socket.assigns.scope)

    form =
      AshPhoenix.Form.for_update(student, :update,
        domain: TeacherAssistant.Academics,
        as: "student",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("Edit Student"))
    |> assign(:student, student)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(TeacherAssistant.Academics.Student, :create,
        domain: TeacherAssistant.Academics,
        as: "student",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("New Student"))
    |> assign(:student, nil)
    |> assign(:form, to_form(form))
  end

  @impl true
  def handle_event("validate", %{"student" => student_params}, socket) do
    {:noreply,
     assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, student_params))}
  end

  def handle_event("save", %{"student" => student_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: student_params) do
      {:ok, student} ->
        socket =
          socket
          |> put_flash(:info, "Student #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path("show", student))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp gender_options do
    [
      {gettext("Male"), :male},
      {gettext("Female"), :female}
    ]
  end

  defp return_path("index", _student), do: ~p"/configurations/students"
  defp return_path("show", student), do: ~p"/configurations/students/#{student}"
end
