defmodule TeacherAssistantWeb.Configurations.OptionLive.Form do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="option-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} />

        <footer class="mt-4">
          <.button variant="primary" phx-disable-with="Saving...">{gettext("Save Option")}</.button>
          <.button navigate={return_path(@return_to, @option)}>{gettext("Cancel")}</.button>
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
    option = Ash.get!(TeacherAssistant.Academics.Option, id, scope: socket.assigns.scope)

    form =
      AshPhoenix.Form.for_update(option, :update,
        domain: TeacherAssistant.Academics,
        as: "option",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("Edit Option"))
    |> assign(:option, option)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(TeacherAssistant.Academics.Option, :create,
        domain: TeacherAssistant.Academics,
        as: "option",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("New Option"))
    |> assign(:option, nil)
    |> assign(:form, to_form(form))
  end

  @impl true
  def handle_event("validate", %{"option" => option_params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, option_params))}
  end

  def handle_event("save", %{"option" => option_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: option_params) do
      {:ok, option} ->
        socket =
          socket
          |> put_flash(:info, "Option #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path("show", option))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp return_path("index", _option), do: ~p"/configurations/options"
  defp return_path("show", option), do: ~p"/configurations/options/#{option}"
end
