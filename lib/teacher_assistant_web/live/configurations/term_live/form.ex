defmodule TeacherAssistantWeb.Configurations.TermLive.Form do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="term-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} />

        <label class="label mt-4">{gettext("Sequences")}</label>
        <table class="table">
          <thead>
            <tr>
              <th>{gettext("Name")}</th>
              <th>{gettext("Start Date")}</th>
              <th>{gettext("End Date")}</th>
              <th></th>
            </tr>
          </thead>
          <.inputs_for :let={sequence_form} field={@form[:sequences]}>
            <tr>
              <td>
                <.input field={sequence_form[:name]} type="text" placeholder={gettext("1st Term")} />
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
        </table>
        <label class="label">
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
          <.button navigate={return_path("show", @term)}>{gettext("Cancel")}</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    term =
      Ash.get!(TeacherAssistant.Academics.Term, id,
        load: [:sequences],
        scope: socket.assigns.scope
      )

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
          |> push_navigate(to: return_path("show", term))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp return_path("show", term),
    do: ~p"/configurations/academic_years/#{term.academic_year_id}/terms/#{term}"
end
