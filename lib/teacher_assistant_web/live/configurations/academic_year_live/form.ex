defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.Form do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="academic_year-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} />
        <div class="grid grid-cols-1 gap-x-4 md:grid-cols-2">
          <.input field={@form[:start_date]} type="date" label={gettext("Start date")} />
          <.input field={@form[:end_date]} type="date" label={gettext("End date")} />
        </div>
        <div class="divider" />
        <label class="font-semibold text-2xl">{gettext("Terms")}</label>
        <table class="table mt-4">
          <thead>
            <tr>
              <th>{gettext("Name")}</th>
              <th>{gettext("Start Date")}</th>
              <th>{gettext("End Date")}</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <.inputs_for :let={term_form} field={@form[:terms]}>
              <tr>
                <td>
                  <.input field={term_form[:name]} type="text" placeholder={gettext("1st Term")} />
                </td>
                <td>
                  <.input field={term_form[:start_date]} type="date" />
                </td>
                <td>
                  <.input field={term_form[:end_date]} type="date" />
                </td>
                <td>
                  <label class="label">
                    <input
                      type="checkbox"
                      name={"#{@form.name}[_drop_terms][]"}
                      value={term_form.index}
                      class="hidden"
                    />

                    <.icon name="hero-x-mark" class="text-error" />
                  </label>
                </td>
              </tr>
              <tr>
                <td colspan="4 mr-8">
                  <div class="overflow-x-auto bg-secondary/10 p-4 border border-base-content/5 rounded-box">
                    <label class="label mt-2">{gettext("Sequences")}</label>
                    <table class="table table-sm">
                      <thead>
                        <tr>
                          <th>{gettext("Name")}</th>
                          <th>{gettext("Start")}</th>
                          <th>{gettext("End")}</th>
                          <th></th>
                        </tr>
                      </thead>
                      <tbody>
                        <.inputs_for :let={sequence_form} field={term_form[:sequences]}>
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
                    <label class="label mt-2.5">
                      <input
                        type="checkbox"
                        name={"#{term_form.name}[_add_sequences]"}
                        value="end"
                        class="hidden"
                      />
                      <.icon name="hero-plus" />{gettext("Add Sequence")}
                    </label>
                  </div>
                </td>
              </tr>
            </.inputs_for>
          </tbody>
        </table>
        <label class="label my-2">
          <input type="checkbox" name={"#{@form.name}[_add_terms]"} value="end" class="hidden" />
          <.icon name="hero-plus" />{gettext("Add Term")}
        </label>

        <footer class="mt-6">
          <.button variant="primary" phx-disable-with="Saving...">
            {gettext("Save Academic Year")}
          </.button>
          <.button navigate={return_path(@return_to, @academic_year)}>{gettext("Cancel")}</.button>
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
    academic_year =
      Ash.get!(TeacherAssistant.Academics.AcademicYear, id,
        load: [terms: [:sequences]],
        scope: socket.assigns.scope
      )

    form =
      AshPhoenix.Form.for_update(academic_year, :update,
        domain: TeacherAssistant.Academics,
        as: "academic_year",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("Edit Academic Year"))
    |> assign(:academic_year, academic_year)
    |> assign(:form, to_form(form))
  end

  defp apply_action(socket, :new, _params) do
    form =
      AshPhoenix.Form.for_create(TeacherAssistant.Academics.AcademicYear, :create,
        domain: TeacherAssistant.Academics,
        extensions: [AshArchival.Resource],
        as: "academic_year",
        scope: socket.assigns.scope,
        forms: [auto?: true]
      )

    socket
    |> assign(:page_title, gettext("New Academic Year"))
    |> assign(:academic_year, nil)
    |> assign(:form, to_form(form))
  end

  @impl true
  def handle_event("validate", %{"academic_year" => academic_year_params}, socket) do
    {:noreply,
     assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, academic_year_params))}
  end

  def handle_event("save", %{"academic_year" => academic_year_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: academic_year_params) do
      {:ok, academic_year} ->
        socket =
          socket
          |> put_flash(:info, "Academic Year #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path("show", academic_year))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp return_path("index", _academic_year), do: ~p"/configurations/academic_years"
  defp return_path("show", academic_year), do: ~p"/configurations/academic_years/#{academic_year}"
end
