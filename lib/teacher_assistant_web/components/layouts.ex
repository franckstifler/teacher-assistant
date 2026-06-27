defmodule TeacherAssistantWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TeacherAssistantWeb, :html

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

  slot :inner_block, required: true

  def app(assigns) do
    current_scope = assigns[:current_scope]
    current_user = current_scope && current_scope.current_user

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(:workspace_name, workspace_name(current_scope))
      |> assign(:role_label, role_label(current_scope))
      |> assign(:workspace_type_label, workspace_type_label(current_scope))

    ~H"""
    <div class="flex min-h-screen flex-col bg-base-200 text-base-content">
      <header class="sticky top-0 z-40 border-b border-base-300 bg-base-100/95 backdrop-blur">
        <div class="mx-auto flex min-h-16 w-full max-w-6xl items-center gap-4 px-4 sm:px-6">
          <a href="/" class="flex min-w-0 items-center gap-2.5">
            <span class="grid size-9 place-items-center rounded-lg bg-primary text-primary-content shadow-sm">
              <.icon name="hero-academic-cap" class="size-5" />
            </span>
            <span class="min-w-0 leading-tight">
              <span class="block text-sm font-semibold ta-display">Teacher Assistant</span>
              <span class="block truncate text-[0.7rem] text-base-content/55">
                {@workspace_name || gettext("Cameroon teacher workspace")}
              </span>
            </span>
          </a>

          <div class="ml-auto flex items-center gap-2">
            <Layouts.theme_toggle />
            <%= if @current_user do %>
              <div class="hidden text-right sm:block">
                <div class="text-xs font-semibold">{@current_user.email}</div>
                <div class="text-[0.7rem] uppercase tracking-wide text-base-content/50">
                  {@workspace_type_label} · {@role_label}
                </div>
              </div>
              <.link href={~p"/sign-out"} method="delete" class="btn btn-ghost btn-sm">
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
                <span class="hidden sm:inline">{gettext("Sign out")}</span>
              </.link>
            <% else %>
              <.link navigate={~p"/sign-in"} class="btn btn-primary btn-sm">
                <.icon name="hero-arrow-left-on-rectangle" class="size-4" />
                {gettext("Sign in")}
              </.link>
            <% end %>
          </div>
        </div>

        <nav
          :if={@current_user}
          id="main-nav"
          class="mx-auto flex w-full max-w-6xl items-center gap-1 px-3 pb-2 sm:px-5"
          aria-label={gettext("Main navigation")}
        >
          <.tab_link id="nav-dashboard" href={~p"/teacher"} icon="hero-squares-2x2">
            {gettext("Dashboard")}
          </.tab_link>
          <.tab_link id="nav-log" href={~p"/teacher/log"} icon="hero-pencil-square">
            {gettext("Log")}
          </.tab_link>
          <div id="locale-switch" class="ml-auto flex items-center gap-1">
            <.link navigate={~p"/locale/fr"} class="btn btn-ghost btn-xs ta-num">FR</.link>
            <span class="text-base-content/30">·</span>
            <.link navigate={~p"/locale/en"} class="btn btn-ghost btn-xs ta-num">EN</.link>
          </div>
        </nav>
      </header>

      <main class={[
        "flex-1",
        if(@current_user, do: "mx-auto w-full max-w-6xl px-4 py-6 sm:px-6", else: "w-full")
      ]}>
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :id, :string, default: nil
  attr :href, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp tab_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@href}
      class="group inline-flex items-center gap-2 rounded-md px-3 py-1.5 text-sm font-semibold text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
    >
      <.icon name={@icon} class="size-4 text-base-content/45 transition group-hover:text-primary" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp workspace_name(%{current_workspace: %{name: name}}), do: name
  defp workspace_name(%{current_user: %{} = _user}), do: gettext("Personal workspace")
  defp workspace_name(_), do: nil

  defp role_label(%{current_role: role}) when not is_nil(role) do
    role
    |> to_string()
    |> String.replace("_", " ")
  end

  defp role_label(_), do: nil

  defp workspace_type_label(%{current_workspace_type: :personal_teacher}), do: gettext("Personal")
  defp workspace_type_label(%{current_workspace_type: :school}), do: gettext("School")
  defp workspace_type_label(_), do: gettext("No workspace")

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
end
