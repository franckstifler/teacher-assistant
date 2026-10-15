defmodule TeacherAssistantWeb.Teacher.RosterLive do
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.TeachingNav
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum

  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_avatar: 1]

  def mount(%{"id" => ctx_id}, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace

    with true <- not is_nil(ws),
         {:ok, ctx} <- Curriculum.fetch_assigned_teaching_context(scope, ctx_id),
         {:ok, class_group} <- Enrollment.fetch_owned_class_group(scope, ctx.class_group_id) do
      {:ok, load(socket, scope, ws, ctx, class_group)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  defp load(socket, scope, ws, ctx, class_group) do
    students = Enrollment.list_students(scope, class_group)

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
        <.teaching_nav context_id={@ctx.id} current={:roster} />
        <.page_header
          eyebrow={gettext("Roster")}
          title={"#{@ctx.subject} · #{@class_group.label}"}
        />

        <div id="roster-count" class="flex items-center gap-3 text-sm text-base-content/70">
          <span class="font-semibold text-base-content">
            {length(@students)} {gettext("students")}
          </span>
          <span class="ta-num">{Map.get(sex_counts(@students), :f, 0)} {gettext("Filles")}</span>
          <span class="text-base-content/70">·</span>
          <span class="ta-num">{Map.get(sex_counts(@students), :m, 0)} {gettext("Garçons")}</span>
        </div>

        <div :if={@students != []} id="student-table" class="ta-section">
          <.list_row
            :for={s <- @students}
            id={"student-row-#{s.id}"}
            title={s.full_name}
            meta={
              [if(s.sex == :f, do: gettext("Fille"), else: gettext("Garçon")), s.matricule]
              |> Enum.reject(&is_nil/1)
              |> Enum.join(" · ")
            }
          >
            <:leading>
              <.student_avatar student={s} class="size-9 text-xs" />
            </:leading>
          </.list_row>
        </div>

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
