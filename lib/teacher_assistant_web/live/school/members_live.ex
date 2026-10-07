defmodule TeacherAssistantWeb.School.MembersLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.{MembershipStatus, SchoolInvitation, SchoolRole, User}
  alias TeacherAssistant.Accounts
  alias TeacherAssistantWeb.Dates

  @drawer "#add-member-drawer"

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    # Reads are policy-checked; a non-member has no workspace in scope.
    if scope.current_workspace do
      {:ok,
       socket
       |> assign(:scope, scope)
       |> assign(:can_manage_staff?, Accounts.can_manage_staff?(scope))
       |> assign(:can_set_service?, Accounts.can_set_member_service?(scope))
       |> assign(:invite_form, invite_form())
       |> assign(:account_form, account_form())
       # The drawer opens client-side (JS.show); the server only forces it
       # visible to show an error, and closes it after a success.
       |> assign(:drawer_open, false)
       |> assign(:drawer_error, nil)
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
      <section id="school-members" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Membres")}>
          <:actions :if={@can_manage_staff?}>
            <button
              id="open-add-member"
              type="button"
              class="btn btn-primary btn-sm transition-transform active:scale-[0.97]"
              phx-click={show_drawer()}
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Ajouter un membre")}
            </button>
          </:actions>
        </.page_header>

        <div class="overflow-x-auto">
          <table id="members-table" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Nom")}</th>
                <th>{gettext("Rôles")}</th>
                <th>{gettext("Statut")}</th>
                <th>{gettext("Service (h/sem.)")}</th>
                <th>{gettext("Compte")}</th>
                <th :if={@can_manage_staff?}><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={m <- @members} id={"member-row-#{m.id}"}>
                <td>
                  <span class="block font-medium">{User.display_name(m.user)}</span>
                  <span
                    :if={m.user.name && User.contact(m.user)}
                    class="mt-0.5 flex items-center gap-1.5 text-xs text-base-content/60"
                  >
                    <span class="ta-num rounded border border-base-300 px-1 text-[0.6rem] font-semibold leading-4 tracking-wide">
                      {if m.user.email, do: "@", else: gettext("TÉL")}
                    </span>
                    <span class={!m.user.email && "ta-num"}>{User.contact(m.user)}</span>
                  </span>
                </td>
                <td>
                  <form
                    :if={@can_manage_staff?}
                    id={"roles-#{m.id}"}
                    phx-change="set_roles"
                    phx-value-id={m.id}
                    class="flex flex-wrap gap-2"
                  >
                    <label :for={role <- SchoolRole.values()} class="label cursor-pointer gap-1">
                      <input
                        type="checkbox"
                        name="roles[]"
                        value={role}
                        checked={role in m.roles}
                        class="checkbox checkbox-sm"
                      />
                      <span class="text-xs">{SchoolRole.label(role)}</span>
                    </label>
                  </form>
                  <span :if={!@can_manage_staff?}>
                    {m.roles |> Enum.map(&SchoolRole.label/1) |> Enum.join(", ")}
                  </span>
                </td>
                <td>
                  <form
                    :if={@can_manage_staff?}
                    id={"member-status-form-#{m.id}"}
                    phx-change="set_status"
                    phx-value-id={m.id}
                  >
                    <select name="status" class="select select-bordered select-xs">
                      <option value="" selected={is_nil(m.status)}>—</option>
                      <option :for={s <- MembershipStatus.values()} value={s} selected={m.status == s}>
                        {MembershipStatus.label(s)}
                      </option>
                    </select>
                  </form>
                  <span :if={!@can_manage_staff?}>
                    {if m.status, do: MembershipStatus.label(m.status), else: "—"}
                  </span>
                </td>
                <td>
                  <.form
                    :if={@can_set_service?}
                    for={%{}}
                    id={"service-#{m.id}"}
                    phx-submit="set_service"
                  >
                    <input type="hidden" name="membership_id" value={m.id} />
                    <input
                      name="service"
                      value={m.statutory_hours}
                      placeholder={gettext("École")}
                      inputmode="numeric"
                      class="input input-bordered input-xs w-16 text-right"
                    />
                  </.form>
                  <span :if={!@can_set_service?}>{m.statutory_hours || "—"}</span>
                </td>
                <td>
                  <.account_status_pill status={account_status(m.user, @scope.current_workspace.id)} />
                </td>
                <td :if={@can_manage_staff?}>
                  <div class="flex flex-wrap justify-end gap-1">
                    <button
                      :if={MapSet.member?(@resettable_member_ids, m.id)}
                      id={"reset-password-#{m.id}"}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="ask_reset_password"
                      phx-value-id={m.id}
                    >
                      <.icon name="hero-key" class="size-3.5" />
                      {gettext("Réinitialiser le mot de passe")}
                    </button>
                    <button
                      id={"member-deactivate-#{m.id}"}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="deactivate_member"
                      phx-value-id={m.id}
                      data-confirm={gettext("Désactiver ce membre ?")}
                    >
                      {gettext("Désactiver")}
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.empty_state
          :if={@members == []}
          icon="hero-user-group"
          title={gettext("Aucun membre actif pour le moment")}
        />

        <div :if={@can_manage_staff?} id="invitations-list" class="space-y-2">
          <h2 class="text-sm font-semibold">{gettext("Invitations en attente")}</h2>
          <.empty_state
            :if={@invitations == []}
            icon="hero-envelope"
            title={gettext("Aucune invitation en attente")}
          />
          <div
            :for={inv <- @invitations}
            id={"invitation-#{inv.id}"}
            class="flex items-center justify-between gap-3 rounded-lg border border-base-300 px-3 py-2"
          >
            <div class="text-sm">
              <span class="font-medium">{inv.email}</span>
              <span class="text-base-content/60">
                — {inv.roles |> Enum.map(&SchoolRole.label/1) |> Enum.join(", ")}
              </span>
            </div>
            <button
              id={"invite-revoke-#{inv.id}"}
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="revoke_invite"
              phx-value-id={inv.id}
              data-confirm={gettext("Révoquer cette invitation ?")}
            >
              {gettext("Révoquer")}
            </button>
          </div>
        </div>

        <.add_member_drawer
          :if={@can_manage_staff?}
          open={@drawer_open}
          error={@drawer_error}
          account_form={@account_form}
          invite_form={@invite_form}
        />

        <.confirm_reset_dialog :if={@reset_candidate} candidate={@reset_candidate} />

        <.temporary_password_dialog :if={@temporary_password} info={@temporary_password} />
      </section>
    </Layouts.app>
    """
  end

  # --- Components ----------------------------------------------------------------

  attr :status, :map, required: true

  defp account_status_pill(assigns) do
    ~H"""
    <span class={["badge badge-sm whitespace-nowrap", @status.tone]}>{@status.label}</span>
    <span class="mt-1 block text-xs text-base-content/60">{@status.note}</span>
    """
  end

  attr :open, :boolean, required: true
  attr :error, :string, default: nil
  attr :account_form, Phoenix.HTML.Form, required: true
  attr :invite_form, Phoenix.HTML.Form, required: true

  # Always in the DOM (shown/hidden with JS) so both forms exist before it opens.
  defp add_member_drawer(assigns) do
    ~H"""
    <div
      id="add-member-drawer"
      data-open={@open}
      data-hide={hide_drawer()}
      class={["fixed inset-0 z-40", !@open && "hidden"]}
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-member-title"
      phx-window-keydown={hide_drawer()}
      phx-key="escape"
    >
      <div class="absolute inset-0 bg-black/50" aria-hidden="true" phx-click={hide_drawer()}></div>
      <aside
        id="add-member-panel"
        class="absolute inset-y-0 right-0 flex w-full max-w-md flex-col border-l border-base-300 bg-base-100 shadow-2xl"
      >
        <header class="flex items-start justify-between gap-3 border-b border-base-300 px-5 py-4">
          <div>
            <p class="ta-eyebrow">{gettext("Équipe")}</p>
            <h2 id="add-member-title" class="mt-1 text-xl font-semibold">
              {gettext("Ajouter un membre")}
            </h2>
          </div>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-square"
            aria-label={gettext("Fermer")}
            phx-click={hide_drawer()}
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>

        <div class="flex-1 space-y-5 overflow-y-auto px-5 pt-5">
          <div :if={@error} id="add-member-error" role="alert" class="alert alert-error alert-soft">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>{@error}</span>
          </div>

          <div class="grid grid-cols-2 gap-2" role="radiogroup" aria-label={gettext("Méthode")}>
            <.method_card
              id="method-phone"
              checked
              icon="hero-device-phone-mobile"
              title={gettext("Par téléphone")}
              hint={
                gettext(
                  "Pour qui n'a pas d'e-mail. Vous recevez un mot de passe temporaire à transmettre."
                )
              }
              on_click={choose_method("phone", "email")}
            />
            <.method_card
              id="method-email"
              icon="hero-envelope"
              title={gettext("Par invitation e-mail")}
              hint={gettext("La personne reçoit un lien et crée son mot de passe elle-même.")}
              on_click={choose_method("email", "phone")}
            />
          </div>

          <div id="member-method-phone">
            <.form
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
                <p class="text-xs text-base-content/60">
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
              <.drawer_footer submit={gettext("Créer le compte")} busy={gettext("Création…")} />
            </.form>
          </div>

          <div id="member-method-email" class="hidden">
            <.form for={@invite_form} id="invite-form" phx-submit="invite" class="space-y-4">
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
              <.drawer_footer submit={gettext("Inviter")} busy={gettext("Envoi…")} />
            </.form>
          </div>
        </div>
      </aside>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :checked, :boolean, default: false
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, required: true
  attr :on_click, :any, required: true

  defp method_card(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="radio"
      aria-checked={to_string(@checked)}
      phx-click={@on_click}
      class="group rounded-box border border-base-300 p-3 text-left transition-colors hover:border-primary/60 aria-checked:border-primary aria-checked:bg-primary/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    >
      <span class="flex items-center gap-2 text-sm font-semibold">
        <.icon
          name={@icon}
          class="size-4 text-base-content/60 group-aria-checked:text-primary"
        />
        {@title}
      </span>
      <span class="mt-1 block text-xs leading-snug text-base-content/65">{@hint}</span>
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
          class="cursor-pointer select-none rounded-full border border-base-300 px-3 py-1 text-sm transition-colors hover:border-primary/60 has-[:checked]:border-primary has-[:checked]:bg-primary/15 has-[:checked]:text-primary has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-primary"
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

  attr :submit, :string, required: true
  attr :busy, :string, required: true

  defp drawer_footer(assigns) do
    ~H"""
    <div class="sticky bottom-0 -mx-5 flex justify-end gap-2 border-t border-base-300 bg-base-100 px-5 py-3">
      <button type="button" class="btn btn-ghost btn-sm" phx-click={hide_drawer()}>
        {gettext("Annuler")}
      </button>
      <button type="submit" class="btn btn-primary btn-sm" phx-disable-with={@busy}>
        {@submit}
      </button>
    </div>
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
            <p class="ta-eyebrow text-base-content/60">{gettext("Identifiant")}</p>
            <p class="ta-num mt-0.5">{@info.login}</p>
          </div>
          <div>
            <p class="ta-eyebrow text-base-content/60">{gettext("Mot de passe temporaire")}</p>
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

  # --- Events ----------------------------------------------------------------------

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
         socket |> assign(:invite_form, invite_form()) |> close_drawer() |> reload_members()}

      {:error, :already_member} ->
        {:noreply, drawer_error(socket, gettext("Cette personne est déjà membre de l'école."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, drawer_error(socket, gettext("Impossible d'envoyer l'invitation."))}
    end
  end

  def handle_event("create_account", %{"account" => params}, socket) do
    if blank?(params["name"]) do
      {:noreply,
       socket
       |> assign(:account_form, account_form(params, name: {gettext("Indiquez le nom."), []}))
       |> drawer_error(nil)}
    else
      create_account(socket, params)
    end
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, socket |> assign(:drawer_open, false) |> assign(:drawer_error, nil)}
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
      {:noreply, reload_members(socket)}
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

  def handle_event("set_roles", %{"id" => id} = params, socket) do
    scope = socket.assigns.scope
    roles = parse_roles(params["roles"])

    with %{} = membership <- find_membership(scope, id),
         {:ok, _} <- Accounts.update_member_roles(scope, membership, roles) do
      {:noreply, reload_members(socket)}
    else
      {:error, :last_head} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Impossible de retirer le rôle de chef d'établissement du dernier chef.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_service", %{"membership_id" => id, "service" => value}, socket) do
    scope = socket.assigns.scope

    with %{} = m <- find_membership(scope, id),
         {:ok, _} <- Accounts.set_member_service(scope, m, value) do
      {:noreply, socket |> reload_members() |> put_flash(:info, gettext("Réglage enregistré."))}
    else
      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_hours} ->
        {:noreply,
         put_flash(socket, :error, gettext("Indiquez un nombre d'heures entre 1 et 40."))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_status", %{"id" => id, "status" => status}, socket) do
    scope = socket.assigns.scope

    with %{} = membership <- find_membership(scope, id),
         {:ok, _} <-
           Accounts.update_member_status(scope, membership, parse_membership_status(status)) do
      {:noreply, reload_members(socket)}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

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
         |> drawer_error(nil)}

      {:error, :already_member} ->
        {:noreply,
         socket
         |> assign(:account_form, account_form(params))
         |> drawer_error(gettext("Déjà membre de l'établissement."))}

      {:error, :forbidden} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:account_form, account_form(params))
         |> drawer_error(gettext("Impossible de créer le compte."))}
    end
  end

  # --- Drawer -------------------------------------------------------------------------

  defp show_drawer do
    JS.show(to: @drawer)
    |> JS.transition({"ease-out duration-200", "translate-x-full", "translate-x-0"},
      to: "#add-member-panel",
      time: 200
    )
    |> JS.focus_first(to: "#add-member-panel")
  end

  defp hide_drawer do
    JS.hide(
      to: @drawer,
      transition: {"ease-in duration-150", "opacity-100", "opacity-0"},
      time: 150
    )
    |> JS.push("close_drawer")
  end

  defp choose_method(chosen, other) do
    JS.show(to: "#member-method-#{chosen}")
    |> JS.hide(to: "#member-method-#{other}")
    |> JS.set_attribute({"aria-checked", "true"}, to: "#method-#{chosen}")
    |> JS.set_attribute({"aria-checked", "false"}, to: "#method-#{other}")
  end

  # Keeps the drawer on screen (it may have been opened client-side only).
  defp drawer_error(socket, message) do
    socket |> assign(:drawer_open, true) |> assign(:drawer_error, message)
  end

  # The drawer was opened with JS.show, so the server asks the client to run its
  # `data-hide` command (see the "phx:js-exec" listener in app.js).
  defp close_drawer(socket) do
    socket
    |> assign(:drawer_open, false)
    |> assign(:drawer_error, nil)
    |> push_event("js-exec", %{to: @drawer, attr: "data-hide"})
  end

  # --- Account status -------------------------------------------------------------

  defp account_status(%User{} = user, workspace_id) do
    cond do
      user.created_in_workspace_id == workspace_id -> created_here_status(user)
      user.phone && user.created_in_workspace_id -> linked_status()
      true -> self_managed_status()
    end
  end

  defp created_here_status(user) do
    cond do
      Accounts.temporary_password_expired?(user) ->
        %{
          label: gettext("Mot de passe expiré"),
          tone: "badge-error badge-soft",
          note: gettext("Expiré — donnez-en un nouveau")
        }

      user.must_change_password ->
        %{
          label: gettext("Mot de passe temporaire"),
          tone: "badge-warning badge-soft",
          note:
            gettext("Pas encore connecté·e · expire le %{date}",
              date: Dates.day_month(expiry_date(user))
            )
        }

      true ->
        %{
          label: gettext("Actif"),
          tone: "badge-success badge-soft",
          note: gettext("Compte créé par l'établissement")
        }
    end
  end

  defp linked_status do
    %{
      label: gettext("Compte lié"),
      tone: "badge-info badge-soft",
      note: gettext("Créé par un autre établissement")
    }
  end

  defp self_managed_status do
    %{
      label: gettext("Actif"),
      tone: "badge-success badge-soft",
      note: gettext("Mot de passe géré par la personne")
    }
  end

  defp expiry_date(%User{temporary_password_expires_at: %DateTime{} = at}),
    do: DateTime.to_date(at)

  defp expiry_date(_user), do: Date.add(Date.utc_today(), 7)

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

  defp checked_roles(%Phoenix.HTML.Form{params: %{"roles" => roles}}) when is_list(roles),
    do: parse_roles(roles)

  defp checked_roles(_form), do: [:teacher]

  defp membership_status_options,
    do: Enum.map(MembershipStatus.values(), &{MembershipStatus.label(&1), &1})

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp reload_members(socket) do
    scope = socket.assigns.scope
    members = Accounts.list_members(scope)

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

    socket
    |> assign(:members, members)
    |> assign(:resettable_member_ids, resettable)
    |> assign(:invitations, Accounts.list_pending_invitations(scope))
  end

  defp parse_roles(nil), do: [:teacher]
  defp parse_roles([]), do: [:teacher]

  defp parse_roles(roles) when is_list(roles) do
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
