defmodule TeacherAssistantWeb.Configurations.LevelLive.Form do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="level-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} />

        <footer class="mt-4">
          <.button variant="primary" phx-disable-with="Saving...">{gettext("Save Level")}</.button>
          <.button navigate={return_path(@return_to, @level)}>{gettext("Cancel")}</.button>
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
    level = Ash.get!(TeacherAssistant.Academics.Level, id, scope: socket.assigns.scope)

    form =
      AshPhoenix.Form.for_update(level, :update,
        domain: TeacherAssistant.Academics,
        as: "level",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("Edit Level"))
    |> assign(:level, level)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(TeacherAssistant.Academics.Level, :create,
        domain: TeacherAssistant.Academics,
        as: "level",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("New Level"))
    |> assign(:level, nil)
    |> assign(:form, to_form(form))
  end

  @impl true
  def handle_event("validate", %{"level" => level_params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, level_params))}
  end

  def handle_event("save", %{"level" => level_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: level_params) do
      {:ok, level} ->
        socket =
          socket
          |> put_flash(:info, "Level #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path("show", level))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp return_path("index", _level), do: ~p"/configurations/levels"
  defp return_path("show", level), do: ~p"/configurations/levels/#{level}"
end
