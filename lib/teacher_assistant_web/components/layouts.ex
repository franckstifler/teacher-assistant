defmodule TeacherAssistantWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TeacherAssistantWeb, :html
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Organization
  alias TeacherAssistantWeb.NotificationText
  alias TeacherAssistantWeb.Spaces

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string,
    default: nil,
    doc:
      "the request path (set by `LiveUserAuth`'s handle_params hook); drives the active rail link and the class-switcher return_to"

  slot :inner_block, required: true

  def app(assigns) do
    current_scope = assigns[:current_scope]
    current_user = current_scope && current_scope.current_user

    workspaces = workspaces(current_scope, current_user)

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(
        :user_initial,
        current_user &&
          String.upcase(String.slice(User.display_name(current_user), 0, 1))
      )
      |> assign(:workspace_name, workspace_name(current_scope))
      |> assign(
        :workspace_id,
        current_scope && current_scope.current_workspace && current_scope.current_workspace.id
      )
      |> assign(:role_label, role_label(current_scope))
      |> assign(:workspace_type_label, workspace_type_label(current_scope))
      |> assign(:workspaces, workspaces)
      |> assign(:in_school?, current_scope && current_scope.current_workspace != nil)
      |> assign(:space, current_scope && current_scope.capabilities[:space])
      |> assign(:space_keys, (current_scope && current_scope.capabilities[:spaces]) || [])
      |> assign(:bell, current_scope && (current_scope.capabilities || %{})[:notifications])
      |> assign(:current_path, assigns[:current_path])
      |> assign(:operator?, current_user != nil and current_user.role == :admin)

    assigns =
      assign(assigns, :tabs, assigns.in_school? && assigns.space && Spaces.tab_bar(assigns.space))

    ~H"""
    <%= if @current_user do %>
      <div class="drawer lg:drawer-open">
        <input id="app-drawer" type="checkbox" class="drawer-toggle" />

        <div class="drawer-content flex min-h-screen flex-col bg-base-200 text-base-content">
          <header class="sticky top-0 z-30 flex min-h-14 items-center gap-2.5 border-b border-base-300 bg-base-200/95 py-1.5 pl-4 pr-1.5 backdrop-blur lg:hidden">
            <%!-- Without a role space (no school yet) there is no tab bar: the drawer is the menu. --%>
            <label
              :if={!@tabs}
              for="app-drawer"
              aria-label={gettext("Open navigation")}
              class="-ml-2 grid size-11 place-items-center rounded-lg"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
            <span class="grid size-8 flex-none place-items-center rounded-lg bg-primary text-primary-content ta-display text-sm font-bold">
              TA
            </span>
            <span class="min-w-0 flex-1 leading-tight">
              <span class="block truncate text-sm font-semibold">
                {@workspace_name || gettext("Teacher Assistant")}
              </span>
              <span :if={@space} class="ta-text-2 block truncate text-xs">
                {gettext("Espace %{space}", space: String.downcase(@space.label))}
              </span>
            </span>
            <.link
              :if={@bell}
              id="notification-bell-mobile"
              navigate={~p"/school/notifications"}
              aria-label={gettext("Notifications")}
              class="relative grid size-11 flex-none place-items-center rounded-lg"
            >
              <.icon name="hero-bell" class="size-[1.375rem]" />
              <span
                :if={@bell.unread > 0}
                class="badge badge-error badge-xs ta-num absolute right-1 top-1"
              >
                {@bell.unread}
              </span>
            </.link>
          </header>

          <main class={[
            "mx-auto w-full max-w-6xl flex-1 px-4 py-6 sm:px-6",
            @tabs && "pb-28 lg:pb-6"
          ]}>
            {render_slot(@inner_block)}
          </main>
        </div>

        <.tab_bar :if={@tabs} tabs={@tabs} current_path={@current_path} />
        <.more_sheet
          :if={@tabs}
          more={@tabs.more}
          current_user={@current_user}
          user_initial={@user_initial}
          space={@space}
          space_keys={@space_keys}
          workspaces={@workspaces}
          workspace_id={@workspace_id}
          current_path={@current_path}
        />

        <div class="drawer-side z-40">
          <label for="app-drawer" aria-label={gettext("Close navigation")} class="drawer-overlay"></label>
          <aside
            class="ta-rail flex min-h-screen w-64 flex-col gap-4 p-3"
            aria-label={gettext("Sidebar")}
          >
            <%!-- relative: the bell menu opens under this whole row, inside the rail. --%>
            <div class="relative flex items-start gap-1">
              <div id="workspace-switcher" class="dropdown min-w-0 flex-1">
                <div
                  tabindex="0"
                  role="button"
                  class="flex w-full items-center gap-2.5 rounded-lg p-1.5 text-left hover:bg-[color:var(--ta-rail-hover)]"
                >
                  <span class="grid size-8 flex-none place-items-center rounded-lg bg-primary text-primary-content ta-display text-sm font-bold">
                    TA
                  </span>
                  <span class="min-w-0 flex-1 leading-tight">
                    <span class="block truncate text-sm font-semibold ta-display">
                      {@workspace_name}
                    </span>
                    <span class="block truncate text-xs text-[color:var(--ta-rail-faint)]">
                      {@workspace_type_label}{if @role_label, do: " · #{@role_label}"}
                    </span>
                  </span>
                  <.icon
                    name="hero-chevron-up-down"
                    class="size-4 flex-none text-[color:var(--ta-rail-faint)]"
                  />
                </div>
                <div
                  tabindex="0"
                  class="dropdown-content menu z-50 mt-1 w-60 rounded-box border border-base-300 bg-base-100 p-1 text-base-content shadow"
                >
                  <ul>
                    <li :for={ws <- @workspaces} id={"workspace-switcher-item-#{ws.id}"}>
                      <.link
                        href={~p"/workspaces/select/#{ws.id}"}
                        class="flex items-center justify-between gap-2"
                      >
                        <span>{ws.name}</span>
                        <span class="badge badge-sm badge-primary">
                          {gettext("École")}
                        </span>
                      </.link>
                    </li>
                  </ul>
                  <div class="mt-1 border-t border-base-300 p-2">
                    <.link navigate={~p"/schools/new"} class="btn btn-primary btn-xs w-full">
                      {gettext("Créer un établissement")}
                    </.link>
                  </div>
                </div>
              </div>
              <.notification_bell :if={@bell} bell={@bell} />
            </div>

            <div
              :if={@in_school? and length(@space_keys) > 1}
              id="space-switcher"
              class="flex flex-wrap gap-1 px-1"
              role="navigation"
              aria-label={gettext("Espaces")}
            >
              <.link
                :for={key <- @space_keys}
                id={"space-switch-#{key}"}
                href={~p"/school/space/#{key}"}
                aria-current={@space && @space.key == key && "true"}
                class={[
                  "inline-flex min-h-7 items-center rounded-full px-2.5 text-xs font-medium transition-colors",
                  if(@space && @space.key == key,
                    do:
                      "bg-[color:var(--ta-rail-active-bg)] font-semibold text-[color:var(--ta-rail-active-fg)]",
                    else:
                      "text-[color:var(--ta-rail-muted)] hover:bg-[color:var(--ta-rail-hover)] hover:text-[color:var(--ta-rail-fg)]"
                  )
                ]}
              >
                {TeacherAssistantWeb.Spaces.label(key)}
              </.link>
            </div>

            <nav
              :if={@in_school? and @space}
              id="school-nav"
              class="flex flex-col gap-0.5"
              aria-label={gettext("School navigation")}
            >
              <%= for section <- @space.sections do %>
                <p class="ta-rail__label px-1.5 pb-1 pt-2">{section.label}</p>
                <.rail_link
                  :for={item <- section.items}
                  id={item.id}
                  href={item.path}
                  icon={item.icon}
                  badge={item[:badge]}
                  badge_tone={item[:badge_tone] || :warning}
                  current_path={@current_path}
                >
                  {item.label}
                </.rail_link>
              <% end %>
            </nav>

            <nav
              :if={@operator?}
              id="admin-nav"
              class="flex flex-col gap-0.5"
              aria-label={gettext("Administration")}
            >
              <p class="ta-rail__label px-1.5 pb-1 pt-2">{gettext("Administration")}</p>
              <.rail_link
                id="nav-admin-overview"
                href={~p"/admin"}
                icon="hero-chart-pie"
                current_path={@current_path}
              >
                {gettext("Vue d'ensemble")}
              </.rail_link>
              <.rail_link
                id="nav-admin-schools"
                href={~p"/admin/schools"}
                icon="hero-building-library"
                current_path={@current_path}
              >
                {gettext("Établissements")}
              </.rail_link>
              <.rail_link
                id="nav-admin-users"
                href={~p"/admin/users"}
                icon="hero-users"
                current_path={@current_path}
              >
                {gettext("Utilisateurs")}
              </.rail_link>
              <.rail_link
                id="nav-admin-journal"
                href={~p"/admin/journal"}
                icon="hero-document-text"
                current_path={@current_path}
              >
                {gettext("Journal")}
              </.rail_link>
            </nav>

            <div class="mt-auto flex flex-col gap-2 border-t border-[color:var(--ta-rail-line)] pt-3">
              <div class="flex items-center gap-2.5 px-1.5">
                <span class="grid size-8 flex-none place-items-center rounded-full bg-[#2B4A3D] text-xs font-semibold text-[#CFE9DC]">
                  {@user_initial}
                </span>
                <span class="min-w-0 flex-1 leading-tight">
                  <span class="block truncate text-sm font-semibold">{User.display_name(@current_user)}</span>
                  <span class="block truncate text-xs text-[color:var(--ta-rail-faint)]">
                    {(@space && gettext("Espace %{space}", space: String.downcase(@space.label))) ||
                      @role_label}
                  </span>
                </span>
              </div>
              <.theme_toggle id="theme-toggle-rail" />
              <div class="flex items-center gap-1">
                <.link href={~p"/sign-out"} method="delete" class="ta-rail__item flex-1">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4 flex-none" />
                  <span class="flex-1">{gettext("Sign out")}</span>
                </.link>
                <div id="locale-switch" class="flex items-center gap-0.5">
                  <.link
                    href={~p"/locale/fr"}
                    class="rounded px-2 py-1 text-xs font-semibold text-[color:var(--ta-rail-muted)] hover:text-[color:var(--ta-rail-fg)]"
                  >
                    FR
                  </.link>
                  <span class="text-[color:var(--ta-rail-faint)]">·</span>
                  <.link
                    href={~p"/locale/en"}
                    class="rounded px-2 py-1 text-xs font-semibold text-[color:var(--ta-rail-muted)] hover:text-[color:var(--ta-rail-fg)]"
                  >
                    EN
                  </.link>
                </div>
              </div>
            </div>
          </aside>
        </div>
      </div>
    <% else %>
      <div class="flex min-h-screen flex-col bg-base-200 text-base-content">
        <header class="sticky top-0 z-30 flex min-h-14 items-center gap-3 border-b border-base-300 bg-base-100/95 px-4 backdrop-blur sm:px-6">
          <a href="/" class="flex items-center gap-2.5">
            <span class="grid size-8 place-items-center rounded-lg bg-primary text-primary-content ta-display text-sm font-bold">
              TA
            </span>
            <span class="text-sm font-semibold ta-display">Teacher Assistant</span>
          </a>
          <.link navigate={~p"/sign-in"} class="btn btn-primary btn-sm ml-auto">
            <.icon name="hero-arrow-left-on-rectangle" class="size-4" />
            {gettext("Sign in")}
          </.link>
        </header>
        <main class="w-full flex-1">{render_slot(@inner_block)}</main>
      </div>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  attr :bell, :map, required: true

  defp notification_bell(assigns) do
    ~H"""
    <%!-- `!static`: the menu is placed against the rail header row, not the bell, so the rail (overflow hidden) never clips it. The drawer clips anything wider than the 16rem rail, so the menu is exactly rail-wide (max 100vw - 2rem) and its list scrolls. --%>
    <div id="notification-bell" class="dropdown dropdown-bottom !static">
      <div
        tabindex="0"
        role="button"
        aria-label={gettext("Notifications")}
        class="relative grid size-9 place-items-center rounded-lg text-[color:var(--ta-rail-muted)] transition-colors hover:bg-[color:var(--ta-rail-hover)] hover:text-[color:var(--ta-rail-fg)]"
      >
        <.icon name="hero-bell" class="size-5" />
        <span
          :if={@bell.unread > 0}
          id="notification-bell-count"
          class="badge badge-error badge-xs ta-num absolute -right-0.5 -top-0.5"
        >
          {@bell.unread}
        </span>
      </div>
      <div
        tabindex="0"
        class="dropdown-content left-0 right-0 z-50 mt-1 w-auto max-w-[calc(100vw-2rem)] rounded-box border border-base-300 bg-base-100 p-2 text-base-content shadow-lg"
      >
        <div class="flex flex-wrap items-center justify-between gap-x-2 gap-y-1 px-2 pb-2">
          <span class="ta-eyebrow">{gettext("Notifications")}</span>
          <button
            :if={@bell.unread > 0}
            id="bell-read-all"
            type="button"
            phx-click="notification:read_all"
            class="whitespace-nowrap text-xs font-semibold text-primary hover:underline"
          >
            {gettext("Tout marquer comme lu")}
          </button>
        </div>
        <p :if={@bell.latest == []} class="px-2 py-3 text-sm text-base-content/70">
          {gettext("Aucune notification.")}
        </p>
        <ul class="flex max-h-[60vh] flex-col gap-0.5 overflow-y-auto">
          <li :for={n <- @bell.latest}>
            <button
              type="button"
              id={"bell-item-#{n.id}"}
              phx-click="notification:open"
              phx-value-id={n.id}
              class={[
                "flex w-full items-start gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition-colors hover:bg-base-200"
              ]}
            >
              <span class={[
                "mt-1.5 size-2 shrink-0 rounded-full",
                if(is_nil(n.read_at), do: "bg-warning", else: "bg-transparent")
              ]}></span>
              <span class="min-w-0 flex-1">
                <span class={["block", is_nil(n.read_at) && "font-semibold"]}>
                  {NotificationText.title(n)}
                </span>
                <span
                  :if={NotificationText.detail(n)}
                  class="block text-xs font-normal text-base-content/70"
                >
                  {NotificationText.detail(n)}
                </span>
                <span class="ta-num block text-[0.7rem] font-normal text-base-content/70">
                  {NotificationText.when_text(n)}
                </span>
              </span>
            </button>
          </li>
        </ul>
        <.link
          id="bell-see-all"
          navigate={~p"/school/notifications"}
          class="mt-1 block rounded-lg px-2 py-1.5 text-center text-xs font-semibold text-primary transition-colors hover:bg-base-200"
        >
          {gettext("Tout voir")}
        </.link>
      </div>
    </div>
    """
  end

  attr :tabs, :map, required: true
  attr :current_path, :string, default: nil

  # The phone tab bar (<lg): four tabs of the role space, then « Plus », which
  # opens the sheet holding the rest of the menu and the account.
  defp tab_bar(assigns) do
    assigns =
      assign(
        assigns,
        :more_active?,
        Enum.any?(assigns.tabs.more, fn s ->
          Enum.any?(s.items, &rail_active?(assigns.current_path, &1.path))
        end)
      )
      |> assign(
        :more_badge?,
        Enum.any?(assigns.tabs.more, fn s -> Enum.any?(s.items, &((&1[:badge] || 0) > 0)) end)
      )

    ~H"""
    <nav id="tab-bar" class="ta-tabbar lg:hidden" aria-label={gettext("Navigation principale")}>
      <.link
        :for={tab <- @tabs.primary}
        id={"tab-#{tab.id}"}
        navigate={tab.path}
        aria-current={tab_active?(@current_path, tab) && "page"}
        class="ta-tab"
      >
        <span class="ta-tab__icon">
          <.icon name={tab.icon} class="size-5" />
          <span :if={(tab[:badge] || 0) > 0} class={["ta-tab__badge", tab_badge_class(tab)]}>
            {tab.badge}
          </span>
        </span>
        <span class="ta-tab__label">{tab.label}</span>
      </.link>
      <button
        id="tab-more"
        type="button"
        popovertarget="more-sheet"
        aria-current={@more_active? && "page"}
        class="ta-tab"
      >
        <span class="ta-tab__icon">
          <.icon name="hero-bars-3" class="size-5" />
          <span :if={@more_badge?} class="ta-tab__dot" aria-hidden="true"></span>
        </span>
        <span class="ta-tab__label">{gettext("Plus")}</span>
      </button>
    </nav>
    """
  end

  defp tab_active?(path, %{match: [_ | _] = prefixes}),
    do: path != nil and Enum.any?(prefixes, &String.starts_with?(path, &1))

  defp tab_active?(path, tab), do: rail_active?(path, tab.path)

  defp tab_badge_class(%{badge_tone: :error}), do: "bg-error text-error-content"
  defp tab_badge_class(_tab), do: "bg-warning text-warning-content"

  attr :more, :list, required: true
  attr :current_user, :map, required: true
  attr :user_initial, :string, default: nil
  attr :space, :map, required: true
  attr :space_keys, :list, default: []
  attr :workspaces, :list, default: []
  attr :workspace_id, :string, default: nil
  attr :current_path, :string, default: nil

  # The « Plus » sheet: a native popover (light-dismiss and Escape for free, and
  # it works on pages without a live connection). app.js closes it on navigation.
  defp more_sheet(assigns) do
    ~H"""
    <div id="more-sheet" popover class="ta-sheet" aria-label={gettext("Plus")}>
      <span class="ta-sheet__grip" aria-hidden="true"></span>

      <div class="flex items-center gap-3">
        <span class="grid size-11 flex-none place-items-center rounded-full bg-primary/20 font-semibold text-base-content">
          {@user_initial}
        </span>
        <span class="min-w-0 flex-1 leading-tight">
          <span class="block truncate font-semibold">{User.display_name(@current_user)}</span>
          <span :if={User.contact(@current_user)} class="ta-text-2 block truncate text-sm">
            {User.contact(@current_user)}
          </span>
        </span>
        <button
          type="button"
          popovertarget="more-sheet"
          popovertargetaction="hide"
          aria-label={gettext("Fermer")}
          class="grid size-11 flex-none place-items-center rounded-lg"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <div :if={length(@space_keys) > 1} class="flex flex-col gap-2">
        <span class="ta-eyebrow">{gettext("Espace")}</span>
        <div class="flex flex-wrap gap-2" role="navigation" aria-label={gettext("Espaces")}>
          <.link
            :for={key <- @space_keys}
            id={"sheet-space-#{key}"}
            href={~p"/school/space/#{key}"}
            aria-current={@space.key == key && "true"}
            class="ta-chip"
          >
            {Spaces.label(key)}
          </.link>
        </div>
      </div>

      <nav
        :if={@more != []}
        id="more-nav"
        class="grid grid-cols-3 gap-2"
        aria-label={gettext("Autres pages")}
      >
        <%= for section <- @more, item <- section.items do %>
          <.link
            id={"more-#{item.id}"}
            navigate={item.path}
            aria-current={rail_active?(@current_path, item.path) && "page"}
            class="ta-tile"
          >
            <span class="flex items-start justify-between gap-1">
              <.icon name={item.icon} class="size-5 text-primary" />
              <span
                :if={(item[:badge] || 0) > 0}
                class={["ta-tab__badge !static", tab_badge_class(item)]}
              >
                {item.badge}
              </span>
            </span>
            <span>{item.label}</span>
          </.link>
        <% end %>
      </nav>

      <div class="flex flex-col">
        <div class="ta-sheet__row">
          <.icon name="hero-moon" class="ta-text-2 size-5 flex-none" />
          <span class="flex-1">{gettext("Thème")}</span>
          <.theme_toggle id="theme-toggle-sheet" />
        </div>
        <div class="ta-sheet__row">
          <.icon name="hero-language" class="ta-text-2 size-5 flex-none" />
          <span class="flex-1">{gettext("Langue")}</span>
          <div class="ta-seg">
            <.link
              :for={{code, label} <- [{"fr", "FR"}, {"en", "EN"}]}
              href={~p"/locale/#{code}"}
              aria-current={Gettext.get_locale(TeacherAssistantWeb.Gettext) == code && "true"}
              class="ta-seg__btn"
            >
              {label}
            </.link>
          </div>
        </div>
        <.link
          :for={ws <- @workspaces}
          :if={length(@workspaces) > 1}
          href={~p"/workspaces/select/#{ws.id}"}
          aria-current={ws.id == @workspace_id && "true"}
          class="ta-sheet__row"
        >
          <.icon name="hero-building-library" class="ta-text-2 size-5 flex-none" />
          <span class="min-w-0 flex-1 truncate">{ws.name}</span>
          <.icon :if={ws.id == @workspace_id} name="hero-check" class="size-5 text-primary" />
        </.link>
        <.link navigate={~p"/account/password"} class="ta-sheet__row">
          <.icon name="hero-key" class="ta-text-2 size-5 flex-none" />
          <span class="flex-1">{gettext("Mot de passe")}</span>
          <.icon name="hero-chevron-right" class="ta-text-2 size-4" />
        </.link>
        <.link href={~p"/sign-out"} method="delete" class="ta-sheet__row !border-b-0 text-error">
          <.icon name="hero-arrow-right-on-rectangle" class="size-5 flex-none" />
          <span class="flex-1">{gettext("Sign out")}</span>
        </.link>
      </div>
    </div>
    """
  end

  # A page under an entry keeps it lit (a class under Classes, every settings page
  # under Paramètres). "/school" (the dashboard) only matches itself.
  @settings_pages ["/school/settings", "/school/periods", "/school/years"]

  defp rail_active?(nil, _href), do: false
  defp rail_active?(path, href) when path == href, do: true
  defp rail_active?(_path, "/school"), do: false

  defp rail_active?(path, "/school/settings"),
    do: Enum.any?(@settings_pages, &(path == &1 or String.starts_with?(path, &1 <> "/")))

  # The editor's sub-pages (« Disponibilités », « Mon emploi du temps ») have their own item.
  defp rail_active?(_path, "/school/timetable"), do: false

  defp rail_active?(path, href), do: String.starts_with?(path, href <> "/")

  attr :id, :string, default: nil
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, default: nil
  attr :badge, :integer, default: nil
  attr :badge_tone, :atom, default: :warning
  slot :inner_block, required: true

  defp rail_link(assigns) do
    assigns = assign(assigns, :active, rail_active?(assigns.current_path, assigns.href))

    ~H"""
    <.link id={@id} navigate={@href} aria-current={@active && "page"} class="ta-rail__item">
      <.icon name={@icon} class="size-[1.05rem] flex-none opacity-90" />
      <span class="flex-1">{render_slot(@inner_block)}</span>
      <span
        :if={@badge && @badge > 0}
        class={[
          "badge badge-sm ta-num",
          if(@badge_tone == :error, do: "badge-error", else: "badge-warning")
        ]}
      >
        {@badge}
      </span>
    </.link>
    """
  end

  defp workspace_name(%{current_workspace: %{name: name}}), do: name
  defp workspace_name(_), do: nil

  defp role_label(%{current_role: role}) when not is_nil(role),
    do: TeacherAssistant.Accounts.SchoolRole.label(role)

  defp role_label(_), do: nil

  defp workspace_type_label(_), do: gettext("School")

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  The reading-mode switch: the board (dark, the default) or craie (light). The
  current one is marked by CSS from `<html data-theme>`, which app.js sets
  before the page paints (see `setTheme`).
  """
  attr :id, :string, required: true

  def theme_toggle(assigns) do
    ~H"""
    <div id={@id} class="ta-seg" role="group" aria-label={gettext("Thème")}>
      <button
        type="button"
        class="ta-seg__btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        {gettext("Sombre")}
      </button>
      <button
        type="button"
        class="ta-seg__btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        {gettext("Craie")}
      </button>
    </div>
    """
  end

  # --- auth layout (paper) helpers -------------------------------------------
  #
  # `Layouts.auth` (layouts/auth.html.heex) wraps every AshAuthentication.Phoenix
  # page (sign-in, register, the "forgot password" request step, the token-based
  # "set a new password" step, and the magic-link landing page). Phoenix passes
  # the live view's full assigns through to the layout, so we can tell these
  # screens apart from assigns alone — no changes to the auth library needed:
  #
  #   * `@strategy` is only ever assigned by `MagicSignInLive`.
  #   * `@token` is assigned by `ResetLive` (the `/password-reset/:token` page)
  #     and by `MagicSignInLive` (checked second, after `@strategy`).
  #   * `@live_action` is `:register` / `:reset` / `:sign_in` on `SignInLive`
  #     (`:reset` there is the "request a reset link" step, not the token step).
  #   * `@auth_screen` is set by our own pages that borrow this shell
  #     (`Account.PasswordLive` → `:own_password`). Such a page renders its own
  #     column heading, so its copy has no title/foot, only the brand `panel`.

  defp auth_points do
    [
      gettext("L'appel en un geste, même sur téléphone"),
      gettext("Notes et bulletins pour toutes les classes"),
      gettext("La couverture du programme, toute l'année")
    ]
  end

  defp auth_screen(assigns) do
    cond do
      assigns[:auth_screen] -> assigns[:auth_screen]
      assigns[:strategy] -> :magic_sign_in
      assigns[:token] -> :reset_confirm
      assigns[:live_action] == :register -> :register
      assigns[:live_action] == :reset -> :reset_request
      true -> :sign_in
    end
  end

  defp auth_copy(assigns) do
    case auth_screen(assigns) do
      :own_password ->
        %{
          eyebrow: nil,
          title: nil,
          sub: nil,
          foot: nil,
          panel: %{
            eyebrow: gettext("Première connexion"),
            title: gettext("Un mot de passe rien qu'à vous."),
            text:
              gettext(
                "Le mot de passe temporaire ne sert qu'une fois. Ensuite, personne à l'établissement ne connaît le vôtre."
              )
          }
        }

      :register ->
        %{
          eyebrow: gettext("Créer un compte"),
          title: gettext("Commencez par votre compte"),
          sub:
            gettext(
              "Ce compte sera celui du responsable de l'établissement. Vous inviterez votre équipe juste après."
            ),
          foot:
            gettext(
              "Nous n'utilisons votre e-mail que pour l'accès au service et les notifications de votre établissement."
            )
        }

      :reset_request ->
        %{
          eyebrow: gettext("Mot de passe oublié"),
          title: gettext("Recevez un lien de réinitialisation"),
          sub: gettext("Nous envoyons un lien valable une heure à l'adresse de votre compte."),
          foot:
            gettext(
              "Si l'adresse n'existe pas, aucun message n'est envoyé — pour protéger les comptes de votre établissement."
            )
        }

      :reset_confirm ->
        %{
          eyebrow: gettext("Nouveau mot de passe"),
          title: gettext("Choisissez un nouveau mot de passe"),
          sub: gettext("Votre nouveau mot de passe doit contenir au moins 8 caractères."),
          foot: gettext("Ce lien de réinitialisation n'est valable qu'une seule fois.")
        }

      :magic_sign_in ->
        %{
          eyebrow: gettext("Connexion"),
          title: gettext("Connexion en cours"),
          sub: nil,
          foot: gettext("Vous allez être redirigé·e automatiquement.")
        }

      :sign_in ->
        %{
          eyebrow: gettext("Connexion"),
          title: gettext("Se connecter"),
          sub:
            gettext("Entrez le numéro de téléphone ou l'adresse fournis par votre établissement."),
          # the page renders its own footer line (« Inscrire mon établissement »)
          foot: nil
        }
    end
  end

  # School LiveViews get the list once per mount (`LiveUserAuth` :assign_capabilities);
  # only pages outside a school (onboarding, controller pages) read it here.
  defp workspaces(%{capabilities: %{workspaces: workspaces}}, _user), do: workspaces
  defp workspaces(_scope, nil), do: []

  defp workspaces(_scope, user),
    do: Organization.list_workspaces_for(%TeacherAssistant.Scope{current_user: user})
end
