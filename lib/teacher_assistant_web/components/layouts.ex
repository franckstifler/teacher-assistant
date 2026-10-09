defmodule TeacherAssistantWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TeacherAssistantWeb, :html
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Organization
  alias TeacherAssistantWeb.NotificationText

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

    units =
      case current_scope do
        %{current_workspace: %{}} ->
          TeacherAssistant.Curriculum.list_units_for_scope(current_scope)

        _ ->
          []
      end

    workspaces =
      if current_user,
        do: Organization.list_workspaces_for(%TeacherAssistant.Scope{current_user: current_user}),
        else: []

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(
        :user_initial,
        current_user &&
          String.upcase(String.slice(User.display_name(current_user), 0, 1))
      )
      |> assign(:workspace_name, workspace_name(current_scope))
      |> assign(:role_label, role_label(current_scope))
      |> assign(:workspace_type_label, workspace_type_label(current_scope))
      |> assign(:units, units)
      |> assign(:workspaces, workspaces)
      |> assign(:in_school?, current_scope && current_scope.current_workspace != nil)
      |> assign(:space, current_scope && current_scope.capabilities[:space])
      |> assign(:space_keys, (current_scope && current_scope.capabilities[:spaces]) || [])
      |> assign(:current_context, current_scope && current_scope.current_context)
      |> assign(:bell, current_scope && (current_scope.capabilities || %{})[:notifications])
      |> assign(:current_path, assigns[:current_path])

    ~H"""
    <%= if @current_user do %>
      <div class="drawer lg:drawer-open">
        <input id="app-drawer" type="checkbox" class="drawer-toggle" />

        <div class="drawer-content flex min-h-screen flex-col bg-base-200 text-base-content">
          <header class="sticky top-0 z-30 flex items-center gap-3 border-b border-base-300 bg-base-100/95 px-4 py-2.5 backdrop-blur lg:hidden">
            <label
              for="app-drawer"
              aria-label={gettext("Open navigation")}
              class="btn btn-ghost btn-sm btn-square"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
            <span class="grid size-8 place-items-center rounded-lg bg-primary text-primary-content ta-display text-sm font-bold">
              TA
            </span>
            <span class="min-w-0 truncate text-sm font-semibold ta-display">
              {@workspace_name || gettext("Teacher Assistant")}
            </span>
            <.link
              :if={@bell}
              id="notification-bell-mobile"
              navigate={~p"/school/notifications"}
              aria-label={gettext("Notifications")}
              class="btn btn-ghost btn-sm btn-square relative ml-auto"
            >
              <.icon name="hero-bell" class="size-5" />
              <span
                :if={@bell.unread > 0}
                class="badge badge-error badge-xs ta-num absolute -right-1 -top-1"
              >
                {@bell.unread}
              </span>
            </.link>
          </header>

          <main class="mx-auto w-full max-w-6xl flex-1 px-4 py-6 sm:px-6">
            {render_slot(@inner_block)}
          </main>
        </div>

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
                    <span class="ta-num block truncate text-[0.6rem] uppercase tracking-widest text-[color:var(--ta-rail-faint)]">
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

            <div :if={@units != []} id="class-switcher" class="dropdown w-full">
              <div
                tabindex="0"
                role="button"
                class="flex w-full items-center gap-2 rounded-lg border border-[color:var(--ta-rail-line)] px-2.5 py-2 text-sm font-semibold"
              >
                <.icon name="hero-users" class="size-4 flex-none text-primary" />
                <span class="min-w-0 flex-1 truncate text-left">
                  {context_label(@current_context)}
                </span>
                <.icon
                  name="hero-chevron-down"
                  class="size-3.5 flex-none text-[color:var(--ta-rail-faint)]"
                />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu z-50 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 text-base-content shadow"
              >
                <li
                  :for={u <- @units}
                  id={"class-switcher-item-#{TeacherAssistant.Curriculum.unit_select_id(@current_scope, u)}"}
                >
                  <.link href={
                    ~p"/teacher/select-context/#{TeacherAssistant.Curriculum.unit_select_id(@current_scope, u)}?return_to=#{@current_path || "/school"}"
                  }>
                    {TeacherAssistant.Curriculum.unit_label(u)}
                  </.link>
                </li>
              </ul>
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
                  "btn btn-xs rounded-full",
                  if(@space && @space.key == key, do: "btn-primary", else: "btn-ghost")
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
              :if={@current_context}
              id="per-class-nav"
              class="flex flex-col gap-0.5"
              aria-label={gettext("Class navigation")}
            >
              <p class="ta-rail__label truncate px-1.5 pb-1">{context_label(@current_context)}</p>
              <.rail_link
                id="nav-roster"
                href={~p"/teacher/contexts/#{@current_context.id}/roster"}
                icon="hero-user-group"
                current_path={@current_path}
              >
                {gettext("Roster")}
              </.rail_link>
              <.rail_link
                id="nav-marks"
                href={~p"/teacher/contexts/#{@current_context.id}/marks"}
                icon="hero-pencil-square"
                current_path={@current_path}
              >
                {gettext("Marks")}
              </.rail_link>
              <.rail_link
                id="nav-results"
                href={~p"/teacher/contexts/#{@current_context.id}/marks/summary"}
                icon="hero-trophy"
                current_path={@current_path}
              >
                {gettext("Results")}
              </.rail_link>
            </nav>

            <div class="mt-auto flex flex-col gap-2 border-t border-[color:var(--ta-rail-line)] pt-3">
              <div class="flex items-center gap-2.5 px-1.5">
                <span class="grid size-8 flex-none place-items-center rounded-full bg-[color:var(--ta-rail-hover)] ta-num text-xs font-semibold uppercase">
                  {@user_initial}
                </span>
                <span class="min-w-0 flex-1 leading-tight">
                  <span class="block truncate text-xs font-semibold">{User.display_name(@current_user)}</span>
                  <span class="ta-num block truncate text-[0.6rem] uppercase tracking-wide text-[color:var(--ta-rail-muted)]">
                    {@workspace_type_label}{if @role_label, do: " · #{@role_label}"}
                  </span>
                </span>
              </div>
              <div class="flex items-center gap-1">
                <.link href={~p"/sign-out"} method="delete" class="ta-rail__item flex-1">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4 flex-none" />
                  <span class="flex-1">{gettext("Sign out")}</span>
                </.link>
                <div id="locale-switch" class="flex items-center gap-0.5">
                  <.link
                    navigate={~p"/locale/fr"}
                    class="ta-num rounded px-2 py-1 text-xs font-semibold text-[color:var(--ta-rail-muted)] hover:text-[color:var(--ta-rail-fg)]"
                  >
                    FR
                  </.link>
                  <span class="text-[color:var(--ta-rail-faint)]">·</span>
                  <.link
                    navigate={~p"/locale/en"}
                    class="ta-num rounded px-2 py-1 text-xs font-semibold text-[color:var(--ta-rail-muted)] hover:text-[color:var(--ta-rail-fg)]"
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
        <p :if={@bell.latest == []} class="px-2 py-3 text-sm text-base-content/60">
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

  attr :id, :string, default: nil
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, default: nil
  attr :badge, :integer, default: nil
  attr :badge_tone, :atom, default: :warning
  slot :inner_block, required: true

  defp rail_link(assigns) do
    assigns = assign(assigns, :active, assigns.current_path == assigns.href)

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

  defp context_label(%{subject: subject, class_group: %{label: label}}) when is_binary(label),
    do: "#{subject} — #{label}"

  defp context_label(%{level: level, subject: subject}), do: "#{level} · #{subject}"
  defp context_label(_), do: Gettext.gettext(TeacherAssistantWeb.Gettext, "Select a class")

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
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-md border border-base-300 bg-base-200">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
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

  @auth_points [
    "L'appel en un geste, même sur téléphone",
    "Notes et bulletins pour toutes les classes",
    "La couverture du programme, toute l'année"
  ]

  defp auth_points, do: @auth_points

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
          eyebrow: "Créer un compte",
          title: "Commencez par votre compte",
          sub:
            "Ce compte sera celui du responsable de l'établissement. Vous inviterez votre équipe juste après.",
          foot:
            "Nous n'utilisons votre e-mail que pour l'accès au service et les notifications de votre établissement."
        }

      :reset_request ->
        %{
          eyebrow: "Mot de passe oublié",
          title: "Recevez un lien de réinitialisation",
          sub: "Nous envoyons un lien valable une heure à l'adresse de votre compte.",
          foot:
            "Si l'adresse n'existe pas, aucun message n'est envoyé — pour protéger les comptes de votre établissement."
        }

      :reset_confirm ->
        %{
          eyebrow: "Nouveau mot de passe",
          title: "Choisissez un nouveau mot de passe",
          sub: "Votre nouveau mot de passe doit contenir au moins 8 caractères.",
          foot: "Ce lien de réinitialisation n'est valable qu'une seule fois."
        }

      :magic_sign_in ->
        %{
          eyebrow: "Connexion",
          title: "Connexion en cours",
          sub: nil,
          foot: "Vous allez être redirigé·e automatiquement."
        }

      :sign_in ->
        %{
          eyebrow: "Connexion",
          title: "Se connecter",
          sub: "Entrez le numéro de téléphone ou l'adresse fournis par votre établissement.",
          # the page renders its own footer line (« Inscrire mon établissement »)
          foot: nil
        }
    end
  end
end
