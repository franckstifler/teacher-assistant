defmodule TeacherAssistantWeb.Onboarding.SetupWizardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.{AcademicYear, Seeding}
  alias TeacherAssistant.Accounts.Permissions

  @steps [:identity, :year, :classes, :invite]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace
    year = scope.current_academic_year

    {:ok,
     assign(socket,
       step: initial_step(ws, year),
       ws: ws,
       year: year,
       year_form: year_form(ws.id, year == nil)
     )}
  end

  defp initial_step(ws, year) do
    cond do
      year == nil -> :year
      Enrollment.list_class_groups(ws, year) == [] -> :classes
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

  def handle_event("validate_year", %{"year" => params}, socket) do
    {:noreply,
     assign(socket, :year_form, AshPhoenix.Form.validate(socket.assigns.year_form, params))}
  end

  def handle_event("create_year", %{"year" => params}, socket) do
    scope = socket.assigns.current_scope
    ws = socket.assigns.ws

    if Permissions.admin?(scope) do
      case AshPhoenix.Form.submit(socket.assigns.year_form, params: params) do
        {:ok, year} ->
          Seeding.seed_starter_classes(ws, year)

          # Deliberately land on the `:classes` step rather than re-deriving
          # via `initial_step/2` — seeding just populated classes, so the
          # derived step would jump straight past it to `:invite`. We want
          # the head to see (and can edit) the seeded starter classes before
          # continuing.
          {:noreply,
           socket
           |> assign(:year, year)
           |> assign(:step, :classes)
           |> put_flash(:info, gettext("Année scolaire créée."))}

        {:error, form} ->
          {:noreply,
           socket
           |> assign(:year_form, form)
           |> put_flash(:error, gettext("Impossible de créer l'année scolaire."))}
      end
    else
      {:noreply, socket}
    end
  end

  # `workspace_id` and `active` are server-controlled (never user input), so
  # they're set on the changeset at build time via `prepare_source` — same
  # pattern as `School.SettingsLive.year_form/2`. Only the first year of a
  # workspace is created active.
  defp year_form(workspace_id, active?) do
    AcademicYear
    |> AshPhoenix.Form.for_create(:create_for_workspace,
      as: "year",
      prepare_source: fn changeset ->
        changeset
        |> Ash.Changeset.change_attribute(:workspace_id, workspace_id)
        |> Ash.Changeset.change_attribute(:active, active?)
      end
    )
    |> to_form()
  end

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
    <div id="wizard-panel-year" class="space-y-4">
      <div class="space-y-2">
        <p class="ta-eyebrow">{gettext("Academic year")}</p>
        <h2 class="text-lg font-semibold">{gettext("Set up your academic year")}</h2>
        <p class="text-sm text-base-content/70">
          {gettext("Create the academic year to unlock classes and enrollment.")}
        </p>
      </div>

      <.form
        for={@year_form}
        id="year-form"
        phx-change="validate_year"
        phx-submit="create_year"
        class="space-y-3"
      >
        <div class="grid gap-3 sm:grid-cols-3">
          <.input field={@year_form[:name]} label={gettext("Name")} />
          <.input field={@year_form[:start_date]} type="date" label={gettext("Start date")} />
          <.input field={@year_form[:end_date]} type="date" label={gettext("End date")} />
        </div>
        <button type="submit" class="btn btn-primary btn-sm">
          {gettext("Create the academic year")}
        </button>
      </.form>
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
