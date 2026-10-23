defmodule TeacherAssistantWeb.School.MembersLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.{MembershipStatus, SchoolInvitation, SchoolRole, User}
  alias TeacherAssistant.Accounts
  alias TeacherAssistantWeb.Dates

  import TeacherAssistantWeb.Drawer

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    # Reads are policy-checked; a non-member has no workspace in scope.
    if scope.current_workspace do
      {:ok,
       socket
       |> assign(:scope, scope)
       |> assign(:page_title, gettext("Membres"))
       |> assign(:can_manage_staff?, Accounts.can_manage_staff?(scope))
       |> assign(:can_set_service?, Accounts.can_set_member_service?(scope))
       |> assign(:query, "")
       |> assign(:role_filter, nil)
       |> assign(:invite_form, invite_form())
       |> assign(:account_form, account_form())
       # nil | :add (the « Ajouter un membre » drawer) | :member (`@editing`)
       |> assign(:panel, nil)
       |> assign(:add_method, :phone)
       |> assign(:add_error, nil)
       |> assign(:editing, nil)
       |> assign(:member_form, nil)
       |> assign(:member_error, nil)
       |> assign(:reset_candidate, nil)
       |> assign(:temporary_password, nil)
       |> reload_members()}
    else
      {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-members" class="mx-auto max-w-4xl space-y-5">
        <.page_header
          eyebrow={gettext("École")}
          title={gettext("Membres")}
          subtitle={summary_line(@members, @invitations, @account_states, @can_manage_staff?)}
        >
          <:actions :if={@can_manage_staff?}>
            <button
              id="open-add-member"
              type="button"
              class="btn btn-primary transition-transform active:scale-[0.97]"
              phx-click="open_add"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Ajouter un membre")}
            </button>
          </:actions>
        </.page_header>

        <form
          id="members-filter"
          phx-change="filter"
          phx-submit="filter"
          class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_14rem]"
          role="search"
        >
          <.input
            type="search"
            id="members-query"
            name="q"
            value={@query}
            placeholder={gettext("Rechercher un nom, un e-mail, un téléphone…")}
            aria-label={gettext("Rechercher un membre")}
            autocomplete="off"
            phx-debounce="200"
          />
          <.input
            type="select"
            id="members-role-filter"
            name="role"
            value={@role_filter && to_string(@role_filter)}
            aria-label={gettext("Filtrer par rôle")}
            prompt={gettext("Tous les rôles")}
            options={role_options()}
          />
        </form>

        <div
          :if={@visible_members != []}
          id="members-list"
          class="ta-section"
          aria-label={gettext("Membres")}
        >
          <.member_row
            :for={m <- @visible_members}
            member={m}
            state={@account_states[m.id]}
            editable?={@can_manage_staff? or @can_set_service?}
            selected={@editing && @editing.id == m.id}
          />
        </div>

        <.empty_state
          :if={@members == []}
          icon="hero-user-group"
          title={gettext("Aucun membre actif pour le moment")}
        />

        <.empty_state
          :if={@members != [] and @visible_members == []}
          icon="hero-magnifying-glass"
          title={gettext("Aucun membre ne correspond à la recherche")}
        >
          <:action>
            <button type="button" class="btn btn-ghost btn-sm" phx-click="clear_filter">
              {gettext("Effacer les filtres")}
            </button>
          </:action>
        </.empty_state>

        <.settings_section
          :if={@can_manage_staff? and @visible_invitations != []}
          id="invitations-list"
          title={gettext("Invitations en attente")}
          subtitle={gettext("La personne n'a pas encore ouvert le lien reçu par e-mail.")}
        >
          <.list_row
            :for={inv <- @visible_invitations}
            id={"invitation-#{inv.id}"}
            title={to_string(inv.email)}
            meta={invitation_meta(inv)}
          >
            <:leading>
              <span class="grid size-10 place-items-center rounded-full bg-base-200 text-base-content/70">
                <.icon name="hero-envelope" class="size-5" />
              </span>
            </:leading>
            <:trailing>
              <button
                id={"invite-revoke-#{inv.id}"}
                type="button"
                class="btn btn-ghost min-h-11 text-error"
                phx-click="revoke_invite"
                phx-value-id={inv.id}
                data-confirm={gettext("Révoquer cette invitation ?")}
              >
                {gettext("Révoquer")}<span class="sr-only">{to_string(inv.email)}</span>
              </button>
            </:trailing>
          </.list_row>
        </.settings_section>

        <.add_member_drawer
          :if={@can_manage_staff? and @panel == :add}
          method={@add_method}
          error={@add_error}
          account_form={@account_form}
          invite_form={@invite_form}
        />

        <.member_drawer
          :if={@panel == :member and @editing}
          member={@editing}
          form={@member_form}
          error={@member_error}
          state={@account_states[@editing.id]}
          resettable?={MapSet.member?(@resettable_member_ids, @editing.id)}
          can_manage_staff?={@can_manage_staff?}
          can_set_service?={@can_set_service?}
        />

        <.confirm_reset_dialog :if={@reset_candidate} candidate={@reset_candidate} />

        <.temporary_password_dialog :if={@temporary_password} info={@temporary_password} />
      </section>
    </Layouts.app>
    """
  end

  # --- Components ----------------------------------------------------------------

  attr :member, :map, required: true
  attr :state, :map, default: nil, doc: "the account state; staff managers only"
  attr :editable?, :boolean, required: true
  attr :selected, :boolean, default: false

  defp member_row(assigns) do
    ~H"""
    <.list_row
      id={"member-row-#{@member.id}"}
      title={User.display_name(@member.user)}
      selected={@selected}
      phx-click={@editable? && "edit_member"}
      phx-value-id={@member.id}
    >
      <:leading>
        <.initials_avatar name={User.display_name(@member.user)} class="size-10 text-sm" />
      </:leading>
      <span
        :if={@member.user.name && User.contact(@member.user)}
        class="mt-0.5 flex min-w-0 items-center gap-1.5 text-sm text-base-content/70"
      >
        <span class="ta-num shrink-0 rounded border border-base-300 px-1 text-[0.6rem] font-semibold leading-4 tracking-wide">
          {if @member.user.email, do: "@", else: gettext("TÉL")}
        </span>
        <span class={["truncate", !@member.user.email && "ta-num"]}>
          {User.contact(@member.user)}
        </span>
      </span>
      <span class="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-base-content/70">
        <span
          :for={role <- @member.roles}
          class="rounded-full border border-base-300 px-2 py-0.5 font-medium text-base-content/80"
          title={SchoolRole.label(role)}
        >
          {role_short(role)}
        </span>
        <span :if={@member.status}>{MembershipStatus.label(@member.status)}</span>
        <span :if={@member.statutory_hours}>
          <span class="ta-num">{@member.statutory_hours}</span> {gettext("h/sem.")}
        </span>
        <.account_state :if={@state} state={@state} class="inline-flex sm:hidden" />
      </span>
      <:trailing :if={@state}>
        <.account_state state={@state} class="hidden sm:inline-flex" />
      </:trailing>
    </.list_row>
    """
  end

  attr :state, :map, required: true
  attr :class, :any, default: "inline-flex", doc: "must set the display (inline-flex)"

  defp account_state(assigns) do
    ~H"""
    <span class={[
      "items-center gap-1.5 whitespace-nowrap text-xs font-medium text-base-content/80",
      @class
    ]}>
      <span class={["size-2 shrink-0 rounded-full", state_dot(@state.kind)]} aria-hidden="true"></span>
      {@state.label}
    </span>
    """
  end

  defp state_dot(:active), do: "bg-success"
  defp state_dot(:pending), do: "bg-warning"
  defp state_dot(:expired), do: "bg-error"
  defp state_dot(:linked), do: "bg-base-content/40"

  attr :method, :atom, required: true
  attr :error, :string, default: nil
  attr :account_form, Phoenix.HTML.Form, required: true
  attr :invite_form, Phoenix.HTML.Form, required: true

  defp add_member_drawer(assigns) do
    ~H"""
    <.drawer
      id="add-member-drawer"
      eyebrow={gettext("Équipe")}
      title={gettext("Ajouter un membre")}
      on_close={JS.push("close_drawer")}
    >
      <div :if={@error} id="add-member-error" role="alert" class="alert alert-error alert-soft">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <div class="grid grid-cols-2 gap-2" role="radiogroup" aria-label={gettext("Méthode")}>
        <.method_card
          id="method-phone"
          method="phone"
          checked={@method == :phone}
          icon="hero-device-phone-mobile"
          title={gettext("Par téléphone")}
          hint={
            gettext(
              "Pour qui n'a pas d'e-mail. Vous recevez un mot de passe temporaire à transmettre."
            )
          }
        />
        <.method_card
          id="method-email"
          method="email"
          checked={@method == :email}
          icon="hero-envelope"
          title={gettext("Par invitation e-mail")}
          hint={gettext("La personne reçoit un lien et crée son mot de passe elle-même.")}
        />
      </div>

      <.form
        :if={@method == :phone}
        for={@account_form}
        id="create-account-form"
        phx-submit="create_account"
        class="space-y-4"
      >
        <.input
          field={@account_form[:name]}
          label={gettext("Nom et prénoms")}
          autocomplete="off"
          required
        />
        <div>
          <label for={@account_form[:phone].id} class="label mb-1 text-sm">
            {gettext("Numéro de téléphone")}
          </label>
          <div class="relative">
            <span
              class="ta-num pointer-events-none absolute left-0 top-0 z-10 flex h-10 items-center rounded-l-[inherit] border-r border-base-300 bg-base-200 px-3 text-sm text-base-content/70"
              aria-hidden="true"
            >
              +237
            </span>
            <.input
              field={@account_form[:phone]}
              type="tel"
              inputmode="tel"
              autocomplete="off"
              placeholder="6XX XX XX XX"
              class="input ta-num w-full pl-[4.5rem]"
              error_class="input-error"
              required
            />
          </div>
          <p class="text-xs text-base-content/70">
            {gettext(
              "9 chiffres, commençant par 6 (mobile) ou 2 (fixe). Écrivez-le comme vous voulez."
            )}
          </p>
        </div>
        <.role_chips name="account[roles][]" checked={checked_roles(@account_form)} />
        <.input
          field={@account_form[:membership_status]}
          type="select"
          label={gettext("Statut d'emploi")}
          prompt={gettext("Non précisé")}
          options={membership_status_options()}
        />
        <div class="rounded-box border border-base-300 bg-base-200/60 p-3 text-sm">
          <p class="font-semibold">{gettext("Ce qui va se passer")}</p>
          <ul class="mt-1.5 space-y-1 text-base-content/75">
            <li>
              {gettext(
                "• Nouveau numéro : un compte est créé avec un mot de passe temporaire (7 jours), affiché une seule fois."
              )}
            </li>
            <li>
              {gettext(
                "• Numéro qui a déjà un compte (autre établissement) : la personne est simplement ajoutée, son mot de passe ne change pas."
              )}
            </li>
          </ul>
        </div>
      </.form>

      <.form
        :if={@method == :email}
        for={@invite_form}
        id="invite-form"
        phx-submit="invite"
        class="space-y-4"
      >
        <.input
          field={@invite_form[:email]}
          type="email"
          label={gettext("Email")}
          autocomplete="off"
        />
        <.role_chips name="invite[roles][]" checked={[:teacher]} />
        <.input
          field={@invite_form[:membership_status]}
          type="select"
          label={gettext("Statut d'emploi")}
          prompt={gettext("Non précisé")}
          options={membership_status_options()}
        />
      </.form>

      <:footer>
        <button type="button" class="btn btn-ghost" phx-click="close_drawer">
          {gettext("Annuler")}
        </button>
        <button
          :if={@method == :phone}
          type="submit"
          form="create-account-form"
          class="btn btn-primary"
          phx-disable-with={gettext("Création…")}
        >
          {gettext("Créer le compte")}
        </button>
        <button
          :if={@method == :email}
          type="submit"
          form="invite-form"
          class="btn btn-primary"
          phx-disable-with={gettext("Envoi…")}
        >
          {gettext("Inviter")}
        </button>
      </:footer>
    </.drawer>
    """
  end

  attr :member, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :error, :string, default: nil
  attr :state, :map, default: nil
  attr :resettable?, :boolean, required: true
  attr :can_manage_staff?, :boolean, required: true
  attr :can_set_service?, :boolean, required: true

  defp member_drawer(assigns) do
    ~H"""
    <.drawer
      id="member-drawer"
      eyebrow={gettext("Membre")}
      title={User.display_name(@member.user)}
      on_close={JS.push("close_drawer")}
    >
      <div class="flex items-center gap-3">
        <.initials_avatar name={User.display_name(@member.user)} class="size-12 text-base" />
        <div class="min-w-0 text-sm">
          <p :if={User.contact(@member.user)} class={["truncate", !@member.user.email && "ta-num"]}>
            {User.contact(@member.user)}
          </p>
          <p class="text-base-content/70">
            {@member.roles |> Enum.map(&SchoolRole.label/1) |> Enum.join(", ")}
          </p>
        </div>
      </div>

      <div :if={@error} id="member-error" role="alert" class="alert alert-error alert-soft">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <.form for={@form} id="member-form" phx-submit="save_member" class="space-y-4">
        <input type="hidden" name="member_id" value={@member.id} />
        <%= if @can_manage_staff? do %>
          <%!-- an empty value keeps « roles » in the params when every chip is off --%>
          <input type="hidden" name="member[roles][]" value="" />
          <.role_chips name="member[roles][]" checked={checked_roles(@form)} />
          <.input
            field={@form[:status]}
            type="select"
            label={gettext("Statut d'emploi")}
            prompt={gettext("Non précisé")}
            options={membership_status_options()}
          />
        <% end %>
        <div :if={@can_set_service?} class="space-y-1">
          <label for="member-service" class="label text-sm">
            {gettext("Service hebdomadaire")}
          </label>
          <div class="sm:[&>label]:ml-0">
            <.unit_input
              id="member-service"
              name={@form[:service].name}
              value={@form[:service].value}
              unit={gettext("h/sem.")}
              placeholder={gettext("École")}
              inputmode="numeric"
            />
          </div>
          <p
            :for={{msg, _opts} <- Keyword.get_values(@form.errors, :service)}
            id="member-service-error"
            class="flex items-center gap-2 text-sm text-error"
          >
            <.icon name="hero-exclamation-circle" class="size-5" />{msg}
          </p>
          <p class="text-xs text-base-content/70">
            {gettext("Laissez vide pour appliquer le service par défaut de l'école.")}
          </p>
        </div>
      </.form>

      <section
        :if={@can_manage_staff? and @state}
        id="member-account"
        class="space-y-2 border-t border-base-300 pt-4"
      >
        <h3 class="text-sm font-semibold">{gettext("Compte")}</h3>
        <.account_state state={@state} />
        <p class="text-sm text-base-content/70">{@state.note}</p>
        <button
          :if={@resettable?}
          id={"reset-password-#{@member.id}"}
          type="button"
          class="btn btn-ghost min-h-11"
          phx-click="ask_reset_password"
          phx-value-id={@member.id}
        >
          <.icon name="hero-key" class="size-4" />
          {gettext("Réinitialiser le mot de passe")}
        </button>
      </section>

      <section :if={@can_manage_staff?} class="space-y-2 border-t border-base-300 pt-4">
        <p class="text-sm text-base-content/70">
          {gettext(
            "Un membre désactivé n'a plus accès à l'école. Ses notes et son historique sont conservés."
          )}
        </p>
        <button
          id={"member-deactivate-#{@member.id}"}
          type="button"
          class="btn btn-ghost min-h-11 text-error"
          phx-click="deactivate_member"
          phx-value-id={@member.id}
          data-confirm={gettext("Désactiver ce membre ?")}
        >
          <.icon name="hero-user-minus" class="size-4" />
          {gettext("Désactiver ce membre")}
        </button>
      </section>

      <:footer>
        <button type="button" class="btn btn-ghost" phx-click="close_drawer">
          {gettext("Fermer")}
        </button>
        <button
          type="submit"
          form="member-form"
          class="btn btn-primary"
          phx-disable-with={gettext("Enregistrement…")}
        >
          {gettext("Enregistrer")}
        </button>
      </:footer>
    </.drawer>
    """
  end

  attr :id, :string, required: true
  attr :method, :string, required: true
  attr :checked, :boolean, default: false
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, required: true

  defp method_card(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="radio"
      aria-checked={to_string(@checked)}
      phx-click="choose_method"
      phx-value-method={@method}
      class="group rounded-box border border-base-300 p-3 text-left transition-colors hover:border-primary/60 aria-checked:border-primary aria-checked:bg-primary/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    >
      <span class="flex items-center gap-2 text-sm font-semibold">
        <.icon
          name={@icon}
          class="size-4 text-base-content/70 group-aria-checked:text-primary"
        />
        {@title}
      </span>
      <span class="mt-1 block text-xs leading-snug text-base-content/70">{@hint}</span>
    </button>
    """
  end

  attr :name, :string, required: true
  attr :checked, :list, required: true

  defp role_chips(assigns) do
    ~H"""
    <fieldset>
      <legend class="label mb-1.5 text-sm">{gettext("Rôles")}</legend>
      <div class="flex flex-wrap gap-2">
        <label
          :for={role <- SchoolRole.values()}
          class="inline-flex min-h-11 cursor-pointer select-none items-center rounded-full border border-base-300 px-3.5 text-sm transition-colors hover:border-primary/60 has-[:checked]:border-primary has-[:checked]:bg-primary/15 has-[:checked]:text-primary has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-primary"
        >
          <input
            type="checkbox"
            name={@name}
            value={role}
            checked={role in @checked}
            class="sr-only"
          />
          {SchoolRole.label(role)}
        </label>
      </div>
    </fieldset>
    """
  end

  attr :candidate, :map, required: true

  defp confirm_reset_dialog(assigns) do
    ~H"""
    <dialog
      id="confirm-reset-dialog"
      class="modal modal-open"
      aria-labelledby="confirm-reset-title"
      phx-window-keydown="cancel_reset_password"
      phx-key="escape"
    >
      <div class="modal-box space-y-3">
        <h3 id="confirm-reset-title" class="text-lg font-semibold">
          {gettext("Nouveau mot de passe pour %{name} ?", name: @candidate.name)}
        </h3>
        <p class="text-sm text-base-content/80">
          {gettext(
            "L'ancien mot de passe cesse de fonctionner et %{name} est déconnecté·e de tous ses appareils. Vous verrez le nouveau mot de passe temporaire une seule fois.",
            name: @candidate.name
          )}
        </p>
        <div class="modal-action">
          <button
            id="cancel-reset"
            type="button"
            class="btn btn-ghost"
            phx-click="cancel_reset_password"
          >
            {gettext("Annuler")}
          </button>
          <button
            id="confirm-reset"
            type="button"
            class="btn btn-warning"
            phx-click="reset_password"
            phx-value-id={@candidate.id}
            phx-disable-with={gettext("Réinitialisation…")}
          >
            {gettext("Réinitialiser")}
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_reset_password"></div>
    </dialog>
    """
  end

  attr :info, :map, required: true

  defp temporary_password_dialog(assigns) do
    ~H"""
    <dialog
      id="temporary-password-dialog"
      class="modal modal-open"
      aria-labelledby="temporary-password-title"
    >
      <div class="modal-box max-w-lg space-y-4">
        <div>
          <p class="ta-eyebrow">
            {if @info.kind == :created,
              do: gettext("Compte créé"),
              else: gettext("Mot de passe réinitialisé")}
          </p>
          <h3 id="temporary-password-title" class="mt-1 text-lg font-semibold">
            {gettext("Mot de passe temporaire de %{name}", name: @info.name)}
          </h3>
        </div>

        <div class="space-y-3 rounded-box border border-base-300 bg-base-200/60 p-4">
          <div :if={@info.login}>
            <p class="ta-eyebrow text-base-content/70">{gettext("Identifiant")}</p>
            <p class="ta-num mt-0.5">{@info.login}</p>
          </div>
          <div>
            <p class="ta-eyebrow text-base-content/70">{gettext("Mot de passe temporaire")}</p>
            <p
              id="temporary-password"
              class="ta-num mt-1 select-all break-all text-2xl font-semibold tracking-wide"
            >
              {@info.value}
            </p>
          </div>
          <p id="temporary-password-message" hidden>{@info.message}</p>
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              class="btn btn-sm"
              phx-click={JS.dispatch("phx:copy", to: "#temporary-password")}
            >
              <.icon name="hero-clipboard-document" class="size-4" />
              {gettext("Copier le mot de passe")}
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click={JS.dispatch("phx:copy", to: "#temporary-password-message")}
            >
              <.icon name="hero-chat-bubble-left-ellipsis" class="size-4" />
              {gettext("Copier le message complet")}
            </button>
          </div>
        </div>

        <ol class="list-decimal space-y-1 pl-5 text-sm text-base-content/80">
          <li>
            {gettext(
              "Transmettez le numéro et ce mot de passe à %{name} — de vive voix, par SMS ou WhatsApp.",
              name: @info.name
            )}
          </li>
          <li>
            {gettext("Valable 7 jours, jusqu'au %{date}.", date: Dates.long(@info.expires_on))}
          </li>
          <li>
            {gettext("À la première connexion, %{name} choisira son propre mot de passe.",
              name: @info.name
            )}
          </li>
        </ol>

        <div role="note" class="alert alert-warning alert-soft text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5" />
          <span>
            {gettext("Il ne sera plus affiché. En cas d'oubli : « Réinitialiser le mot de passe ».")}
          </span>
        </div>

        <div class="modal-action">
          <button
            id="close-temporary-password"
            type="button"
            class="btn btn-primary"
            phx-click="close_temporary_password"
          >
            {gettext("C'est noté")}
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  # --- Events: list ------------------------------------------------------------------

  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:query, String.trim(params["q"] || ""))
     |> assign(:role_filter, parse_role(params["role"]))
     |> apply_filters()}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply, socket |> assign(query: "", role_filter: nil) |> apply_filters()}
  end

  def handle_event("open_add", _params, socket) do
    if socket.assigns.can_manage_staff? do
      {:noreply,
       socket
       |> close_drawer()
       |> assign(:panel, :add)
       |> assign(:add_method, :phone)
       |> assign(:account_form, account_form())
       |> assign(:invite_form, invite_form())}
    else
      {:noreply, socket}
    end
  end

  def handle_event("choose_method", %{"method" => method}, socket) do
    {:noreply,
     socket
     |> assign(:add_method, if(method == "email", do: :email, else: :phone))
     |> assign(:add_error, nil)}
  end

  def handle_event("close_drawer", _params, socket), do: {:noreply, close_drawer(socket)}

  def handle_event("edit_member", %{"id" => id}, socket) do
    %{members: members, can_manage_staff?: manage?, can_set_service?: service?} = socket.assigns

    case Enum.find(members, &(to_string(&1.id) == to_string(id))) do
      %{} = m when manage? or service? ->
        {:noreply,
         socket
         |> close_drawer()
         |> assign(panel: :member, editing: m, member_form: member_form(m))}

      _ ->
        {:noreply, socket}
    end
  end

  # --- Events: adding a member ---------------------------------------------------------

  def handle_event("invite", %{"invite" => params}, socket) do
    scope = socket.assigns.scope
    roles = parse_roles(params["roles"])

    case Accounts.invite_member(scope, %{
           email: params["email"],
           roles: roles,
           membership_status: parse_membership_status(params["membership_status"])
         }) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> assign(:invite_form, invite_form())
         |> close_drawer()
         |> reload_members()
         |> put_flash(:info, gettext("Invitation envoyée."))}

      {:error, :already_member} ->
        {:noreply, add_error(socket, gettext("Cette personne est déjà membre de l'école."))}

      {:error, :email_not_sent} ->
        {:noreply,
         add_error(
           socket,
           gettext(
             "L'e-mail d'invitation n'a pas pu être envoyé. Vérifiez l'adresse et réessayez."
           )
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, add_error(socket, gettext("Impossible d'envoyer l'invitation."))}
    end
  end

  def handle_event("create_account", %{"account" => params}, socket) do
    if blank?(params["name"]) do
      {:noreply,
       socket
       |> assign(:account_form, account_form(params, name: {gettext("Indiquez le nom."), []}))
       |> add_error(nil)}
    else
      create_account(socket, params)
    end
  end

  # --- Events: one member ----------------------------------------------------------------

  # One submit for the drawer's fields. The service is saved first (it is the
  # only field that can be rejected as invalid input), then the roles (refused
  # when they would leave the school without a head), then the status. Fields a
  # member may not change are not rendered, so they are not in the params;
  # policies still refuse a crafted request.
  def handle_event("save_member", %{"member_id" => id} = params, socket) do
    scope = socket.assigns.scope
    attrs = Map.get(params, "member", %{})

    with %{} = m <- find_membership(scope, id),
         {:ok, m} <- save_service(scope, m, attrs),
         {:ok, m} <- save_roles(scope, m, attrs),
         {:ok, _} <- save_status(scope, m, attrs) do
      {:noreply,
       socket
       |> close_drawer()
       |> reload_members()
       |> put_flash(:info, gettext("Membre mis à jour."))}
    else
      nil ->
        {:noreply, socket |> close_drawer() |> reload_members()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_hours} ->
        {:noreply,
         member_error(socket, attrs, nil,
           service: {gettext("Indiquez un nombre d'heures entre 1 et 40."), []}
         )}

      {:error, :last_head} ->
        {:noreply,
         member_error(
           socket,
           attrs,
           gettext("Impossible de retirer le rôle de chef d'établissement du dernier chef.")
         )}

      {:error, _} ->
        {:noreply,
         member_error(socket, attrs, gettext("Impossible d'enregistrer les modifications."))}
    end
  end

  def handle_event("ask_reset_password", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.members, &(to_string(&1.id) == to_string(id))) do
      nil ->
        {:noreply, socket}

      m ->
        {:noreply, assign(socket, :reset_candidate, %{id: m.id, name: User.display_name(m.user)})}
    end
  end

  def handle_event("cancel_reset_password", _params, socket) do
    {:noreply, assign(socket, :reset_candidate, nil)}
  end

  def handle_event("reset_password", %{"id" => id}, socket) do
    scope = socket.assigns.scope
    socket = assign(socket, :reset_candidate, nil)

    with %{} = membership <- find_membership(scope, id),
         {:ok, password} <- Accounts.reset_member_password(scope, membership) do
      socket = reload_members(socket)

      {:noreply,
       assign(
         socket,
         :temporary_password,
         temporary_password_info(socket, membership.user_id, password, :reset)
       )}
    else
      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Impossible de réinitialiser le mot de passe."))}
    end
  end

  def handle_event("close_temporary_password", _params, socket) do
    {:noreply, assign(socket, :temporary_password, nil)}
  end

  def handle_event("revoke_invite", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = inv <- find_invitation(scope, id),
         {:ok, _} <- Accounts.revoke_invitation(inv, scope: scope) do
      {:noreply, reload_members(socket)}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("deactivate_member", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = membership <- find_membership(scope, id),
         {:ok, _} <- Accounts.deactivate_member(scope, membership) do
      {:noreply,
       socket
       |> close_drawer()
       |> reload_members()
       |> put_flash(:info, gettext("Membre désactivé."))}
    else
      {:error, :last_head} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Impossible de désactiver le dernier chef d'établissement.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  defp save_service(scope, m, %{"service" => value}) when is_binary(value) do
    value = String.trim(value)

    if value == to_string(m.statutory_hours || ""),
      do: {:ok, m},
      else: Accounts.set_member_service(scope, m, value)
  end

  defp save_service(_scope, m, _attrs), do: {:ok, m}

  defp save_roles(scope, m, %{"roles" => roles}) when is_list(roles) do
    roles = parse_roles(roles)

    if MapSet.new(roles) == MapSet.new(m.roles),
      do: {:ok, m},
      else: Accounts.update_member_roles(scope, m, roles)
  end

  defp save_roles(_scope, m, _attrs), do: {:ok, m}

  defp save_status(scope, m, %{"status" => status}) when is_binary(status) do
    status = parse_membership_status(status)

    if status == m.status,
      do: {:ok, m},
      else: Accounts.update_member_status(scope, m, status)
  end

  defp save_status(_scope, m, _attrs), do: {:ok, m}

  defp create_account(socket, params) do
    attrs = %{
      name: String.trim(params["name"]),
      phone: params["phone"],
      roles: parse_roles(params["roles"]),
      membership_status: parse_membership_status(params["membership_status"])
    }

    case Accounts.add_member_by_phone(socket.assigns.scope, attrs) do
      {:ok, %{user: user, temporary_password: nil}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext(
             "Compte existant ajouté : %{name}. Son nom et son mot de passe n'ont pas été modifiés.",
             name: User.display_name(user)
           )
         )
         |> assign(:account_form, account_form())
         |> close_drawer()
         |> reload_members()}

      {:ok, %{user: user, temporary_password: password}} ->
        socket =
          socket
          |> assign(:account_form, account_form())
          |> close_drawer()
          |> reload_members()

        {:noreply,
         assign(
           socket,
           :temporary_password,
           temporary_password_info(socket, user.id, password, :created)
         )}

      {:error, :invalid_phone} ->
        {:noreply,
         socket
         |> assign(
           :account_form,
           account_form(params, phone: {gettext("Ce numéro de téléphone n'est pas valide."), []})
         )
         |> add_error(nil)}

      {:error, :already_member} ->
        {:noreply,
         socket
         |> assign(:account_form, account_form(params))
         |> add_error(gettext("Déjà membre de l'établissement."))}

      {:error, :forbidden} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:account_form, account_form(params))
         |> add_error(gettext("Impossible de créer le compte."))}
    end
  end

  # --- Drawers -------------------------------------------------------------------------

  defp close_drawer(socket) do
    assign(socket,
      panel: nil,
      add_error: nil,
      editing: nil,
      member_form: nil,
      member_error: nil
    )
  end

  defp add_error(socket, message), do: assign(socket, :add_error, message)

  # Keeps the drawer open on the submitted values; a partial save (the service
  # before a refused role change) is already in the reloaded list.
  defp member_error(socket, attrs, message, errors \\ []) do
    socket = reload_members(socket)
    editing = Enum.find(socket.assigns.members, &(&1.id == socket.assigns.editing.id))

    socket
    |> assign(:editing, editing || socket.assigns.editing)
    |> assign(:member_form, to_form(attrs, as: "member", errors: errors))
    |> assign(:member_error, message)
  end

  # --- Account status -------------------------------------------------------------

  # Only computed for staff managers (heads of this school). An account this school
  # created that still cannot be reset, and that is neither an operator's, the
  # viewer's own nor another head's (operator console spec §3), is one the person
  # also uses in another school (see `Checks.ActiveInAnotherSchool`).
  defp account_status(%User{} = user, roles, workspace_id, resettable?, viewer_id) do
    cond do
      user.created_in_workspace_id == workspace_id and not resettable? and user.role != :admin and
        user.id != viewer_id and :head not in roles ->
        %{
          created_here_status(user)
          | note:
              gettext(
                "Ce compte est aussi utilisé dans un autre établissement : la personne doit réinitialiser son mot de passe par e-mail ou demander à un administrateur."
              )
        }

      user.created_in_workspace_id == workspace_id ->
        created_here_status(user)

      # An invited account the head has reset (operator console spec §3).
      is_nil(user.created_in_workspace_id) and user.must_change_password ->
        created_here_status(user)

      user.phone && user.created_in_workspace_id ->
        linked_status()

      resettable? ->
        %{kind: :active, label: gettext("Actif"), note: gettext("Compte personnel")}

      true ->
        self_managed_status()
    end
  end

  defp created_here_status(user) do
    cond do
      Accounts.temporary_password_expired?(user) ->
        %{
          kind: :expired,
          label: gettext("Mot de passe expiré"),
          note: gettext("Expiré — donnez-en un nouveau")
        }

      user.must_change_password ->
        %{
          kind: :pending,
          label: gettext("Mot de passe temporaire"),
          note:
            gettext("Pas encore connecté·e · expire le %{date}",
              date: Dates.day_month(expiry_date(user))
            )
        }

      true ->
        %{
          kind: :active,
          label: gettext("Actif"),
          note: gettext("Compte créé par l'établissement")
        }
    end
  end

  defp linked_status do
    %{
      kind: :linked,
      label: gettext("Compte lié"),
      note: gettext("Créé par un autre établissement")
    }
  end

  defp self_managed_status do
    %{
      kind: :active,
      label: gettext("Actif"),
      note: gettext("Mot de passe géré par la personne")
    }
  end

  defp expiry_date(%User{temporary_password_expires_at: %DateTime{} = at}),
    do: DateTime.to_date(at)

  defp expiry_date(_user), do: Date.add(TeacherAssistant.Academics.Reference.today(), 7)

  defp temporary_password_info(socket, user_id, password, kind) do
    user =
      Enum.find_value(socket.assigns.members, fn m -> m.user_id == user_id && m.user end)

    name = User.display_name(user)
    login = User.contact(user)

    %{
      kind: kind,
      name: name,
      login: login,
      value: password,
      expires_on: expiry_date(user),
      message:
        gettext(
          "%{school} — connexion : numéro %{login}, mot de passe temporaire %{password} (valable 7 jours).",
          school: socket.assigns.scope.current_workspace.name,
          login: login,
          password: password
        )
    }
  end

  # --- Display helpers ----------------------------------------------------------------

  # « 11 membres · 1 compte en attente de première connexion · 2 invitations en attente »;
  # account states and invitations are for staff managers only.
  defp summary_line(members, invitations, states, manager?) do
    pending = Enum.count(states, fn {_id, s} -> s.kind in [:pending, :expired] end)

    [
      ngettext("1 membre", "%{count} membres", length(members)),
      (manager? and pending > 0) &&
        ngettext(
          "1 compte en attente de première connexion",
          "%{count} comptes en attente de première connexion",
          pending
        ),
      (manager? and invitations != []) &&
        ngettext(
          "1 invitation en attente",
          "%{count} invitations en attente",
          length(invitations)
        )
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp invitation_meta(inv) do
    roles = inv.roles |> Enum.map(&role_short/1) |> Enum.join(", ")

    case inv.expires_at do
      %DateTime{} = at ->
        roles <>
          " · " <> gettext("expire le %{date}", date: Dates.day_month(DateTime.to_date(at)))

      _ ->
        roles
    end
  end

  # Short labels for the list's chips; the full label is the chip's title.
  defp role_short(:head), do: gettext("Chef d'étab.")
  defp role_short(:vice_principal), do: gettext("Censeur")
  defp role_short(:discipline_master), do: gettext("Surveillant gén.")
  defp role_short(:bursar), do: gettext("Intendant")
  defp role_short(:hod), do: gettext("Animateur péd.")
  defp role_short(:teacher), do: gettext("Enseignant")
  defp role_short(:guidance_counsellor), do: gettext("Orientation")
  defp role_short(:librarian), do: gettext("Documentaliste")

  defp role_options, do: Enum.map(SchoolRole.values(), &{SchoolRole.label(&1), to_string(&1)})

  # --- Forms & data ----------------------------------------------------------------

  # The invite dialog binds to `SchoolInvitation :create` for its email field.
  # Submit still routes through `Accounts.invite_member/2`, which owns the
  # token/expiry generation, the "already a member" guard and the invitation
  # email — behaviour the bare create action does not reproduce.
  defp invite_form do
    SchoolInvitation
    |> AshPhoenix.Form.for_create(:create, as: "invite")
    |> to_form()
  end

  defp account_form(params \\ %{}, errors \\ []) do
    to_form(params, as: "account", errors: errors)
  end

  # The drawer's fields span three actions (roles, status, statutory hours), each
  # with its own policy and guard, so it is a plain form saved field by field.
  defp member_form(m) do
    to_form(
      %{
        "roles" => Enum.map(m.roles, &to_string/1),
        "status" => if(m.status, do: to_string(m.status), else: ""),
        "service" => to_string(m.statutory_hours || "")
      },
      as: "member"
    )
  end

  defp checked_roles(%Phoenix.HTML.Form{params: %{"roles" => roles}}) when is_list(roles),
    do: parse_roles(roles)

  defp checked_roles(_form), do: [:teacher]

  defp membership_status_options,
    do: Enum.map(MembershipStatus.values(), &{MembershipStatus.label(&1), to_string(&1)})

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp reload_members(socket) do
    scope = socket.assigns.scope
    members = Accounts.list_members(scope)
    workspace_id = scope.current_workspace.id

    # One policy check per row: done here, never in render.
    resettable =
      if socket.assigns.can_manage_staff?,
        do:
          for(
            m <- members,
            Accounts.can_reset_member_password?(scope, m.user),
            into: MapSet.new(),
            do: m.id
          ),
        else: MapSet.new()

    # Colleagues' password state is for staff managers only.
    states =
      if socket.assigns.can_manage_staff?,
        do:
          Map.new(members, fn m ->
            {m.id,
             account_status(
               m.user,
               m.roles,
               workspace_id,
               MapSet.member?(resettable, m.id),
               scope.current_user.id
             )}
          end),
        else: %{}

    socket
    |> assign(:members, members)
    |> assign(:resettable_member_ids, resettable)
    |> assign(:account_states, states)
    |> assign(:invitations, Accounts.list_pending_invitations(scope))
    |> apply_filters()
  end

  defp apply_filters(socket) do
    %{members: members, invitations: invitations, query: query, role_filter: role} =
      socket.assigns

    needle = fold(query)
    digits = String.replace(query, ~r/\D/, "")

    socket
    |> assign(
      :visible_members,
      Enum.filter(members, &(role_match?(&1.roles, role) and member_match?(&1, needle, digits)))
    )
    |> assign(
      :visible_invitations,
      Enum.filter(
        invitations,
        &(role_match?(&1.roles, role) and String.contains?(fold(to_string(&1.email)), needle))
      )
    )
  end

  defp role_match?(_roles, nil), do: true
  defp role_match?(roles, role), do: role in roles

  defp member_match?(_m, "", _digits), do: true

  defp member_match?(%{user: user}, needle, digits) do
    Enum.any?([user.name, user.email && to_string(user.email)], fn text ->
      is_binary(text) and String.contains?(fold(text), needle)
    end) or
      (digits != "" and is_binary(user.phone) and
         String.contains?(String.replace(user.phone, ~r/\D/, ""), digits))
  end

  # Case- and accent-insensitive: « Éloïse » matches « eloise ».
  defp fold(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  defp parse_role(value) when is_binary(value),
    do: Enum.find(SchoolRole.values(), &(to_string(&1) == value))

  defp parse_role(_value), do: nil

  defp parse_roles(roles) when is_list(roles) do
    roles
    |> Enum.map(&parse_role/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> [:teacher]
      parsed -> parsed
    end
  end

  defp parse_roles(_roles), do: [:teacher]

  defp parse_membership_status(status) when is_binary(status),
    do: Enum.find(MembershipStatus.values(), &(to_string(&1) == status))

  defp parse_membership_status(_status), do: nil

  defp find_invitation(scope, id) do
    scope
    |> Accounts.list_pending_invitations()
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end

  defp find_membership(scope, id) do
    scope
    |> Accounts.list_members()
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end
end
