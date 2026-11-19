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

    day =
      Enum.find(days, &(Atom.to_string(&1) == params["day"])) ||
        if(today in days, do: today, else: List.first(days))

    {:noreply, assign(socket, tab: tab, day: day)}
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
  end

  defp load_profile(socket) do
    %{scope: scope, member: member} = socket.assigns
    profile = TeacherProfile.load(scope, member, allowed?: true)

    assign(socket,
      profile: profile,
      show_timetable?:
        TeacherAssistant.Scope.module?(scope, :emploi_du_temps) &&
          (:teacher in member.roles || match?({:ok, %{teaching?: true}}, profile))
    )
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
