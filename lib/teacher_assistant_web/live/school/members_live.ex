defmodule TeacherAssistantWeb.School.MembersLive do
  @moduledoc """
  Membres (UX refonte 2026-11-03 « Membres »): a table with checkboxes (Membre and
  contact, Rôles, Service, Accès) on wide screens, the list on phones; filter pills
  by role with counts and « Jamais connectés » (staff managers: `last_sign_in_at`
  still nil); a selection bar that copies the selected members' numbers. The
  « Ajouter un membre » and member drawers, resets and invitations are unchanged.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.{MembershipStatus, SchoolInvitation, SchoolRole, User}
  alias TeacherAssistant.{Accounts, Timetabling}
  alias TeacherAssistantWeb.Dates

  import TeacherAssistantWeb.School.MembersComponents

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
       |> assign(:never, false)
       |> assign(:selected, MapSet.new())
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
      <section id="school-members" class="mx-auto max-w-[1040px] space-y-5">
        <.page_header
          eyebrow={gettext("Organisation")}
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

        <.filter_pills :if={@members != []} id="member-filters" label={gettext("Filtrer par rôle")}>
          <:pill
            id="filter-all"
            patch={~p"/school/members"}
            count={length(@members)}
            current={is_nil(@role_filter) and not @never}
          >
            {gettext("Tous")}
          </:pill>
          <:pill
            :if={@can_manage_staff?}
            id="filter-never"
            patch={~p"/school/members?f=never"}
            count={@counts.never}
            current={@never}
          >
            {gettext("Jamais connectés")}
          </:pill>
          <:pill
            :for={{role, count} <- @counts.roles}
            id={"filter-#{role}"}
            patch={~p"/school/members?role=#{role}"}
            count={count}
            current={@role_filter == role}
          >
            {role_short(role)}
          </:pill>
        </.filter_pills>

        <form
          id="members-filter"
          phx-change="filter"
          phx-submit="filter"
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
        </form>

        <div
          :if={@visible_members != []}
          id="members-table"
          class="ta-section hidden overflow-x-auto sm:block"
        >
          <table class="table">
            <thead>
              <tr class="text-xs text-base-content/70">
                <th class="w-10">
                  <input
                    id="select-all"
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    checked={all_selected?(@visible_members, @selected)}
                    phx-click="toggle_all"
                    aria-label={gettext("Tout sélectionner")}
                  />
                </th>
                <th>{gettext("Membre")}</th>
                <th>{gettext("Rôles")}</th>
                <th>{gettext("Service")}</th>
                <th :if={@can_manage_staff?}>{gettext("Accès")}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={m <- @visible_members}
                id={"member-tr-#{m.id}"}
                class={[
                  "transition-colors hover:bg-base-200/50",
                  MapSet.member?(@selected, m.id) && "bg-primary/8"
                ]}
              >
                <td>
                  <input
                    id={"select-#{m.id}"}
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    checked={MapSet.member?(@selected, m.id)}
                    phx-click="toggle_select"
                    phx-value-id={m.id}
                    aria-label={gettext("Sélectionner %{name}", name: User.display_name(m.user))}
                  />
                </td>
                <td class="min-w-0">
                  <button
                    :if={@can_manage_staff? or @can_set_service?}
                    id={"member-open-#{m.id}"}
                    type="button"
                    phx-click="edit_member"
                    phx-value-id={m.id}
                    class="text-left font-semibold hover:text-primary"
                  >
                    {User.display_name(m.user)}
                  </button>
                  <span :if={!(@can_manage_staff? or @can_set_service?)} class="font-semibold">
                    {User.display_name(m.user)}
                  </span>
                  <span
                    :if={m.user.name && User.contact(m.user)}
                    class={["block text-xs text-base-content/70", !m.user.email && "ta-num"]}
                  >
                    {User.contact(m.user)}
                  </span>
                </td>
                <td class="text-xs">
                  {m.roles |> Enum.map(&role_short/1) |> Enum.join(", ")}
                </td>
                <td id={"member-service-#{m.id}"} class="ta-num whitespace-nowrap text-xs">
                  <.service_cell member={m} service={@services[m.user_id]} />
                </td>
                <td :if={@can_manage_staff?} id={"member-access-#{m.id}"}>
                  <.member_access state={@account_states[m.id]} user={m.user} />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          :if={@visible_members != []}
          id="members-list"
          class="ta-section sm:hidden"
          aria-label={gettext("Membres")}
        >
          <.member_row
            :for={m <- @visible_members}
            member={m}
            state={@account_states[m.id]}
            never?={@can_manage_staff? and is_nil(m.user.last_sign_in_at)}
            editable?={@can_manage_staff? or @can_set_service?}
            selected={@editing && @editing.id == m.id}
          />
        </div>

        <.bulk_bar id="members-bulk" count={MapSet.size(@selected)} clear="clear_selection">
          <:actions>
            <span id="selected-phones" hidden>{selected_phones(@members, @selected)}</span>
            <button
              id="copy-phones"
              type="button"
              class="btn btn-primary btn-sm"
              disabled={selected_phones(@members, @selected) == ""}
              phx-click={JS.dispatch("phx:copy", to: "#selected-phones") |> JS.push("phones_copied")}
            >
              <.icon name="hero-clipboard-document" class="size-4" /> {gettext("Copier les numéros")}
            </button>
          </:actions>
        </.bulk_bar>

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
          roles={checked_roles(@account_form)}
        />

        <.member_drawer
          :if={@panel == :member and @editing}
          member={@editing}
          form={@member_form}
          error={@member_error}
          state={@account_states[@editing.id]}
          resettable?={MapSet.member?(@resettable_member_ids, @editing.id)}
          renamable?={MapSet.member?(@renamable_member_ids, @editing.id)}
          can_manage_staff?={@can_manage_staff?}
          can_set_service?={@can_set_service?}
          roles={checked_roles(@member_form)}
        />

        <.confirm_reset_dialog :if={@reset_candidate} candidate={@reset_candidate} />

        <.temporary_password_dialog :if={@temporary_password} info={@temporary_password} />
      </section>
    </Layouts.app>
    """
  end

  # The pills: a role (`?role=teacher`) or « Jamais connectés » (`?f=never`, staff
  # managers only).
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       role_filter: parse_role(params["role"]),
       never: params["f"] == "never" and socket.assigns.can_manage_staff?
     )
     |> apply_filters()}
  end

  # --- Events: list ------------------------------------------------------------------

  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:query, String.trim(params["q"] || ""))
     |> apply_filters()}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(query: "", role_filter: nil, never: false)
     |> apply_filters()
     |> push_patch(to: ~p"/school/members")}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected

    selected =
      case Enum.find(socket.assigns.visible_members, &(to_string(&1.id) == id)) do
        nil ->
          selected

        m ->
          if MapSet.member?(selected, m.id),
            do: MapSet.delete(selected, m.id),
            else: MapSet.put(selected, m.id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("toggle_all", _params, socket) do
    %{visible_members: visible, selected: selected} = socket.assigns
    ids = MapSet.new(visible, & &1.id)

    selected =
      if all_selected?(visible, selected),
        do: MapSet.difference(selected, ids),
        else: MapSet.union(selected, ids)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear_selection", _params, socket),
    do: {:noreply, assign(socket, :selected, MapSet.new())}

  def handle_event("phones_copied", _params, socket) do
    count =
      socket.assigns.members
      |> Enum.filter(&(MapSet.member?(socket.assigns.selected, &1.id) and &1.user.phone))
      |> length()

    {:noreply,
     put_flash(
       socket,
       :info,
       ngettext("%{count} numéro copié.", "%{count} numéros copiés.", count)
     )}
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
         :ok <- save_name(scope, m, attrs),
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

      {:error, :blank_name} ->
        {:noreply,
         member_error(socket, attrs, nil, name: {gettext("Indiquez le nom et le prénom."), []})}

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

  # The name field shows only to those who may rename (the `:rename_by_school` policy
  # decides); an unchanged name writes nothing. A member invited by e-mail may have no
  # name yet: the field may stay empty, but a name is never erased.
  defp save_name(scope, m, %{"name" => name}) when is_binary(name) do
    cond do
      blank?(name) and blank?(m.user.name) ->
        :ok

      blank?(name) ->
        {:error, :blank_name}

      Enum.join(String.split(name), " ") == m.user.name ->
        :ok

      true ->
        with {:ok, _user} <- Accounts.rename_member(scope, m, name), do: :ok
    end
  end

  defp save_name(_scope, _m, _attrs), do: :ok

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

    signed_in = Enum.count(members, & &1.user.last_sign_in_at)

    [
      ngettext("1 membre", "%{count} membres", length(members)),
      manager? &&
        ngettext(
          "%{count} connecté au moins une fois",
          "%{count} connectés au moins une fois",
          signed_in
        ),
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
        "name" => m.user.name || "",
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

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp reload_members(socket) do
    scope = socket.assigns.scope
    members = Accounts.list_members(scope)
    workspace_id = scope.current_workspace.id

    # Computed here for the whole list, never in render.
    resettable =
      if socket.assigns.can_manage_staff?,
        do: Accounts.resettable_member_ids(scope, members),
        else: MapSet.new()

    renamable =
      if socket.assigns.can_manage_staff?,
        do: Accounts.renamable_member_ids(scope, members),
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
    |> assign(:services, Timetabling.teacher_services(scope, members))
    |> assign(
      :selected,
      MapSet.intersection(socket.assigns.selected, MapSet.new(members, & &1.id))
    )
    |> assign(:counts, counts(members))
    |> assign(:resettable_member_ids, resettable)
    |> assign(:renamable_member_ids, renamable)
    |> assign(:account_states, states)
    |> assign(:invitations, Accounts.list_pending_invitations(scope))
    |> apply_filters()
  end

  defp apply_filters(socket) do
    %{members: members, invitations: invitations, query: query, role_filter: role} =
      socket.assigns

    never = socket.assigns.never
    needle = fold(query)
    digits = String.replace(query, ~r/\D/, "")

    socket
    |> assign(
      :visible_members,
      Enum.filter(
        members,
        &(role_match?(&1.roles, role) and never_match?(&1, never) and
            member_match?(&1, needle, digits))
      )
    )
    |> assign(
      :visible_invitations,
      Enum.filter(
        invitations,
        &(not never and role_match?(&1.roles, role) and
            String.contains?(fold(to_string(&1.email)), needle))
      )
    )
  end

  defp never_match?(_m, false), do: true
  defp never_match?(m, true), do: is_nil(m.user.last_sign_in_at)

  # The pills' counts, whatever the search: never signed in, and each role held.
  defp counts(members) do
    %{
      never: Enum.count(members, &is_nil(&1.user.last_sign_in_at)),
      roles:
        for(
          role <- SchoolRole.values(),
          count = Enum.count(members, &(role in &1.roles)),
          count > 0,
          do: {role, count}
        )
    }
  end

  defp all_selected?([], _selected), do: false
  defp all_selected?(visible, selected), do: Enum.all?(visible, &MapSet.member?(selected, &1.id))

  # The selected members' phone numbers, for « Copier les numéros ».
  defp selected_phones(members, selected) do
    members
    |> Enum.filter(&(MapSet.member?(selected, &1.id) and &1.user.phone))
    |> Enum.map_join(", ", &to_string(&1.user.phone))
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
