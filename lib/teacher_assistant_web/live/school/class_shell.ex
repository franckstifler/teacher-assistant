defmodule TeacherAssistantWeb.School.ClassShell do
  @moduledoc """
  The class page's frame (spec 2026-10-08 §3): breadcrumb, header and the tab
  bar shared by the class's pages. Each tab is its own LiveView; `allowed?/3`
  is the single access rule both the tab bar and each page's `mount/3` use.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.{Curriculum, Discipline, Enrollment, Fees, ReportCards}
  alias TeacherAssistant.Academics.{ClassGroup, SchoolTemplates}
  alias TeacherAssistant.Accounts.User

  @tabs [:students, :teachings, :timetable, :register, :discipline, :results, :fees]

  @doc "Whether the scope may open the class's `tab`."
  def allowed?(scope, %ClassGroup{} = cg, tab) when tab in [:students, :teachings, :timetable],
    do: Enrollment.class_manager?(scope, cg)

  def allowed?(scope, %ClassGroup{} = cg, tab) when tab in [:register, :discipline],
    do: Discipline.can_manage_conduct?(scope) or Enrollment.class_manager?(scope, cg)

  def allowed?(scope, %ClassGroup{} = cg, :results), do: ReportCards.access(scope, cg) != :none

  def allowed?(scope, %ClassGroup{} = cg, :fees),
    do: Fees.can_manage_fees?(scope) or Enrollment.class_manager?(scope, cg)

  @doc "The class's tabs the scope may open, in display order."
  def visible_tabs(scope, %ClassGroup{} = cg) do
    Enum.filter(@tabs, fn tab ->
      allowed?(scope, cg, tab) and
        TeacherAssistantWeb.Spaces.path_allowed?(scope, tab_url(cg, tab))
    end)
  end

  @doc "Where a tab lives."
  def tab_url(%ClassGroup{id: id}, :students), do: ~p"/school/classes/#{id}"
  def tab_url(%ClassGroup{id: id}, :teachings), do: ~p"/school/classes/#{id}/teachings"
  def tab_url(%ClassGroup{id: id}, :timetable), do: ~p"/school/classes/#{id}/timetable"
  def tab_url(%ClassGroup{id: id}, :register), do: ~p"/school/classes/#{id}/register"
  def tab_url(%ClassGroup{id: id}, :discipline), do: ~p"/school/classes/#{id}/discipline"
  def tab_url(%ClassGroup{id: id}, :results), do: ~p"/school/classes/#{id}/results"
  def tab_url(%ClassGroup{id: id}, :fees), do: ~p"/school/classes/#{id}/fees"

  @doc """
  Everything the header and tab bar show, loaded once per page mount (and
  again after a roster or assignment change). A page that has already read
  the class's headcount (`count:`) or unassigned subjects (`unassigned:`)
  passes them in `known`, so the shell does not read them again.
  """
  def load(scope, %ClassGroup{} = cg, known \\ []) do
    tabs = visible_tabs(scope, cg)

    count =
      Keyword.get_lazy(known, :count, fn -> length(Enrollment.list_roster(scope, cg)) end)

    unassigned =
      cond do
        :teachings not in tabs -> 0
        Keyword.has_key?(known, :unassigned) -> length(known[:unassigned])
        true -> length(Curriculum.unassigned_subjects_by_class(scope, [cg])[cg.id])
      end

    %{
      tabs: Enum.map(tabs, &{&1, tab_url(cg, &1)}),
      capacity: Enrollment.capacity(scope, cg, count),
      form_master: Enrollment.form_master(scope, cg),
      unassigned: unassigned
    }
  end

  @doc "Assigns `:shell` on the socket (see `load/3` for `known`)."
  def assign_shell(socket, known \\ []),
    do:
      Phoenix.Component.assign(
        socket,
        :shell,
        load(socket.assigns.current_scope, socket.assigns.cg, known)
      )

  attr :cg, ClassGroup, required: true
  attr :shell, :map, required: true
  attr :tab, :atom, required: true, values: @tabs

  attr :trail, :list,
    default: [],
    doc:
      "a sub-page's own crumbs after the class's (« Contrôle des frais »); the class's crumb then leads back to the tab"

  slot :actions
  slot :inner_block, required: true

  def class_shell(assigns) do
    assigns =
      assign(
        assigns,
        :chip,
        "inline-flex items-center rounded-[0.4rem] border border-base-300 bg-base-100 px-2.5 py-1"
      )

    ~H"""
    <section id="class-shell" class="space-y-5">
      <.breadcrumb>
        <:crumb navigate={~p"/school/classes"}>{gettext("Classes")}</:crumb>
        <:crumb navigate={@trail != [] && tab_url(@cg, @tab)}>{@cg.label}</:crumb>
        <:crumb :for={label <- @trail}>{label}</:crumb>
      </.breadcrumb>

      <header class="flex flex-wrap items-end justify-between gap-4">
        <div class="min-w-0 space-y-2">
          <h1 class="font-display text-3xl font-semibold leading-none sm:text-[2.2rem]">
            {@cg.label}
          </h1>
          <div class="flex flex-wrap gap-2 text-xs">
            <span id="class-cycle" class={@chip}>{subsystem_cycle(@cg)}</span>
            <span id="class-form-master" class={@chip}>
              {gettext("PP : %{name}",
                name:
                  if(@shell.form_master,
                    do: User.display_name(@shell.form_master),
                    else: gettext("à désigner")
                  )
              )}
            </span>
            <span
              id="class-size"
              class={[@chip, "ta-num", @shell.capacity.over? && "border-warning/60 text-warning"]}
            >
              {capacity_text(@shell.capacity)}
            </span>
          </div>
        </div>
        <%!-- Full width on phones, so a trailing « ⋯ » sits at the right edge and its menu fits. --%>
        <div :if={@actions != []} class="flex w-full flex-wrap items-center gap-2 sm:w-auto">
          {render_slot(@actions)}
        </div>
      </header>

      <nav
        id="class-tabs"
        aria-label={gettext("Sections de la classe")}
        phx-hook="ScrollActiveTab"
        class="-mx-1 overflow-x-auto border-b border-base-300"
      >
        <ul class="flex min-w-max gap-1 px-1">
          <li :for={{tab, path} <- @shell.tabs}>
            <.link
              navigate={path}
              id={"class-tab-#{tab}"}
              aria-current={tab == @tab && "page"}
              class={[
                "-mb-px inline-flex items-center gap-2 border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors",
                if(tab == @tab,
                  do: "border-primary text-base-content",
                  else: "border-transparent text-base-content/70 hover:text-base-content"
                )
              ]}
            >
              {tab_label(tab)}
              <span
                :if={tab == :students}
                class="ta-num rounded-full bg-base-300 px-1.5 text-[0.7rem] text-base-content/70"
              >
                {@shell.capacity.count}
              </span>
              <span
                :if={tab == :teachings and @shell.unassigned > 0}
                class="ta-num rounded-full bg-error/20 px-1.5 text-[0.7rem] text-error"
              >
                {@shell.unassigned}
              </span>
            </.link>
          </li>
        </ul>
      </nav>

      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  The browser tab title of a class page: the class first, then the tab's
  label (« 4e B · Élèves ») or a sub-page's own label.
  """
  def page_title(%ClassGroup{} = cg, tab) when tab in @tabs, do: page_title(cg, tab_label(tab))

  def page_title(%ClassGroup{label: label}, name) when is_binary(name), do: "#{label} · #{name}"

  @doc "A tab's label in the tab bar."
  def tab_label(:students), do: gettext("Élèves")
  def tab_label(:teachings), do: gettext("Enseignements")
  def tab_label(:timetable), do: gettext("Emploi du temps")
  def tab_label(:register), do: gettext("Cahier d'appel")
  def tab_label(:discipline), do: gettext("Discipline")
  def tab_label(:results), do: gettext("Résultats")
  def tab_label(:fees), do: gettext("Frais")

  @doc "Spec 2026-10-31 §1: the class list to print, official roster or working list."
  attr :cg, ClassGroup, required: true
  attr :button_class, :string, default: "btn btn-ghost btn-sm", doc: "matches the page's buttons"

  def class_list_menu(assigns) do
    ~H"""
    <details id="class-list-menu" class="dropdown dropdown-end">
      <summary class={@button_class}>
        <.icon name="hero-printer" class="size-4" /> {gettext("Liste de classe")} ▾
      </summary>
      <ul class="menu dropdown-content z-30 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 shadow-lg">
        <li>
          <a
            id="class-list-roster"
            href={~p"/school/classes/#{@cg.id}/class-list/print"}
            target="_blank"
          >
            {gettext("Liste officielle")}
          </a>
        </li>
        <li>
          <a
            id="class-list-working"
            href={~p"/school/classes/#{@cg.id}/class-list/working/print"}
            target="_blank"
          >
            {gettext("Liste de travail")}
          </a>
        </li>
      </ul>
    </details>
    """
  end

  @doc "« Francophone · 1er cycle »."
  def subsystem_cycle(%ClassGroup{subsystem: subsystem, level: level}) do
    sub = if subsystem == :anglophone, do: gettext("Anglophone"), else: gettext("Francophone")

    case SchoolTemplates.cycle(level, subsystem) do
      :first -> "#{sub} · #{gettext("1er cycle")}"
      :second -> "#{sub} · #{gettext("2nd cycle")}"
      _ -> sub
    end
  end

  defp capacity_text(%{count: count, max: nil}),
    do: ngettext("%{count} élève", "%{count} élèves", count)

  defp capacity_text(%{count: count, max: max, over?: true}),
    do:
      gettext("%{count} / %{max} élèves · %{extra} au-delà",
        count: count,
        max: max,
        extra: count - max
      )

  defp capacity_text(%{count: count, max: max}),
    do:
      gettext("%{count} / %{max} élèves · %{free} places",
        count: count,
        max: max,
        free: max - count
      )
end
