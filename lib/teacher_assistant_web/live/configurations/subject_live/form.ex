defmodule TeacherAssistantWeb.Configurations.SubjectLive.Form do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="subject-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input
          field={@form[:default_coefficient]}
          type="number"
          label={gettext("Default coefficient")}
        />
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} />

        <footer class="mt-4">
          <.button variant="primary" phx-disable-with="Saving...">{gettext("Save Subject")}</.button>
          <.button navigate={return_path(@return_to, @subject)}>{gettext("Cancel")}</.button>
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
    subject =
      Ash.get!(TeacherAssistant.Academics.Subject, id, scope: socket.assigns.scope)

    form =
      AshPhoenix.Form.for_update(subject, :update,
        domain: TeacherAssistant.Academics,
        as: "subject",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("Edit Subject"))
    |> assign(:subject, subject)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(TeacherAssistant.Academics.Subject, :create,
        domain: TeacherAssistant.Academics,
        as: "subject",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("New Subject"))
    |> assign(:subject, nil)
    |> assign(:form, to_form(form))
  end

  @impl true
  def handle_event("validate", %{"subject" => subject_params}, socket) do
    {:noreply,
     assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, subject_params))}
  end

  def handle_event("save", %{"subject" => subject_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: subject_params) do
      {:ok, subject} ->
        socket =
          socket
          |> put_flash(:info, "Subject #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path("show", subject))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def is_checked?(option_ids, option_id) do
    Enum.any?(option_ids, &(&1 == option_id))
  end

  defp return_path("index", _subject), do: ~p"/configurations/subjects"
  defp return_path("show", subject), do: ~p"/configurations/subjects/#{subject}"
end
