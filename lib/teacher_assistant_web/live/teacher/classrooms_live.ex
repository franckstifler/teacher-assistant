defmodule TeacherAssistantWeb.Teacher.ClassroomsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_classrooms(socket)}
  end

  @impl true
  def handle_event("save", %{"classroom" => params}, socket) do
    scope = socket.assigns.current_scope

    case Academics.create_personal_classroom(
           scope.current_workspace,
           scope.current_academic_year,
           params
         ) do
      {:ok, _classroom} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Classroom created"))
         |> assign_classrooms()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create classroom"))}
    end
  end

  defp assign_classrooms(socket) do
    workspace = socket.assigns.current_scope.current_workspace
    academic_year = socket.assigns.current_scope.current_academic_year

    socket
    |> assign(:academic_year, academic_year)
    |> assign(
      :classrooms,
      if(academic_year, do: Academics.list_personal_classrooms(workspace), else: [])
    )
    |> assign(:form, to_form(%{}, as: :classroom))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="classrooms-index" class="space-y-6">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="ta-section-label">{gettext("Personal classes")}</p>
            <h1 class="text-3xl font-semibold">{gettext("Classrooms")}</h1>
            <p class="mt-2 text-sm text-base-content/65">
              {gettext("Create one classroom per class and subject you teach.")}
            </p>
          </div>
        </div>

        <div :if={!@academic_year} id="classroom-year-gate" class="ta-panel p-6">
          <h2 class="font-semibold">{gettext("Academic year required")}</h2>
          <p class="mt-1 text-sm text-base-content/65">
            {gettext("Create an academic year before adding classrooms.")}
          </p>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary mt-4">
            {gettext("Create academic year")}
          </.link>
        </div>

        <div :if={@academic_year} class="grid gap-5 lg:grid-cols-[0.8fr_1.2fr]">
          <section class="ta-panel p-5">
            <.form for={@form} id="classroom-form" phx-submit="save" class="space-y-4">
              <.input field={@form[:class_label]} label={gettext("Class label")} placeholder="Form 3" />
              <.input field={@form[:subject]} label={gettext("Subject")} placeholder="Mathematics" />
              <button id="save-classroom" class="btn btn-primary">
                <.icon name="hero-plus" class="size-5" />
                {gettext("Add classroom")}
              </button>
            </.form>
          </section>

          <section class="ta-panel p-5">
            <div class="overflow-x-auto">
              <table id="classrooms-table" class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Class")}</th>
                    <th>{gettext("Subject")}</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@classrooms == []}>
                    <td colspan="3" class="text-base-content/55">
                      {gettext("No classroom yet.")}
                    </td>
                  </tr>
                  <tr :for={classroom <- @classrooms} id={"classroom-#{classroom.id}"}>
                    <td class="font-medium">{classroom.class_label}</td>
                    <td>{classroom.subject}</td>
                    <td class="text-right">
                      <.link
                        navigate={~p"/teacher/classrooms/#{classroom.id}"}
                        class="btn btn-ghost btn-xs"
                      >
                        {gettext("Learners")}
                      </.link>
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
