defmodule TeacherAssistantWeb.School.MembersComponents do
  @moduledoc """
  The Membres page's parts: a member's row, the « Ajouter un membre » and member
  drawers, and the reset and temporary-password dialogs. Events are handled by
  `TeacherAssistantWeb.School.MembersLive`.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Accounts.{MembershipStatus, SchoolRole, User}
  alias TeacherAssistantWeb.Dates

  import TeacherAssistantWeb.Drawer
  import TeacherAssistantWeb.Modal

  attr :member, :map, required: true
  attr :state, :map, default: nil, doc: "the account state; staff managers only"
  attr :editable?, :boolean, required: true
  attr :selected, :boolean, default: false

  def member_row(assigns) do
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
  attr :roles, :list, required: true, doc: "the roles ticked in `account_form`"

  def add_member_drawer(assigns) do
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
        <.role_chips name="account[roles][]" checked={@roles} />
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
  attr :roles, :list, required: true, doc: "the roles ticked in `form`"

  def member_drawer(assigns) do
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
          <.role_chips name="member[roles][]" checked={@roles} />
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

  def confirm_reset_dialog(assigns) do
    ~H"""
    <.modal
      id="confirm-reset-dialog"
      title={gettext("Nouveau mot de passe pour %{name} ?", name: @candidate.name)}
      on_close="cancel_reset_password"
    >
      <p class="text-sm text-base-content/80">
        {gettext(
          "L'ancien mot de passe cesse de fonctionner et %{name} est déconnecté·e de tous ses appareils. Vous verrez le nouveau mot de passe temporaire une seule fois.",
          name: @candidate.name
        )}
      </p>
      <:actions>
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
      </:actions>
    </.modal>
    """
  end

  attr :info, :map, required: true

  def temporary_password_dialog(assigns) do
    ~H"""
    <%!-- no Escape or backdrop: the password is shown once, so it is closed on purpose --%>
    <.modal
      id="temporary-password-dialog"
      class="max-w-lg"
      eyebrow={
        if @info.kind == :created,
          do: gettext("Compte créé"),
          else: gettext("Mot de passe réinitialisé")
      }
      title={gettext("Mot de passe temporaire de %{name}", name: @info.name)}
    >
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

      <:actions>
        <button
          id="close-temporary-password"
          type="button"
          class="btn btn-primary"
          phx-click="close_temporary_password"
        >
          {gettext("C'est noté")}
        </button>
      </:actions>
    </.modal>
    """
  end

  @doc "A role's short label, for a row's chips and an invitation's line."
  def role_short(:head), do: gettext("Chef d'étab.")
  def role_short(:vice_principal), do: gettext("Censeur")
  def role_short(:discipline_master), do: gettext("Surveillant gén.")
  def role_short(:bursar), do: gettext("Intendant")
  def role_short(:hod), do: gettext("Animateur péd.")
  def role_short(:teacher), do: gettext("Enseignant")
  def role_short(:guidance_counsellor), do: gettext("Orientation")
  def role_short(:librarian), do: gettext("Documentaliste")

  defp membership_status_options,
    do: Enum.map(MembershipStatus.values(), &{MembershipStatus.label(&1), to_string(&1)})
end
