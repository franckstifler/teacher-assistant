defmodule TeacherAssistantWeb.Teacher.RosterLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum

  def mount(%{"id" => ctx_id}, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace

    with true <- not is_nil(ws),
         {:ok, ctx} <- Curriculum.fetch_assigned_teaching_context(ctx_id, scope),
         {:ok, class_group} <- Enrollment.fetch_owned_class_group(ctx.class_group_id, ws) do
      {:ok, load(socket, ws, ctx, class_group)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  defp load(socket, ws, ctx, class_group) do
    students = Enrollment.list_students(class_group)

    socket
    |> assign(:ws, ws)
    |> assign(:ctx, ctx)
    |> assign(:class_group, class_group)
    |> assign(:students, students)
  end

  defp sex_counts(students) do
    Enum.frequencies_by(students, & &1.sex)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="teacher-roster" class="mx-auto max-w-2xl space-y-5">
        <.page_header eyebrow={gettext("Roster")} title={"#{@ctx.subject} · #{@ctx.level}"} />

        <div id="roster-count" class="flex items-center gap-3 text-sm text-base-content/70">
          <span class="font-semibold text-base-content">
            {length(@students)} {gettext("students")}
          </span>
          <span class="ta-num">{Map.get(sex_counts(@students), :f, 0)} {gettext("Filles")}</span>
          <span class="text-base-content/40">·</span>
          <span class="ta-num">{Map.get(sex_counts(@students), :m, 0)} {gettext("Garçons")}</span>
        </div>

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
            </tr>
          </thead>
          <tbody class="block space-y-1 md:table-row-group">
            <tr :for={s <- @students} id={"student-row-#{s.id}"} class="ta-leaf block md:table-row">
              <td class="flex items-center justify-between gap-2 md:table-cell md:px-3 md:py-2">
                <span class="font-semibold md:font-normal">{s.full_name}</span>
              </td>
              <td class="hidden text-sm text-base-content/70 md:table-cell md:px-3 md:py-2">
                {if s.sex == :f, do: gettext("Fille"), else: gettext("Garçon")}
              </td>
              <td class="ta-num hidden text-sm text-base-content/70 md:table-cell md:px-3 md:py-2">
                {s.matricule || "—"}
              </td>
            </tr>
          </tbody>
        </table>

        <.empty_state
          :if={@students == []}
          icon="hero-user-plus"
          title={gettext("No students yet.")}
        />
      </section>
    </Layouts.app>
    """
  end
end
