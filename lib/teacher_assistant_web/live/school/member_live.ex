defmodule TeacherAssistantWeb.School.MemberLive do
  @moduledoc """
  One member's page (`/school/members/:id`), opened from Membres: the header with
  contact shortcuts, then Résumé, Emploi du temps and Paramètres. The tab and the
  timetable's day are in the address (`?tab=timetable&day=tuesday`), so the back
  button, a reload and a shared link land on the same view. Who may open it is
  unchanged from the old drawer: staff managers and those who set services.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.{SchoolRole, User}
  alias TeacherAssistant.Academics.{Reference, SchoolCalendar, TeacherProfile}
  alias TeacherAssistantWeb.School.MemberAccount

  import TeacherAssistantWeb.School.MemberProfileComponents
  import TeacherAssistantWeb.School.MembersComponents

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    manage? = scope.current_workspace && Accounts.can_manage_staff?(scope)
    service? = scope.current_workspace && Accounts.can_set_member_service?(scope)

    cond do
      is_nil(scope.current_workspace) ->
        {:ok, push_navigate(socket, to: ~p"/school")}

      not (manage? or service?) ->
        {:ok, socket |> Authz.put_not_allowed() |> push_navigate(to: ~p"/school/members")}

      member = find_member(scope, id) ->
        {:ok,
         socket
         |> assign(scope: scope, can_manage_staff?: manage?, can_set_service?: service?)
         |> assign(:today, SchoolCalendar.weekday(Reference.today()))
         |> assign(member_error: nil, reset_candidate: nil, temporary_password: nil)
         |> assign_member(member)
         |> load_profile()}

      true ->
        {:ok, not_found(socket)}
    end
  end

  # An unknown tab, or the timetable for a member without one, shows Résumé; an
  # unknown day shows today when it is a school day, else the first day.
  def handle_params(params, _uri, socket) do
    %{profile: profile, show_timetable?: timetable?, today: today} = socket.assigns
    days = profile_days(profile)

    tab =
      case params["tab"] do
        "timetable" when timetable? -> "timetable"
        "settings" -> "settings"
        _ -> "overview"
      end

    {:noreply, assign(socket, tab: tab, day: pick_day(days, params["day"], today))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="member-page" class="mx-auto flex max-w-[760px] flex-col gap-5">
        <.breadcrumb id="member-breadcrumb">
          <:crumb navigate={~p"/school/members"}>{gettext("Membres")}</:crumb>
          <:crumb>{User.display_name(@member.user)}</:crumb>
        </.breadcrumb>

        <header id="member-header" class="flex min-w-0 items-center gap-4">
          <.initials_avatar name={User.display_name(@member.user)} class="size-14 shrink-0 text-lg" />
          <div class="min-w-0 space-y-1.5">
            <h1 class="font-display break-words text-3xl font-semibold leading-none sm:text-[2.2rem]">
              {User.display_name(@member.user)}
            </h1>
            <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-base-content/80">
              <span
                :if={@member.user.name && User.contact(@member.user)}
                class={["truncate", !@member.user.email && "ta-num"]}
              >
                {User.contact(@member.user)}
              </span>
              <span>{@member.roles |> Enum.map(&SchoolRole.label/1) |> Enum.join(", ")}</span>
            </div>
          </div>
        </header>

        <.contact_actions member={@member} />
        <.profile_tabs member_id={@member.id} tab={@tab} timetable?={@show_timetable?} />
        <.academic_panels
          profile={@profile}
          member={@member}
          tab={@tab}
          timetable?={@show_timetable?}
          day={@day}
          today={@today}
        />
        <.member_settings
          member={@member}
          form={@member_form}
          error={@member_error}
          state={@account.states[@member.id]}
          resettable?={MapSet.member?(@account.resettable, @member.id)}
          renamable?={MapSet.member?(@account.renamable, @member.id)}
          can_manage_staff?={@can_manage_staff?}
          can_set_service?={@can_set_service?}
          roles={checked_roles(@member_form)}
          tab={@tab}
        />

        <.confirm_reset_dialog :if={@reset_candidate} candidate={@reset_candidate} />
        <.temporary_password_dialog :if={@temporary_password} info={@temporary_password} />
      </section>
    </Layouts.app>
    """
  end

  # The day strip stays buttons (`aria-pressed`); a day is part of the address but
  # replaces it, so paging through days does not fill the back button's history.
  def handle_event("member_day", %{"day" => value}, socket) do
    case Enum.find(profile_days(socket.assigns.profile), &(Atom.to_string(&1) == value)) do
      nil -> {:noreply, socket}
      day -> {:noreply, push_patch(socket, to: day_path(socket, day), replace: true)}
    end
  end

  def handle_event("retry_member_profile", _params, socket), do: {:noreply, load_profile(socket)}

  # One submit for the settings' fields. The service is saved first (it is the only
  # field that can be rejected as invalid input), then the name, the roles (refused
  # when they would leave the school without a head), then the status. Fields a
  # viewer may not change are not rendered, so they are not in the params; policies
  # still refuse a crafted request.
  #
  # Each change first re-reads the member: one deactivated meanwhile (the page may
  # stay open for hours on a phone) is not written to.
  def handle_event(event, params, socket)
      when event in ["save_member", "reset_password", "deactivate_member"] do
    case find_member(socket.assigns.scope, socket.assigns.member.id) do
      nil -> {:noreply, not_found(socket)}
      member -> change(event, params, assign(socket, :member, member))
    end
  end

  def handle_event("ask_reset_password", _params, socket) do
    m = socket.assigns.member
    {:noreply, assign(socket, :reset_candidate, %{id: m.id, name: User.display_name(m.user)})}
  end

  def handle_event("cancel_reset_password", _params, socket),
    do: {:noreply, assign(socket, :reset_candidate, nil)}

  def handle_event("close_temporary_password", _params, socket),
    do: {:noreply, assign(socket, :temporary_password, nil)}

  defp change("save_member", params, socket) do
    %{scope: scope, member: m} = socket.assigns
    attrs = Map.get(params, "member", %{})

    with :ok <- save_name(scope, m, attrs),
         {:ok, m} <- save_service(scope, m, attrs),
         {:ok, m} <- save_roles(scope, m, attrs),
         {:ok, _} <- save_status(scope, m, attrs) do
      {:noreply, socket |> reload_member() |> put_flash(:info, gettext("Membre mis à jour."))}
    else
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

  defp change("reset_password", _params, socket) do
    %{scope: scope, member: member} = socket.assigns
    socket = assign(socket, :reset_candidate, nil)

    case Accounts.reset_member_password(scope, member) do
      {:ok, password} ->
        socket = reload_member(socket)

        info =
          MemberAccount.temporary_password_info(
            scope,
            socket.assigns.member.user,
            password,
            :reset
          )

        {:noreply, assign(socket, :temporary_password, info)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Impossible de réinitialiser le mot de passe."))}
    end
  end

  defp change("deactivate_member", _params, socket) do
    case Accounts.deactivate_member(socket.assigns.scope, socket.assigns.member) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Membre désactivé."))
         |> push_navigate(to: ~p"/school/members")}

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

  # Keeps the submitted values and the message; a partial save (the service before a
  # refused role change) is already in the reloaded member.
  defp member_error(socket, attrs, message, errors \\ []) do
    socket
    |> reload_member()
    |> assign(:member_form, to_form(attrs, as: "member", errors: errors))
    |> assign(:member_error, message)
  end

  # After a change: the member as saved, with Résumé and the tabs recomputed (a new
  # service or role changes them), or the list when they are no longer here.
  defp reload_member(socket) do
    case find_member(socket.assigns.scope, socket.assigns.member.id) do
      nil -> not_found(socket)
      member -> socket |> assign_member(member) |> load_profile()
    end
  end

  # The settings' fields span three actions (roles, status, statutory hours), each
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

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  # The same policy-checked read as the list: only this school's active members.
  defp find_member(scope, id) do
    scope
    |> Accounts.list_members()
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end

  defp assign_member(socket, member) do
    %{scope: scope, can_manage_staff?: manage?} = socket.assigns

    socket
    |> assign(:member, member)
    |> assign(:page_title, User.display_name(member.user))
    |> assign(:account, MemberAccount.access(scope, [member], manage?))
    |> assign(member_form: member_form(member), member_error: nil)
  end

  defp load_profile(socket) do
    %{scope: scope, member: member} = socket.assigns
    profile = TeacherProfile.load(scope, member, allowed?: true)

    assign(socket,
      profile: profile,
      day: pick_day(profile_days(profile), socket.assigns[:day], socket.assigns.today),
      show_timetable?:
        TeacherAssistant.Scope.module?(scope, :emploi_du_temps) &&
          (:teacher in member.roles || match?({:ok, %{teaching?: true}}, profile))
    )
  end

  # The wanted day when the member has lessons that day, else today when it is a
  # school day, else the first day.
  defp pick_day(days, wanted, today) do
    Enum.find(days, &(Atom.to_string(&1) == to_string(wanted))) ||
      if(today in days, do: today, else: List.first(days))
  end

  defp profile_days({:ok, %{days: days}}), do: days
  defp profile_days(_profile), do: []

  defp day_path(socket, day),
    do: ~p"/school/members/#{socket.assigns.member.id}?#{[tab: "timetable", day: day]}"

  defp not_found(socket) do
    socket
    |> put_flash(:error, gettext("Membre introuvable."))
    |> push_navigate(to: ~p"/school/members")
  end
end
