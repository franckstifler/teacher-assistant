defmodule TeacherAssistantWeb.Configurations.TermLive.Form do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage term records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="term-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:start_date]} type="date" label={gettext("Start Date")} />
        <.input field={@form[:end_date]} type="date" label={gettext("End Date")} />
        <.inputs_for field={@form[:sequences]}>
          <label class="label mt-4">{gettext("Sequences")}</label>
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Name")}</th>
                <th>{gettext("Start Date")}</th>
                <th>{gettext("End Date")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <.inputs_for :let={sequence_form} field={@form[:sequences]}>
                <tr>
                  <td>
                    <.input
                      field={sequence_form[:name]}
                      type="text"
                      placeholder={gettext("1st Sequence")}
                    />
                  </td>
                  <td>
                    <.input field={sequence_form[:start_date]} type="date" />
                  </td>
                  <td>
                    <.input field={sequence_form[:end_date]} type="date" />
                  </td>
                  <td>
                    <label class="label">
                      <input
                        type="checkbox"
                        name={"#{@form.name}[_drop_sequences][]"}
                        value={sequence_form.index}
                        class="hidden"
                      />

                      <.icon name="hero-x-mark" class="text-error" />
                    </label>
                  </td>
                </tr>
              </.inputs_for>
            </tbody>
          </table>
        </.inputs_for>
        <label class="label mt-2">
          <input
            type="checkbox"
            name={"#{@form.name}[_add_sequences]"}
            value="end"
            class="hidden"
          />
          <.icon name="hero-plus" />{gettext("Add Sequence")}
        </label>

        <footer class="mt-4">
          <.button variant="primary" phx-disable-with="Saving...">{gettext("Save Term")}</.button>
          <.button navigate={return_path(@return_to, @term)}>{gettext("Cancel")}</.button>
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
    term = Ash.get!(TeacherAssistant.Academics.Term, id, load: [:sequences], scope: socket.assigns.scope)

    form =
      AshPhoenix.Form.for_update(term, :update,
        domain: TeacherAssistant.Academics,
        as: "term",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("Edit Term"))
    |> assign(:term, term)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(TeacherAssistant.Academics.Term, :create,
        domain: TeacherAssistant.Academics,
        as: "term",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("New Term"))
    |> assign(:term, nil)
    |> assign(:form, to_form(form))
  end

  @impl true
  def handle_event("validate", %{"term" => term_params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, term_params))}
  end

  def handle_event("save", %{"term" => term_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: term_params) do
      {:ok, term} ->
        socket =
          socket
          |> put_flash(:info, "Term #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path(socket.assigns.return_to, term))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp return_path("index", _term), do: ~p"/configurations/terms"
  defp return_path("show", term), do: ~p"/configurations/terms/#{term}"
end
