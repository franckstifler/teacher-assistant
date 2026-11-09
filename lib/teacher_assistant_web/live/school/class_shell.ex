defmodule TeacherAssistantWeb.School.ClassShell do
  @moduledoc """
  The class page's frame (spec 2026-10-08 §3; UX refonte batch 5): « ← Classes » and
  the previous / next class, the header (class, « niveau · sous-système · N élèves
  (f filles, g garçons) · r redoublants ») and the tab bar shared by the class's
  pages, with counts (« Élèves · 14 », « Enseignements · 11/13 »). Each tab is its
  own LiveView; `allowed?/3` is the single access rule both the tab bar and each
  page's `mount/3` use. « Vue d'ensemble » is the class's root URL.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.{Curriculum, Discipline, Enrollment, Fees, ReportCards}
  alias TeacherAssistant.Academics.{ClassGroup, SchoolTemplates}
  alias TeacherAssistant.Accounts.User

  @tabs [:overview, :students, :teachings, :timetable, :register, :discipline, :results, :fees]

  @doc "Whether the scope may open the class's `tab`."
  def allowed?(scope, %ClassGroup{} = cg, tab)
      when tab in [:overview, :students, :teachings, :timetable],
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
  def tab_url(%ClassGroup{id: id}, :overview), do: ~p"/school/classes/#{id}"
  def tab_url(%ClassGroup{id: id}, :students), do: ~p"/school/classes/#{id}/students"
  def tab_url(%ClassGroup{id: id}, :teachings), do: ~p"/school/classes/#{id}/teachings"
  def tab_url(%ClassGroup{id: id}, :timetable), do: ~p"/school/classes/#{id}/timetable"
  def tab_url(%ClassGroup{id: id}, :register), do: ~p"/school/classes/#{id}/register"
  def tab_url(%ClassGroup{id: id}, :discipline), do: ~p"/school/classes/#{id}/discipline"
  def tab_url(%ClassGroup{id: id}, :results), do: ~p"/school/classes/#{id}/results"
  def tab_url(%ClassGroup{id: id}, :fees), do: ~p"/school/classes/#{id}/fees"

  @doc """
  Everything the header and tab bar show, loaded once per page mount (and
  again after a roster or assignment change). A page that has already read
  the class's roster (`roster:`, rows of `Enrollment.list_roster/2`) or its
  assignments (`assigned:` count and `unassigned:` subjects) passes them in
  `known`, so the shell does not read them again.
  """
  def load(scope, %ClassGroup{} = cg, known \\ []) do
    tabs = visible_tabs(scope, cg)
    roster = Keyword.get_lazy(known, :roster, fn -> Enrollment.list_roster(scope, cg) end)
    count = length(roster)

    {assigned, unassigned} =
      cond do
        :teachings not in tabs ->
          {0, []}

        Keyword.has_key?(known, :unassigned) and Keyword.has_key?(known, :assigned) ->
          {known[:assigned], known[:unassigned]}

        true ->
          status = Curriculum.assignment_status_by_class(scope, [cg])[cg.id]
          {status.assigned, status.unassigned}
      end

    %{
      tabs: Enum.map(tabs, &{&1, tab_url(cg, &1)}),
      capacity: Enrollment.capacity(scope, cg, count),
      girls: Enum.count(roster, &(&1.student.sex == :f)),
      boys: Enum.count(roster, &(&1.student.sex == :m)),
      repeaters: Enum.count(roster, & &1.enrollment.repeater),
      form_master: Enrollment.form_master(scope, cg),
      assigned: assigned,
      unassigned: length(unassigned),
      unassigned_subjects: unassigned,
      neighbours: neighbours(scope, cg)
    }
  end

  # The previous and next classes of the year in the class list's order, each with
  # the tabs the scope may open there (nil when none, or for a past year's class).
  defp neighbours(%{current_academic_year: %{id: year_id} = year} = scope, %ClassGroup{} = cg)
       when year_id == cg.academic_year_id do
    sorted =
      scope
      |> Enrollment.list_class_groups(year)
      |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)

    case Enum.find_index(sorted, &(&1.id == cg.id)) do
      nil ->
        %{prev: nil, next: nil}

      index ->
        %{
          prev: if(index > 0, do: neighbour(scope, Enum.at(sorted, index - 1))),
          next: neighbour(scope, Enum.at(sorted, index + 1))
        }
    end
  end

  defp neighbours(_scope, _cg), do: %{prev: nil, next: nil}

  defp neighbour(_scope, nil), do: nil

  defp neighbour(scope, cg) do
    case visible_tabs(scope, cg) do
      [] -> nil
      tabs -> %{cg: cg, tabs: tabs}
    end
  end

  # The neighbour's same tab, else its first one.
  defp neighbour_url(%{cg: cg, tabs: tabs}, tab),
    do: tab_url(cg, if(tab in tabs, do: tab, else: hd(tabs)))

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
    ~H"""
    <section id="class-shell" class="space-y-5">
      <div class="flex flex-wrap items-center gap-2">
        <.link
          :if={@trail == []}
          id="class-back"
          navigate={~p"/school/classes"}
          class="inline-flex min-h-9 items-center gap-1.5 text-sm font-medium text-primary hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-4" /> {gettext("Classes")}
        </.link>
        <.breadcrumb :if={@trail != []}>
          <:crumb navigate={~p"/school/classes"}>{gettext("Classes")}</:crumb>
          <:crumb navigate={tab_url(@cg, @tab)}>{@cg.label}</:crumb>
          <:crumb :for={label <- @trail}>{label}</:crumb>
        </.breadcrumb>
        <span class="flex-1"></span>
        <.link
          :if={@shell.neighbours.prev}
          id="class-prev"
          navigate={neighbour_url(@shell.neighbours.prev, @tab)}
          class="btn btn-ghost btn-sm text-base-content/75"
          aria-label={gettext("Classe précédente : %{label}", label: @shell.neighbours.prev.cg.label)}
        >
          <.icon name="hero-chevron-left" class="size-4" />{@shell.neighbours.prev.cg.label}
        </.link>
        <.link
          :if={@shell.neighbours.next}
          id="class-next"
          navigate={neighbour_url(@shell.neighbours.next, @tab)}
          class="btn btn-ghost btn-sm text-base-content/75"
          aria-label={gettext("Classe suivante : %{label}", label: @shell.neighbours.next.cg.label)}
        >
          {@shell.neighbours.next.cg.label}<.icon name="hero-chevron-right" class="size-4" />
        </.link>
      </div>

      <header class="flex flex-wrap items-end justify-between gap-4">
        <div class="min-w-0 space-y-1.5">
          <h1 class="font-display text-3xl font-semibold leading-none sm:text-[2.2rem]">
            {@cg.label}
          </h1>
          <p id="class-summary" class="text-[0.95rem] text-base-content/75">
            <span id="class-cycle">{level_line(@cg)}</span>
            ·
            <span
              id="class-size"
              class={["ta-num", @shell.capacity.over? && "font-semibold text-warning"]}
            >{capacity_text(@shell.capacity)}</span>
            <span :if={@shell.capacity.count > 0} class="ta-num">({sex_split(@shell)})</span>
            <span :if={@shell.repeaters > 0} class="ta-num">
              · {ngettext("%{count} redoublant", "%{count} redoublants", @shell.repeaters)}
            </span>
            <span :if={@shell.form_master} id="class-form-master">
              · {gettext("PP : %{name}", name: User.display_name(@shell.form_master))}
            </span>
          </p>
        </div>
        <%!-- At the right, also on phones and when the header wraps: a menu opens
             leftwards from its button's right edge, so it then fits on the screen. --%>
        <div
          :if={@actions != []}
          id="class-actions"
          class="ml-auto flex w-full flex-wrap items-center justify-end gap-2 sm:w-auto"
        >
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
                "-mb-px inline-flex items-center gap-1.5 border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors",
                if(tab == @tab,
                  do: "border-primary text-base-content",
                  else: "border-transparent text-base-content/70 hover:text-base-content"
                )
              ]}
            >
              {tab_label(tab)}
              <span :if={tab == :students} class="ta-num font-normal text-base-content/70">
                · {@shell.capacity.count}
              </span>
              <span
                :if={tab == :teachings}
                class={[
                  "ta-num font-normal",
                  if(@shell.unassigned > 0, do: "text-error", else: "text-base-content/70")
                ]}
                title={
                  @shell.unassigned > 0 &&
                    ngettext(
                      "%{count} matière sans enseignant",
                      "%{count} matières sans enseignant",
                      @shell.unassigned
                    )
                }
              >
                · {@shell.assigned}/{@shell.assigned + @shell.unassigned}
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
  def tab_label(:overview), do: gettext("Vue d'ensemble")
  def tab_label(:students), do: gettext("Élèves")
  def tab_label(:teachings), do: gettext("Enseignements")
  def tab_label(:timetable), do: gettext("Emploi du temps")
  def tab_label(:register), do: gettext("Cahier d'appel")
  def tab_label(:discipline), do: gettext("Discipline")
  def tab_label(:results), do: gettext("Résultats")
  def tab_label(:fees), do: gettext("Frais")

  @doc "« Francophone · 1er cycle »."
  def subsystem_cycle(%ClassGroup{subsystem: subsystem, level: level}) do
    sub = if subsystem == :anglophone, do: gettext("Anglophone"), else: gettext("Francophone")

    case SchoolTemplates.cycle(level, subsystem) do
      :first -> "#{sub} · #{gettext("1er cycle")}"
      :second -> "#{sub} · #{gettext("2nd cycle")}"
      _ -> sub
    end
  end

  # « 6ème · Francophone · 1er cycle »
  defp level_line(%ClassGroup{level: level} = cg) when is_binary(level) and level != "",
    do: "#{level} · #{subsystem_cycle(cg)}"

  defp level_line(cg), do: subsystem_cycle(cg)

  # « 13 filles, 1 garçon »
  defp sex_split(%{girls: girls, boys: boys}),
    do:
      Enum.join(
        [
          ngettext("%{count} fille", "%{count} filles", girls),
          ngettext("%{count} garçon", "%{count} garçons", boys)
        ],
        ", "
      )

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
