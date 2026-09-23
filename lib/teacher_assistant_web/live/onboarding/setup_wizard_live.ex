defmodule TeacherAssistantWeb.Onboarding.SetupWizardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.{AcademicYear, Seeding, SchoolTemplates}
  alias TeacherAssistant.Accounts

  alias TeacherAssistant.Accounts.{
    CameroonRegion,
    MembershipStatus,
    Permissions,
    SchoolInvitation,
    SchoolRole,
    SchoolSubsystem,
    SchoolType
  }

  @steps [:identity, :year, :classes, :invite]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace
    year = scope.current_academic_year

    {:ok,
     socket
     |> assign(
       step: initial_step(ws, year),
       ws: ws,
       year: year,
       year_form: year_form(ws.id, year == nil),
       class_streams: class_streams_for(ws),
       class_form: class_form(),
       invite_form: invite_form(),
       profile: fetch_profile(ws),
       staff_count: ws |> Accounts.list_members() |> length()
     )
     |> assign_classes(year)
     |> assign_invitations()}
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
      <section id="setup-wizard" class="mx-auto max-w-5xl space-y-6">
        <.page_header
          eyebrow={gettext("Get started")}
          title={gettext("Set up your school")}
        />

        <.wizard_progress step={@step} />

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_18rem] lg:items-start">
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

          <.recap_aside
            profile={@profile}
            year={@year}
            classes={@classes}
            invitations={@invitations}
            staff_count={@staff_count}
            verification_status={@current_scope.school_verification_status}
            tip={tip_for_step(@step)}
          />
        </div>
      </section>
    </Layouts.app>
    """
  end

  # Persistent right-column aside (mockup: Récapitulatif + "Bon à savoir" tip
  # card) — the checklist rows mirror the SAME four signals
  # `DashboardLive`'s `#setup-checklist` derives (profile / year / classes /
  # staff), plus a fifth row for verification, which the dashboard shows as a
  # separate callout rather than a checklist row. No data is invented: every
  # row reads a real assign already computed in `mount/3` or the domain
  # calls it wraps.
  attr :profile, :any, required: true
  attr :year, :any, required: true
  attr :classes, :list, required: true
  attr :invitations, :list, required: true
  attr :staff_count, :integer, required: true
  attr :verification_status, :atom, default: nil
  attr :tip, :string, required: true

  defp recap_aside(assigns) do
    rows = [
      {:identity, gettext("Identité"), assigns.profile != nil,
       if(assigns.profile,
         do: assigns.profile.short_name || gettext("à compléter"),
         else: gettext("à remplir")
       )},
      {:year, gettext("Année scolaire"), assigns.year != nil,
       if(assigns.year, do: assigns.year.name, else: "—")},
      {:classes, gettext("Classes"), assigns.classes != [],
       if(assigns.classes != [],
         do:
           ngettext("%{count} classe", "%{count} classes", length(assigns.classes),
             count: length(assigns.classes)
           ),
         else: "—"
       )},
      {:team, gettext("Équipe"), assigns.invitations != [] or assigns.staff_count > 1,
       ngettext("%{count} invitation", "%{count} invitations", length(assigns.invitations),
         count: length(assigns.invitations)
       )},
      {:verification, gettext("Vérification"), assigns.verification_status == :verified,
       if(assigns.verification_status == :verified,
         do: gettext("vérifié"),
         else: gettext("après envoi")
       )}
    ]

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <aside id="wizard-recap" class="space-y-4">
      <div class="ta-leaf space-y-2">
        <h2 class="ta-eyebrow">{gettext("Récapitulatif")}</h2>
        <ul class="divide-y divide-base-300/70 text-sm">
          <li
            :for={{key, label, done?, value} <- @rows}
            id={"recap-#{key}"}
            data-state={if done?, do: "done", else: "todo"}
            class="flex items-center justify-between gap-2 py-1.5 first:pt-0 last:pb-0"
          >
            <span class="flex items-center gap-2">
              <.icon
                name={if done?, do: "hero-check-circle", else: "hero-minus-circle"}
                class={"size-4 shrink-0 " <> if(done?, do: "text-primary", else: "text-base-content/40")}
              />
              {label}
            </span>
            <span class="ta-num shrink-0 text-xs text-base-content/60">{value}</span>
          </li>
        </ul>
      </div>

      <div class="space-y-1 rounded-lg border border-dashed border-[color:var(--ta-rail-line)] p-4">
        <h3 class="ta-eyebrow">{gettext("Bon à savoir")}</h3>
        <p class="text-sm text-base-content/70">{@tip}</p>
      </div>
    </aside>
    """
  end

  defp tip_for_step(:year),
    do:
      gettext(
        "Les dates des séquences déterminent les fenêtres de saisie des notes et le calcul des bulletins. Elles restent modifiables toute l'année."
      )

  defp tip_for_step(:classes),
    do:
      gettext(
        "Vous pourrez dédoubler une classe (2de A, 2de B…), changer les coefficients et importer vos listes d'élèves depuis les paramètres."
      )

  defp tip_for_step(:invite),
    do:
      gettext(
        "Les enseignants n'ont accès qu'à leurs classes. Les censeurs voient la discipline et la saisie ; l'intendant voit les frais."
      )

  defp tip_for_step(_identity),
    do:
      gettext(
        "Le nom doit être celui de l'arrêté d'ouverture. Vous pourrez ajouter le logo et le cachet plus tard, dans les paramètres."
      )

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
           |> assign_classes(year)
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

  def handle_event("add_class", %{"class_group" => params}, socket) do
    scope = socket.assigns.current_scope
    %{ws: ws, year: year} = socket.assigns

    if Permissions.admin?(scope) do
      attrs = class_attrs(params)

      case Enrollment.create_class_group(ws, year, attrs) do
        {:ok, _class_group} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Class created."))
           |> assign(:class_form, class_form())
           |> assign_classes(year)}

        {:error, _error} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create the class."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_class", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    %{classes: classes, year: year} = socket.assigns

    if Permissions.admin?(scope) do
      case Enum.find(classes, &(&1.id == id)) do
        nil ->
          {:noreply, socket}

        class_group ->
          case Enrollment.delete_class_group(class_group) do
            :ok ->
              {:noreply,
               socket
               |> put_flash(:info, gettext("Class deleted."))
               |> assign_classes(year)}

            {:error, :has_data} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 gettext("This class has students or teachers — remove them first.")
               )}
          end
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("continue_classes", _params, socket) do
    if socket.assigns.classes == [] do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :step, :invite)}
    end
  end

  def handle_event("invite", %{"invite" => params}, socket) do
    scope = socket.assigns.current_scope

    if Permissions.head?(scope) do
      roles = parse_invite_roles(params["roles"])

      case Accounts.invite_member(scope.current_workspace, scope.current_user, %{
             email: params["email"],
             roles: roles,
             membership_status: parse_membership_status(params["membership_status"])
           }) do
        {:ok, _invitation} ->
          {:noreply,
           socket
           |> assign(:invite_form, invite_form())
           |> assign_invitations()
           |> put_flash(:info, gettext("Invitation envoyée."))}

        {:error, :already_member} ->
          {:noreply,
           put_flash(socket, :error, gettext("Cette personne est déjà membre de l'école."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("finish", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/school")}
  end

  defp assign_classes(socket, nil), do: assign(socket, :classes, [])

  defp assign_classes(socket, year) do
    assign(socket, :classes, Enrollment.list_class_groups(socket.assigns.ws, year))
  end

  defp assign_invitations(socket) do
    assign(socket, :invitations, Accounts.list_pending_invitations(socket.assigns.ws))
  end

  defp fetch_profile(ws) do
    case Accounts.fetch_school_profile(ws) do
      {:ok, profile} -> profile
      _ -> nil
    end
  end

  # Mirrors `MembersLive.parse_roles/1` — an invite always needs at least one
  # role, defaulting to `:teacher` when none are checked.
  defp parse_invite_roles(nil), do: [:teacher]
  defp parse_invite_roles([]), do: [:teacher]

  defp parse_invite_roles(roles) when is_list(roles) do
    roles
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&String.to_existing_atom/1)
    |> case do
      [] -> [:teacher]
      parsed -> parsed
    end
  end

  defp parse_membership_status(nil), do: nil
  defp parse_membership_status(""), do: nil
  defp parse_membership_status(status) when is_binary(status), do: String.to_existing_atom(status)

  defp class_streams_for(ws) do
    case TeacherAssistant.Accounts.fetch_school_profile(ws) do
      {:ok, profile} -> SchoolTemplates.streams_for(profile.school_type, profile.subsystem)
      _ -> %{kind: :serie, values: [], levels: []}
    end
  end

  # A plain (non-`AshPhoenix.Form`) form: `add_class` calls
  # `Enrollment.create_class_group/3` directly, which already sets
  # `workspace_id`/`academic_year_id`/`subsystem` — there's no changeset to
  # attach `prepare_source` to here (unlike `ClassesLive.class_form/2`).
  defp class_form, do: to_form(%{"label" => "", "level" => "", "serie" => ""}, as: "class_group")

  # `ClassGroup.serie` is a nullable string; an empty selection stays `nil`
  # rather than being stored as "" (mirrors `ClassesLive.drop_blank_serie/1`).
  defp class_attrs(params) do
    %{
      label: Map.get(params, "label", ""),
      level: Map.get(params, "level", ""),
      serie: presence(Map.get(params, "serie"))
    }
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  # The invite dialog binds to `SchoolInvitation :create` for its email
  # field. Submit still routes through `Accounts.invite_member/3`, which owns
  # the token/expiry generation, the "already a member" guard and the
  # invitation email — mirrors `MembersLive.invite_form/0`.
  defp invite_form do
    SchoolInvitation
    |> AshPhoenix.Form.for_create(:create, as: "invite")
    |> to_form()
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

  # `identity_panel/1` is only reached if a head navigates back to `:identity`
  # after setup is already complete (the derived initial step never lands
  # there) — so it's a read-only recap, not a form. It deliberately does not
  # link to `/school/settings`: that page is gated behind setup completion
  # and would just bounce back here mid-wizard.
  defp identity_panel(assigns) do
    ~H"""
    <div id="wizard-panel-identity" class="space-y-4">
      <div class="space-y-2">
        <p class="ta-eyebrow">{gettext("Your school")}</p>
        <h2 class="text-lg font-semibold">{@ws && @ws.name}</h2>
        <p class="text-sm text-base-content/70">
          {gettext("Setup is complete — here's a quick recap.")}
        </p>
      </div>

      <dl :if={@profile} class="ta-leaf grid gap-4 px-4 py-4 sm:grid-cols-2">
        <div>
          <dt class="ta-eyebrow">{gettext("Name")}</dt>
          <dd class="text-sm font-medium">{@profile.short_name || @ws.name}</dd>
        </div>
        <div>
          <dt class="ta-eyebrow">{gettext("Type")}</dt>
          <dd class="text-sm font-medium">{SchoolType.label(@profile.school_type)}</dd>
        </div>
        <div>
          <dt class="ta-eyebrow">{gettext("Subsystem")}</dt>
          <dd class="text-sm font-medium">{SchoolSubsystem.label(@profile.subsystem)}</dd>
        </div>
        <div>
          <dt class="ta-eyebrow">{gettext("Region")}</dt>
          <dd class="text-sm font-medium">{CameroonRegion.label(@profile.region)}</dd>
        </div>
      </dl>
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
    <div id="wizard-panel-classes" class="space-y-4">
      <div class="space-y-2">
        <p class="ta-eyebrow">{gettext("Classes")}</p>
        <h2 class="text-lg font-semibold">{gettext("Review your classes")}</h2>
        <p class="text-sm text-base-content/70">
          {gettext(
            "We've suggested starter classes below — edit them, then add at least one to continue."
          )}
        </p>
      </div>

      <ul :if={@classes != []} id="wizard-classes-list" class="space-y-2">
        <li
          :for={cg <- @classes}
          id={"wizard-class-#{cg.id}"}
          class="ta-leaf flex items-center justify-between gap-2 px-3 py-2"
        >
          <span class="text-sm">
            <span class="font-medium">{cg.label}</span>
            <span class="text-base-content/60">· {cg.level}</span>
            <span :if={cg.serie} class="text-base-content/60">· {cg.serie}</span>
          </span>
          <button
            id={"wizard-class-delete-#{cg.id}"}
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="delete_class"
            phx-value-id={cg.id}
            data-confirm={gettext("Delete this class?")}
          >
            {gettext("Delete")}
          </button>
        </li>
      </ul>

      <.empty_state
        :if={@classes == []}
        icon="hero-rectangle-group"
        title={gettext("No classes yet")}
      />

      <div class="ta-leaf space-y-3">
        <h3 class="text-sm font-semibold">{gettext("Add a class")}</h3>
        <.form for={@class_form} id="class-form" phx-submit="add_class" class="space-y-2">
          <div class="grid gap-2 sm:grid-cols-3">
            <.input field={@class_form[:label]} label={gettext("Label")} />
            <.input field={@class_form[:level]} label={gettext("Level")} />
            <.input
              field={@class_form[:serie]}
              label={SchoolTemplates.stream_label(@class_streams.kind)}
              list="wizard-serie-options"
            />
            <datalist id="wizard-serie-options">
              <option :for={s <- @class_streams.values} value={s}>{s}</option>
            </datalist>
          </div>
          <button type="submit" class="btn btn-secondary btn-sm">{gettext("Add class")}</button>
        </.form>
      </div>

      <button
        type="button"
        class="btn btn-primary btn-sm"
        phx-click="continue_classes"
        disabled={@classes == []}
      >
        {gettext("Continuer")}
      </button>
    </div>
    """
  end

  defp invite_panel(assigns) do
    ~H"""
    <div id="wizard-panel-invite" class="space-y-5">
      <div class="space-y-2">
        <p class="ta-eyebrow">{gettext("Invite team")}</p>
        <h2 class="text-lg font-semibold">{gettext("Invite your team")}</h2>
        <p class="text-sm text-base-content/70">
          {gettext("Invite teachers and staff to join your school.")}
        </p>
      </div>

      <div class="ta-leaf space-y-3">
        <.form for={@invite_form} id="invite-form" phx-submit="invite">
          <div class="flex flex-wrap items-end gap-3">
            <.input field={@invite_form[:email]} type="email" label={gettext("Email")} />
            <div class="flex flex-wrap gap-2">
              <label :for={role <- SchoolRole.values()} class="label cursor-pointer gap-1">
                <input
                  type="checkbox"
                  name="invite[roles][]"
                  value={role}
                  checked={role == :teacher}
                  class="checkbox checkbox-sm"
                />
                <span class="text-xs">{SchoolRole.label(role)}</span>
              </label>
            </div>
            <.input
              field={@invite_form[:membership_status]}
              type="select"
              label={gettext("Statut d'emploi")}
              prompt={gettext("Non précisé")}
              options={Enum.map(MembershipStatus.values(), &{MembershipStatus.label(&1), &1})}
            />
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Inviter")}</button>
          </div>
        </.form>
      </div>

      <div id="wizard-invitations-list" class="space-y-2">
        <h3 class="text-sm font-semibold">{gettext("Invitations en attente")}</h3>
        <.empty_state
          :if={@invitations == []}
          icon="hero-envelope"
          title={gettext("Aucune invitation en attente")}
        />
        <div
          :for={inv <- @invitations}
          id={"wizard-invitation-#{inv.id}"}
          class="ta-leaf flex items-center justify-between gap-3 px-3 py-2"
        >
          <div class="text-sm">
            <span class="font-medium">{inv.email}</span>
            <span class="text-base-content/60">
              — {inv.roles |> Enum.map(&SchoolRole.label/1) |> Enum.join(", ")}
            </span>
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <button id="finish-setup" type="button" class="btn btn-primary btn-sm" phx-click="finish">
          {gettext("Terminer la configuration")}
        </button>
        <button type="button" class="btn btn-ghost btn-sm" phx-click="finish">
          {gettext("Passer pour l'instant")}
        </button>
      </div>
    </div>
    """
  end
end
