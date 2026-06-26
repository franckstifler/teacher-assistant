defmodule TeacherAssistantWeb.Teacher.ClassroomShowLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign_classroom(socket, id)}
  end

  @impl true
  def handle_event("save_learner", %{"learner" => params}, socket) do
    case Academics.create_learner(socket.assigns.classroom, params) do
      {:ok, _learner} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Learner added"))
         |> assign_classroom(socket.assigns.classroom.id)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not add learner"))}
    end
  end

  defp assign_classroom(socket, id) do
    {:ok, classroom} = Academics.get_personal_classroom(id)

    socket
    |> assign(:classroom, classroom)
    |> assign(:learners, Academics.list_learners(classroom))
    |> assign(:form, to_form(%{}, as: :learner))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="classroom-detail" class="space-y-6">
        <div>
          <.link navigate={~p"/teacher/classrooms"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4" />
            {gettext("Classrooms")}
          </.link>
          <h1 class="mt-4 text-3xl font-semibold">
            {@classroom.class_label} · {@classroom.subject}
          </h1>
          <p class="mt-2 text-sm text-base-content/65">
            {gettext("Manage learners for this personal classroom.")}
          </p>
        </div>

        <div class="grid gap-5 lg:grid-cols-[0.8fr_1.2fr]">
          <section class="ta-panel p-5">
            <.form for={@form} id="learner-form" phx-submit="save_learner" class="space-y-4">
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@form[:first_name]} label={gettext("First name")} />
                <.input field={@form[:last_name]} label={gettext("Last name")} />
              </div>
              <.input field={@form[:identifier]} label={gettext("Identifier")} />
              <button id="save-learner" class="btn btn-primary">
                <.icon name="hero-user-plus" class="size-5" />
                {gettext("Add learner")}
              </button>
            </.form>
          </section>

          <section class="ta-panel p-5">
            <div class="overflow-x-auto">
              <table id="learners-table" class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Name")}</th>
                    <th>{gettext("Identifier")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@learners == []}>
                    <td colspan="2" class="text-base-content/55">{gettext("No learners yet.")}</td>
                  </tr>
                  <tr :for={learner <- @learners} id={"learner-#{learner.id}"}>
                    <td class="font-medium">{learner.full_name}</td>
                    <td>{learner.identifier}</td>
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
