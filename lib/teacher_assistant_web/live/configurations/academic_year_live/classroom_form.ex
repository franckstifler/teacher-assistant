defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.ClassRoomForm do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="academic_year-form" phx-change="validate" phx-submit="save">
        <h3 class="text-xl font-semibold my-4">{gettext("Classes")}</h3>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <%= for level_option <- @levels_options do %>
            <label class="label">
              <input
                class="checkbox"
                name={"#{@form.name}[levels_options][]"}
                value={level_option.id}
                checked={is_checked?(AshPhoenix.Form.value(@form, :levels_options), level_option.id)}
                type="checkbox"
              />
              {level_option.full_name}
            </label>
          <% end %>
        </div>

        <footer class="mt-6">
          <.button variant="primary" phx-disable-with="Saving...">
            {gettext("Save Classrooms")}
          </.button>
          <.button navigate={return_path("show", @academic_year)}>{gettext("Cancel")}</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    academic_year =
      Ash.get!(TeacherAssistant.Academics.AcademicYear, id,
        load: [:classrooms],
        scope: socket.assigns.scope
      )

    levels_options =
      Ash.read!(TeacherAssistant.Academics.LevelOption,
        load: [:full_name],
        scope: socket.assigns.scope
      )

    form =
      AshPhoenix.Form.for_update(academic_year, :manage_classrooms,
        domain: TeacherAssistant.Academics,
        as: "academic_year",
        scope: socket.assigns.scope,
        forms: [auto?: true],
        prepare_source: fn changeset ->
          levels_options = Enum.map(academic_year.classrooms, & &1.id)
          Ash.Changeset.set_argument(changeset, :levels_options, levels_options)
        end
      )

    {:ok,
     socket
     |> assign(:page_title, gettext("Edit Year Classrooms"))
     |> assign(:levels_options, levels_options)
     |> assign(:academic_year, academic_year)
     |> assign(:form, to_form(form))}
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
          |> put_flash(:info, gettext("Classrooms updated successfully"))
          |> push_navigate(to: return_path("show", academic_year))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def is_checked?(option_ids, option_id) do
    Enum.any?(option_ids, &(&1 == option_id))
  end

  defp return_path("show", academic_year), do: ~p"/configurations/academic_years/#{academic_year}"
end
