defmodule TeacherAssistantWeb.Onboarding.SetupWizardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment

  @steps [:identity, :year, :classes, :invite]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       step: initial_step(scope),
       ws: scope.current_workspace,
       year: scope.current_academic_year
     )}
  end

  defp initial_step(scope) do
    cond do
      scope.current_academic_year == nil -> :year
      Enrollment.list_class_groups(scope.current_workspace, scope.current_academic_year) == [] -> :classes
      true -> :invite
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="setup-wizard" class="mx-auto max-w-3xl space-y-6">
        <.page_header
          eyebrow={gettext("Get started")}
          title={gettext("Set up your school")}
        />

        <.wizard_progress step={@step} />

        <div class="ta-board space-y-5 p-5 sm:p-6">
          <%= case @step do %>
            <% :year -> %>
              <.year_panel {assigns} />
            <% :classes -> %>
              <.classes_panel {assigns} />
            <% :invite -> %>
              <.invite_panel {assigns} />
            <% _ -> %>
              <.identity_panel {assigns} />
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :step, :atom, required: true

  defp wizard_progress(assigns) do
    steps = [
      {:identity, gettext("Identity")},
      {:year, gettext("Academic year")},
      {:classes, gettext("Classes")},
      {:invite, gettext("Invite team")}
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <ol id="wizard-progress" class="grid grid-cols-2 gap-2 sm:grid-cols-4">
      <li
        :for={{{key, label}, idx} <- Enum.with_index(@steps)}
        id={"wizard-step-#{key}"}
        data-state={step_state(@step, key)}
        class={[
          "ta-leaf flex items-center gap-2 px-3 py-2",
          step_state(@step, key) == :current && "ring-2 ring-primary"
        ]}
      >
        <span class={[
          "ta-num flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
          step_badge_class(step_state(@step, key))
        ]}>
          <.icon :if={step_state(@step, key) == :done} name="hero-check" class="size-3.5" />
          <span :if={step_state(@step, key) != :done}>{idx + 1}</span>
        </span>
        <span class="ta-eyebrow">{label}</span>
      </li>
    </ol>
    """
  end

  defp step_state(current, key) do
    current_idx = Enum.find_index(@steps, &(&1 == current))
    key_idx = Enum.find_index(@steps, &(&1 == key))

    cond do
      key_idx < current_idx -> :done
      key_idx == current_idx -> :current
      true -> :upcoming
    end
  end

  defp step_badge_class(:done), do: "bg-primary text-primary-content"
  defp step_badge_class(:current), do: "border-2 border-primary text-primary"
  defp step_badge_class(:upcoming), do: "bg-base-300 text-base-content/50"

  # Panels are placeholders for now — filled in by later tasks in this
  # feature (year/classes/invite panels get real forms; identity gets a
  # proper recap). This task only wires the shell + step derivation.

  defp identity_panel(assigns) do
    ~H"""
    <div id="wizard-panel-identity" class="space-y-2">
      <p class="ta-eyebrow">{gettext("Your school")}</p>
      <h2 class="text-lg font-semibold">{@ws && @ws.name}</h2>
      <p class="text-sm text-base-content/70">
        {gettext("Setup is complete — here's a quick recap.")}
      </p>
    </div>
    """
  end

  defp year_panel(assigns) do
    ~H"""
    <div id="wizard-panel-year" class="space-y-2">
      <p class="ta-eyebrow">{gettext("Academic year")}</p>
      <h2 class="text-lg font-semibold">{gettext("Set up your academic year")}</h2>
      <p class="text-sm text-base-content/70">
        {gettext("Create the academic year to unlock classes and enrollment.")}
      </p>
    </div>
    """
  end

  defp classes_panel(assigns) do
    ~H"""
    <div id="wizard-panel-classes" class="space-y-2">
      <p class="ta-eyebrow">{gettext("Classes")}</p>
      <h2 class="text-lg font-semibold">{gettext("Create your first class")}</h2>
      <p class="text-sm text-base-content/70">
        {gettext("Add at least one class to continue.")}
      </p>
    </div>
    """
  end

  defp invite_panel(assigns) do
    ~H"""
    <div id="wizard-panel-invite" class="space-y-2">
      <p class="ta-eyebrow">{gettext("Invite team")}</p>
      <h2 class="text-lg font-semibold">{gettext("Invite your team")}</h2>
      <p class="text-sm text-base-content/70">
        {gettext("Invite teachers and staff to join your school.")}
      </p>
    </div>
    """
  end
end
