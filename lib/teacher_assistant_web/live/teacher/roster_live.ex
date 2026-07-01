defmodule TeacherAssistantWeb.Teacher.RosterLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => ctx_id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with true <- not is_nil(ws),
         {:ok, ctx} <- Academics.fetch_owned_teaching_context(ctx_id, ws) do
      {:ok, load(socket, ws, ctx)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  defp load(socket, ws, ctx) do
    class_group =
      case ctx.class_group_id do
        nil ->
          nil

        id ->
          case Academics.fetch_owned_class_group(id, ws) do
            {:ok, cg} -> cg
            _ -> nil
          end
      end

    students = if class_group, do: Academics.list_students(class_group), else: []

    socket
    |> assign(:ws, ws)
    |> assign(:ctx, ctx)
    |> assign(:class_group, class_group)
    |> assign(:students, students)
    |> assign(:class_form, to_form(%{}, as: :class_group))
    |> assign(:student_form, to_form(%{}, as: :student))
  end

  def handle_event("create_class", %{"class_group" => p}, socket) do
    ws = socket.assigns.ws
    year = Academics.current_academic_year(ws)

    with false <- is_nil(year),
         {:ok, cg} <-
           Academics.create_class_group(ws, year, %{label: p["label"], level: p["level"]}),
         {:ok, ctx} <- Academics.link_class_group(socket.assigns.ctx, cg) do
      {:noreply, load(socket, ws, ctx)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the class"))}
    end
  end

  def handle_event("add_student", %{"student" => p}, socket) do
    cg = socket.assigns.class_group

    with false <- is_nil(cg),
         {:ok, _s} <-
           Academics.add_student(cg, %{
             full_name: p["full_name"],
             sex: String.to_existing_atom(p["sex"]),
             matricule: blank_to(p["matricule"], nil)
           }) do
      {:noreply,
       socket
       |> assign(:students, Academics.list_students(cg))
       |> assign(:student_form, to_form(%{}, as: :student))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not add the student"))}
    end
  end

  def handle_event("delete_student", %{"id" => id}, socket) do
    with {:ok, s} <- Academics.fetch_owned_student(id, socket.assigns.ws),
         :ok <- Academics.delete_student(s) do
      {:noreply, assign(socket, :students, Academics.list_students(socket.assigns.class_group))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not remove the student"))}
    end
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-roster" class="mx-auto max-w-md space-y-5">
        <header>
          <p class="ta-eyebrow">{gettext("Roster")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">
            {@ctx.subject} · {@ctx.level}
          </h1>
        </header>

        <%= if @class_group do %>
          <.form
            for={@student_form}
            id="student-form"
            phx-submit="add_student"
            class="ta-leaf space-y-2"
          >
            <.input field={@student_form[:full_name]} label={gettext("Full name")} />
            <.input
              type="select"
              field={@student_form[:sex]}
              label={gettext("Sex")}
              options={[{gettext("Girl"), "f"}, {gettext("Boy"), "m"}]}
            />
            <.input field={@student_form[:matricule]} label={gettext("Matricule (optional)")} />
            <.button id="student-submit" type="submit" class="btn btn-primary w-full">
              {gettext("Add student")}
            </.button>
          </.form>

          <ul class="space-y-1">
            <li
              :for={s <- @students}
              id={"student-row-#{s.id}"}
              class="ta-leaf flex items-center justify-between"
            >
              <span>{s.full_name}</span>
              <button
                id={"student-delete-#{s.id}"}
                phx-click="delete_student"
                phx-value-id={s.id}
                class="btn btn-ghost btn-xs"
              >
                {gettext("Remove")}
              </button>
            </li>
          </ul>
        <% else %>
          <.form
            for={@class_form}
            id="roster-create-class-form"
            phx-submit="create_class"
            class="ta-leaf space-y-2"
          >
            <p class="text-sm opacity-80">{gettext("Create the class this subject is taught to.")}</p>
            <.input field={@class_form[:label]} label={gettext("Class label")} />
            <.input field={@class_form[:level]} label={gettext("Level")} value={@ctx.level} />
            <.button type="submit" class="btn btn-primary w-full">{gettext("Create class")}</.button>
          </.form>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
