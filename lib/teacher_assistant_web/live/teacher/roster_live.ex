defmodule TeacherAssistantWeb.Teacher.RosterLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => ctx_id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace
    read_only? = socket.assigns.current_scope.current_workspace_type == :school

    with true <- not is_nil(ws),
         {:ok, ctx} <- Academics.fetch_owned_teaching_context(ctx_id, ws) do
      {:ok, load(socket, ws, ctx) |> assign(:read_only?, read_only?)}
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
    |> assign(:undo_student, nil)
    |> assign(:class_form, to_form(%{}, as: :class_group))
    |> assign(:student_form, to_form(%{}, as: :student))
  end

  def handle_event(event, _params, %{assigns: %{read_only?: true}} = socket)
      when event in ~w(create_class add_student delete_student undo_delete) do
    {:noreply, socket}
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
      {:noreply,
       socket
       |> assign(:students, Academics.list_students(socket.assigns.class_group))
       |> assign(:undo_student, %{full_name: s.full_name, sex: s.sex, matricule: s.matricule})}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not remove the student"))}
    end
  end

  def handle_event("undo_delete", _params, socket) do
    cg = socket.assigns.class_group

    case socket.assigns[:undo_student] do
      nil ->
        {:noreply, socket}

      attrs ->
        case Academics.add_student(cg, attrs) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:students, Academics.list_students(cg))
             |> assign(:undo_student, nil)}

          _ ->
            {:noreply, put_flash(socket, :error, gettext("Could not restore the student"))}
        end
    end
  end

  defp sex_counts(students) do
    Enum.frequencies_by(students, & &1.sex)
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-roster" class="mx-auto max-w-2xl space-y-5">
        <.page_header eyebrow={gettext("Roster")} title={"#{@ctx.subject} · #{@ctx.level}"} />

        <%= if @class_group do %>
          <div id="roster-count" class="flex items-center gap-3 text-sm text-base-content/70">
            <span class="font-semibold text-base-content">
              {length(@students)} {gettext("students")}
            </span>
            <span class="ta-num">{Map.get(sex_counts(@students), :f, 0)} {gettext("Filles")}</span>
            <span class="text-base-content/40">·</span>
            <span class="ta-num">{Map.get(sex_counts(@students), :m, 0)} {gettext("Garçons")}</span>
          </div>

          <div
            :if={!@read_only? && @undo_student}
            id="student-undo-bar"
            class="ta-leaf flex items-center justify-between gap-2 text-sm"
          >
            <span>{gettext("%{name} removed.", name: @undo_student.full_name)}</span>
            <button id="student-undo" phx-click="undo_delete" class="btn btn-outline btn-xs">
              {gettext("Undo")}
            </button>
          </div>

          <.form
            :if={!@read_only?}
            for={@student_form}
            id="student-form"
            phx-submit="add_student"
            class="ta-leaf space-y-2"
          >
            <fieldset class="space-y-2">
              <legend class="ta-eyebrow">{gettext("Add a student")}</legend>
              <.input field={@student_form[:full_name]} label={gettext("Full name")} />
              <div class="grid gap-2 sm:grid-cols-2">
                <.input
                  type="select"
                  field={@student_form[:sex]}
                  label={gettext("Sex")}
                  options={[{gettext("Girl"), "f"}, {gettext("Boy"), "m"}]}
                />
                <.input
                  field={@student_form[:matricule]}
                  label={gettext("Matricule (optional)")}
                  inputmode="numeric"
                />
              </div>
            </fieldset>
            <.button id="student-submit" type="submit" class="btn btn-primary w-full">
              {gettext("Add student")}
            </.button>
          </.form>

          <table
            :if={@students != []}
            id="student-table"
            class="w-full border-separate border-spacing-y-1"
          >
            <caption class="sr-only">{gettext("Class roster")}</caption>
            <thead class="hidden md:table-header-group">
              <tr class="text-left">
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Élève")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Sexe")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Matricule")}</th>
                <th scope="col" class="px-3 pb-1">
                  <span class="sr-only">{gettext("Actions")}</span>
                </th>
              </tr>
            </thead>
            <tbody class="block space-y-1 md:table-row-group">
              <tr :for={s <- @students} id={"student-row-#{s.id}"} class="ta-leaf block md:table-row">
                <td class="flex items-center justify-between gap-2 md:table-cell md:px-3 md:py-2">
                  <span class="font-semibold md:font-normal">{s.full_name}</span>
                  <button
                    :if={!@read_only?}
                    id={"student-delete-#{s.id}"}
                    phx-click="delete_student"
                    phx-value-id={s.id}
                    data-confirm={gettext("Remove %{name} from the roster?", name: s.full_name)}
                    class="btn btn-ghost btn-xs md:hidden"
                  >
                    {gettext("Remove")}
                  </button>
                </td>
                <td class="hidden text-sm text-base-content/70 md:table-cell md:px-3 md:py-2">
                  {if s.sex == :f, do: gettext("Fille"), else: gettext("Garçon")}
                </td>
                <td class="ta-num hidden text-sm text-base-content/70 md:table-cell md:px-3 md:py-2">
                  {s.matricule || "—"}
                </td>
                <td class="hidden text-right md:table-cell md:px-3 md:py-2">
                  <button
                    :if={!@read_only?}
                    id={"student-delete-md-#{s.id}"}
                    phx-click="delete_student"
                    phx-value-id={s.id}
                    data-confirm={gettext("Remove %{name} from the roster?", name: s.full_name)}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Remove")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <.empty_state
            :if={@students == []}
            icon="hero-user-plus"
            title={gettext("No students yet — add your first with the form above.")}
          />
        <% else %>
          <.form
            :if={!@read_only?}
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
          <.empty_state
            :if={@read_only?}
            icon="hero-user-group"
            title={gettext("No class linked to this assignment yet.")}
          />
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
