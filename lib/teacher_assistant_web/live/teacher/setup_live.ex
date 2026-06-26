defmodule TeacherAssistantWeb.Teacher.SetupLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_setup(socket)}
  end

  @impl true
  def handle_event("save", %{"academic_year" => params}, socket) do
    case Academics.create_academic_year(socket.assigns.current_scope.current_workspace, params) do
      {:ok, _year} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Academic year created"))
         |> push_navigate(to: ~p"/teacher/classrooms")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create academic year"))}
    end
  end

  defp assign_setup(socket) do
    workspace = socket.assigns.current_scope.current_workspace

    socket
    |> assign(:academic_years, Academics.list_academic_years(workspace))
    |> assign(:form, to_form(%{}, as: :academic_year))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="academic-year-setup" class="space-y-6">
        <div>
          <p class="ta-section-label">{gettext("Setup")}</p>
          <h1 class="text-3xl font-semibold">{gettext("Academic year")}</h1>
          <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/65">
            {gettext(
              "Create the school year that will hold your personal classrooms, roll calls, and progress entries."
            )}
          </p>
        </div>

        <div class="grid gap-5 lg:grid-cols-[0.9fr_1.1fr]">
          <section class="ta-panel p-5">
            <.form for={@form} id="academic-year-form" phx-submit="save" class="space-y-4">
              <.input field={@form[:name]} label={gettext("Name")} placeholder="2026-2027" />
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@form[:start_date]} type="date" label={gettext("Start date")} />
                <.input field={@form[:end_date]} type="date" label={gettext("End date")} />
              </div>
              <button id="save-academic-year" class="btn btn-primary">
                <.icon name="hero-check" class="size-5" />
                {gettext("Save academic year")}
              </button>
            </.form>
          </section>

          <section id="academic-years-table" class="ta-panel p-5">
            <h2 class="font-semibold">{gettext("Your academic years")}</h2>
            <div class="mt-4 overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Name")}</th>
                    <th>{gettext("Dates")}</th>
                    <th>{gettext("Status")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@academic_years == []}>
                    <td colspan="3" class="text-base-content/55">
                      {gettext("No academic year yet.")}
                    </td>
                  </tr>
                  <tr :for={year <- @academic_years} id={"academic-year-#{year.id}"}>
                    <td class="font-medium">{year.name}</td>
                    <td>{year.start_date} - {year.end_date}</td>
                    <td>
                      <span class={["badge badge-sm", year.active && "badge-success"]}>
                        {if(year.active, do: gettext("Current"), else: gettext("Archived"))}
                      </span>
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
end
