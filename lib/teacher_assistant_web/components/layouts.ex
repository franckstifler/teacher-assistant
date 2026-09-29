defmodule TeacherAssistantWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TeacherAssistantWeb, :html
  alias TeacherAssistant.Organization

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

    space_info =
      case current_scope do
        %{current_workspace: %{}, capabilities: %{space: space, spaces: keys}} ->
          {space, keys}

        %{current_workspace: %{}} ->
          facts = TeacherAssistantWeb.Spaces.facts(current_scope)
          keys = TeacherAssistantWeb.Spaces.keys_for(facts)
          {TeacherAssistantWeb.Spaces.space(hd(keys), facts), keys}

        _ ->
          {nil, []}
      end

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
        current_user && String.upcase(String.slice(to_string(current_user.email), 0, 1))
      )
      |> assign(:workspace_name, workspace_name(current_scope))
      |> assign(:role_label, role_label(current_scope))
      |> assign(:workspace_type_label, workspace_type_label(current_scope))
      |> assign(:units, units)
      |> assign(:workspaces, workspaces)
      |> assign(:in_school?, current_scope && current_scope.current_workspace != nil)
      |> assign(:space, elem(space_info, 0))
      |> assign(:space_keys, elem(space_info, 1))
      |> assign(:current_context, current_scope && current_scope.current_context)
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
            <div id="workspace-switcher" class="dropdown w-full">
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
                  <span class="block truncate text-xs font-semibold">{@current_user.email}</span>
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

  attr :id, :string, default: nil
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, default: nil
  slot :inner_block, required: true

  defp rail_link(assigns) do
    assigns = assign(assigns, :active, assigns.current_path == assigns.href)

    ~H"""
    <.link id={@id} navigate={@href} aria-current={@active && "page"} class="ta-rail__item">
      <.icon name={@icon} class="size-[1.05rem] flex-none opacity-90" />
      <span class="flex-1">{render_slot(@inner_block)}</span>
    </.link>
    """
  end

  defp context_label(%{subject: subject, class_group: %{label: label}}) when is_binary(label),
    do: "#{subject} — #{label}"

  defp context_label(%{level: level, subject: subject}), do: "#{level} · #{subject}"
  defp context_label(_), do: Gettext.gettext(TeacherAssistantWeb.Gettext, "Select a class")

  defp workspace_name(%{current_workspace: %{name: name}}), do: name
  defp workspace_name(_), do: nil

  defp role_label(%{current_role: role}) when not is_nil(role) do
    role
    |> to_string()
    |> String.replace("_", " ")
  end

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

  @auth_points [
    "L'appel en un geste, même sur téléphone",
    "Notes et bulletins pour toutes les classes",
    "La couverture du programme, toute l'année"
  ]

  defp auth_points, do: @auth_points

  defp auth_screen(assigns) do
    cond do
      assigns[:strategy] -> :magic_sign_in
      assigns[:token] -> :reset_confirm
      assigns[:live_action] == :register -> :register
      assigns[:live_action] == :reset -> :reset_request
      true -> :sign_in
    end
  end

  defp auth_copy(assigns) do
    case auth_screen(assigns) do
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
          title: "Content de vous revoir",
          sub: "Entrez l'adresse fournie par votre établissement.",
          foot:
            "Une invitation reçue par e-mail vous rattache automatiquement à votre établissement et à votre rôle."
        }
    end
  end
end
