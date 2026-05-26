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
      |> assign(:school_name, school_name(current_scope))
      |> assign(:role_label, role_label(current_user))
      |> assign(
        :show_configuration_nav?,
        role_in?(current_scope, [:admin, :principal, :vice_principal])
      )
      |> assign(:show_access_nav?, role_in?(current_scope, [:admin, :accountant, :principal]))
      |> assign(
        :show_teacher_nav?,
        role_in?(current_scope, [:admin, :teacher, :principal_teacher])
      )
      |> assign(
        :show_reports_nav?,
        role_in?(current_scope, [:admin, :principal, :vice_principal])
      )

    ~H"""
    <div class="min-h-screen bg-base-200 text-base-content">
      <header class="sticky top-0 z-40 border-b border-base-300 bg-base-100">
        <div class="flex min-h-16 items-center gap-4 px-4 sm:px-6 lg:px-8">
          <a href="/" class="flex min-w-0 items-center gap-3">
            <span class="grid size-9 place-items-center rounded-md bg-primary text-primary-content shadow-sm">
              <.icon name="hero-academic-cap" class="size-5" />
            </span>
            <span class="min-w-0">
              <span class="block text-sm font-semibold leading-5">Teacher Assistant</span>
              <span class="block truncate text-xs text-base-content/55">
                {@school_name || gettext("Cameroon schools")}
              </span>
            </span>
          </a>

          <nav
            class="ml-auto hidden items-center gap-1 lg:flex"
            aria-label={gettext("Main navigation")}
          >
            <.top_nav_link
              :if={@show_teacher_nav?}
              href={~p"/teacher/marks"}
              icon="hero-pencil-square"
            >
              {gettext("Marks")}
            </.top_nav_link>
            <.top_nav_link
              :if={@show_teacher_nav?}
              href={~p"/teacher/attendance"}
              icon="hero-clipboard-document-check"
            >
              {gettext("Attendance")}
            </.top_nav_link>
            <.top_nav_link
              :if={@show_reports_nav?}
              href={~p"/reports/report_cards"}
              icon="hero-document-chart-bar"
            >
              {gettext("Reports")}
            </.top_nav_link>
            <.top_nav_link :if={!@current_user} href={~p"/"} icon="hero-squares-2x2">
              {gettext("Overview")}
            </.top_nav_link>
          </nav>

          <div class="ml-auto flex items-center gap-2 lg:ml-3">
            <Layouts.theme_toggle />
            <%= if @current_user do %>
              <div class="hidden text-right sm:block">
                <div class="text-xs font-semibold">{@current_user.email}</div>
                <div class="text-[0.7rem] uppercase tracking-wide text-base-content/50">
                  {@role_label}
                </div>
              </div>
              <.link href={~p"/sign-out"} method="delete" class="btn btn-ghost btn-sm">
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
                {gettext("Sign out")}
              </.link>
            <% else %>
              <.link navigate={~p"/sign-in"} class="btn btn-primary btn-sm">
                <.icon name="hero-arrow-left-on-rectangle" class="size-4" />
                {gettext("Sign in")}
              </.link>
            <% end %>
          </div>
        </div>
      </header>

      <div class={["mx-auto flex w-full", @current_user && "max-w-[1600px]"]}>
        <aside
          :if={@current_user}
          class="hidden min-h-[calc(100vh-4rem)] w-72 shrink-0 border-r border-base-300 bg-base-100 px-4 py-5 lg:block"
        >
          <nav class="space-y-6" aria-label={gettext("Workspace navigation")}>
            <div :if={@show_teacher_nav?} id="nav-teacher-tools" class="space-y-2">
              <div class="px-3 text-[0.7rem] font-semibold uppercase tracking-wide text-base-content/45">
                {gettext("Operate")}
              </div>
              <.side_nav_link href={~p"/teacher/marks"} icon="hero-clipboard-document-list">
                {gettext("Marks entry")}
              </.side_nav_link>
              <.side_nav_link href={~p"/teacher/attendance"} icon="hero-clipboard-document-check">
                {gettext("Attendance")}
              </.side_nav_link>
              <.side_nav_link href={~p"/teacher/progression"} icon="hero-calendar-days">
                {gettext("Progression")}
              </.side_nav_link>
            </div>

            <div :if={@show_reports_nav?} id="nav-reports" class="space-y-2">
              <div class="px-3 text-[0.7rem] font-semibold uppercase tracking-wide text-base-content/45">
                {gettext("Reports")}
              </div>
              <.side_nav_link href={~p"/reports/report_cards"} icon="hero-document-chart-bar">
                {gettext("Report cards")}
              </.side_nav_link>
              <.side_nav_link href={~p"/reports/programme_coverage"} icon="hero-chart-bar">
                {gettext("Programme coverage")}
              </.side_nav_link>
            </div>

            <div :if={@show_access_nav?} id="nav-student-access" class="space-y-2">
              <div class="px-3 text-[0.7rem] font-semibold uppercase tracking-wide text-base-content/45">
                {gettext("Access")}
              </div>
              <.side_nav_link href={~p"/configurations/student_access"} icon="hero-identification">
                {gettext("Classroom access")}
              </.side_nav_link>
            </div>

            <div :if={@show_configuration_nav?} id="nav-configuration" class="space-y-2">
              <div class="px-3 text-[0.7rem] font-semibold uppercase tracking-wide text-base-content/45">
                {gettext("Configuration")}
              </div>
              <.side_nav_link href={~p"/configurations/academic_years"} icon="hero-calendar">
                {gettext("Academic years")}
              </.side_nav_link>
              <.side_nav_link
                id="nav-grade-intervals"
                href={~p"/configurations/grade_intervals"}
                icon="hero-chart-pie"
              >
                {gettext("Grade intervals")}
              </.side_nav_link>
              <.side_nav_link href={~p"/configurations/students"} icon="hero-users">
                {gettext("Students")}
              </.side_nav_link>
              <.side_nav_link href={~p"/configurations/subjects"} icon="hero-book-open">
                {gettext("Subjects")}
              </.side_nav_link>
              <.side_nav_link href={~p"/configurations/levels_options"} icon="hero-rectangle-group">
                {gettext("Levels and options")}
              </.side_nav_link>
              <.side_nav_link href={~p"/configurations/levels"} icon="hero-bars-3-bottom-left">
                {gettext("Levels")}
              </.side_nav_link>
              <.side_nav_link href={~p"/configurations/options"} icon="hero-squares-2x2">
                {gettext("Options")}
              </.side_nav_link>
            </div>
          </nav>
        </aside>

        <main class={
          if(@current_user, do: "min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8", else: "w-full")
        }>
          <div class={if(@current_user, do: "mx-auto max-w-7xl space-y-6", else: "mx-auto w-full")}>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp top_nav_link(assigns) do
    ~H"""
    <.link navigate={@href} class="btn btn-ghost btn-sm gap-2">
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :id, :string, default: nil
  attr :href, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp side_nav_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@href}
      class="group flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-base-content/72 transition hover:bg-base-200 hover:text-base-content"
    >
      <.icon name={@icon} class="size-4 text-base-content/45 transition group-hover:text-primary" />
      <span>{render_slot(@inner_block)}</span>
    </.link>
    """
  end

  defp role_in?(%{current_user: %{role: role}}, roles), do: role in roles
  defp role_in?(_, _roles), do: false

  defp school_name(%{current_tenant: %{name: name}}), do: name
  defp school_name(_), do: nil

  defp role_label(%{role: role}) do
    role
    |> to_string()
    |> String.replace("_", " ")
  end

  defp role_label(_), do: nil

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
