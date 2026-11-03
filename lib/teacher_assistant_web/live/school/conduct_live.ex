defmodule TeacherAssistantWeb.School.ConductLive do
  @moduledoc """
  SG → Conduite (spec KLM3, V05; Vie scolaire redesign §2.3; UX refonte
  2026-11-03 « Conduite »): for a class (picked by level) and a séquence, the
  students with an incident as cards — what happened, the conduct mark the
  school's scale suggests (name click: the deductions, lates included), and an
  input pre-filled with the current mark (else the suggestion). The others
  (20/20) are folded into a footer but still posted. « Valider X et passer à Y »
  saves the class in one go and moves to the next one.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{EntryProgress, Reference, SanctionType, SchoolTemplates}
  alias TeacherAssistantWeb.{Authz, Dates}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Discipline.can_manage_conduct?(scope) do
      year = scope.current_academic_year

      {:ok,
       assign(socket,
         page_title: gettext("Conduite"),
         classes:
           scope
           |> Enrollment.list_class_groups(year, load: [:enrollment_count])
           |> Enum.sort_by(&SchoolTemplates.class_sort_key/1),
         sequences: Organization.list_sequences(scope, year),
         rules: Attendance.school_life_rules(scope),
         open: nil,
         only_incidents: true,
         error: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    cg =
      Enum.find(socket.assigns.classes, &(&1.id == params["class"])) ||
        List.first(socket.assigns.classes)

    seq =
      Enum.find(socket.assigns.sequences, &(&1.id == params["seq"])) ||
        EntryProgress.default_sequence(socket.assigns.sequences, Reference.today())

    {:noreply,
     socket
     |> assign(cg: cg, seq: seq, open: nil, error: nil, only_incidents: true)
     |> load()}
  end

  defp load(%{assigns: %{cg: cg, seq: seq}} = socket) when not is_nil(cg) and not is_nil(seq) do
    scope = socket.assigns.current_scope
    rows = Discipline.conduct_sheet(scope, cg, seq)
    values = Map.new(rows, &{&1.enrollment.id, shown(&1.current || &1.suggestion.mark)})

    assign(socket,
      rows: rows,
      values: values,
      validated: Discipline.validated_conduct_classes(scope, scope.current_academic_year, seq)
    )
  end

  defp load(socket), do: assign(socket, rows: [], values: %{}, validated: MapSet.new())

  # A row the page shows by default: something to look at (an absence, a late, a
  # sanction) or a mark already set away from the suggestion.
  defp flagged?(row),
    do:
      row.suggestion.deductions != [] or
        (row.current != nil and not Decimal.equal?(row.current, row.suggestion.mark))

  defp next_class(classes, %{id: id}) do
    classes |> Enum.drop_while(&(&1.id != id)) |> Enum.at(1)
  end

  defp next_class(_classes, nil), do: nil

  defp conduct_path(cg, seq),
    do: ~p"/school/conduct?#{[class: cg.id] ++ if(seq, do: [seq: seq.id], else: [])}"

  # A year without séquences (or classes) posts no value for that select.
  # The class picker posts the class alone; the séquence select, both.
  def handle_event("pick", params, socket) do
    %{cg: cg, seq: seq} = socket.assigns

    query =
      %{"class" => cg && cg.id, "seq" => seq && seq.id}
      |> Map.merge(Map.take(params, ["class", "seq"]))
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    {:noreply, push_patch(socket, to: ~p"/school/conduct?#{query}")}
  end

  def handle_event("edit", %{"marks" => marks}, socket),
    do: {:noreply, assign(socket, values: Map.merge(socket.assigns.values, marks))}

  def handle_event("apply", _params, socket) do
    values = Map.new(socket.assigns.rows, &{&1.enrollment.id, shown(&1.suggestion.mark)})
    {:noreply, assign(socket, values: values)}
  end

  def handle_event("toggle_incidents", _params, socket),
    do: {:noreply, assign(socket, only_incidents: not socket.assigns.only_incidents)}

  def handle_event("toggle", %{"id" => id}, socket),
    do: {:noreply, assign(socket, open: if(socket.assigns.open == id, do: nil, else: id))}

  def handle_event("validate", %{"marks" => marks}, socket) do
    %{current_scope: scope, cg: cg, seq: seq} = socket.assigns

    case Discipline.set_conduct_marks(scope, cg, seq, marks) do
      {:ok, count} ->
        socket =
          put_flash(
            socket,
            :info,
            ngettext(
              "%{count} note de conduite enregistrée",
              "%{count} notes de conduite enregistrées",
              count
            )
          )

        case next_class(socket.assigns.classes, cg) do
          nil -> {:noreply, socket |> load() |> assign(error: nil)}
          next -> {:noreply, push_patch(socket, to: conduct_path(next, seq))}
        end

      {:error, {:invalid_value, id}} ->
        name =
          Enum.find_value(socket.assigns.rows, &(&1.enrollment.id == id && &1.student.full_name))

        {:noreply,
         assign(socket,
           values: Map.merge(socket.assigns.values, marks),
           error: gettext("%{name} : une note entre 0 et 20.", name: name)
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, assign(socket, error: gettext("Notes de conduite non enregistrées."))}
    end
  end

  # Compared as numbers: « 17.5 », « 17,50 » and « 17,5 » are the same mark.
  defp adjusted?(row, values) do
    case Map.get(values, row.enrollment.id) do
      blank when blank in [nil, ""] ->
        false

      typed ->
        case typed
             |> to_string()
             |> String.trim()
             |> String.replace(",", ".")
             |> Decimal.parse() do
          {%Decimal{coef: coef} = d, ""} when is_integer(coef) ->
            not Decimal.equal?(d, row.suggestion.mark)

          _ ->
            true
        end
    end
  end

  defp shown(nil), do: ""

  defp shown(%Decimal{} = d),
    do: d |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp deduction_label(%{kind: :absences, count: hours}),
    do: gettext("%{hours} h non justifiées", hours: shown(Decimal.round(hours, 2)))

  defp deduction_label(%{kind: :retards, count: n}),
    do: ngettext("%{count} retard", "%{count} retards", n)

  defp deduction_label(%{kind: {:sanction, type}, count: n}),
    do: "#{n} × #{SanctionType.label(type)}"

  # « 4 h injustifiées · 1 retard · Avertissement le 21 oct. »
  defp incident_line(row) do
    hours = Decimal.round(row.unjustified_hours, 1)

    [
      Decimal.gt?(hours, 0) &&
        gettext("%{hours} h injustifiées", hours: shown(hours)),
      row.retards > 0 && ngettext("%{count} retard", "%{count} retards", row.retards)
      | Enum.map(
          row.sanctions,
          &gettext("%{sanction} le %{date}",
            sanction: SanctionType.label(&1.type),
            date: Dates.day_month(&1.date)
          )
        )
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp rule_text(rules) do
    gettext(
      "règle : 20 − %{per_hour} pt / h injustifiée − %{per_late} pt / retard − points par sanction",
      per_hour: shown(rules.points_per_absence_hour),
      per_late: shown(rules.points_per_late)
    )
  end

  def render(assigns) do
    {shown_rows, folded} =
      if assigns.only_incidents,
        do: Enum.split_with(assigns.rows, &flagged?/1),
        else: {assigns.rows, []}

    assigns =
      assign(assigns,
        shown_rows: shown_rows,
        folded: folded,
        incidents: Enum.count(assigns.rows, &flagged?/1),
        next: next_class(assigns.classes, assigns.cg)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="conduct" class="mx-auto flex w-full max-w-[920px] flex-col gap-4">
        <.page_header eyebrow={gettext("Vie scolaire")} title={gettext("Conduite")}>
          <:hint>
            <span id="conduct-subtitle" class="ta-num text-sm">
              <span :if={@seq}>{gettext("Séquence %{n}", n: @seq.number)} · </span>{ngettext(
                "%{count} classe validée sur %{total}",
                "%{count} classes validées sur %{total}",
                MapSet.size(@validated),
                total: length(@classes)
              )}
            </span>
          </:hint>
          <:actions :if={@rows != []}>
            <button
              type="button"
              id="apply-suggestions"
              phx-click="apply"
              class="btn btn-outline btn-sm"
            >
              {gettext("Appliquer les suggestions")}
            </button>
          </:actions>
        </.page_header>

        <div class="ta-section flex flex-wrap items-center gap-2 p-2.5">
          <.class_picker
            :if={@classes != []}
            id="conduct-class"
            classes={@classes}
            current={@cg && @cg.id}
            to={&conduct_path(&1, @seq)}
            change="pick"
            select_class="font-semibold"
            suffix={fn c -> ngettext("%{count} élève", "%{count} élèves", c.enrollment_count) end}
            class="min-w-0 flex-[1_1_16rem]"
          />
          <form id="conduct-pick" phx-change="pick" class="flex-none">
            <input :if={@cg} type="hidden" name="class" value={@cg.id} />
            <select name="seq" aria-label={gettext("Séquence")} class="select w-auto">
              <option :for={s <- @sequences} value={s.id} selected={@seq && s.id == @seq.id}>
                {gettext("Séquence %{n}", n: s.number)}
              </option>
            </select>
          </form>
          <span id="conduct-rule" class="basis-full px-1 text-xs text-base-content/70">
            {rule_text(@rules)} (<.link
              navigate={~p"/school/settings/school-life"}
              class="text-info hover:underline"
            >{gettext("Paramètres › Assiduité & discipline")}</.link>)
          </span>
        </div>

        <p :if={@rows == []} class="text-sm text-base-content/70">
          {gettext("Aucun élève dans cette classe.")}
        </p>

        <.form
          :if={@rows != []}
          for={%{}}
          id="conduct-form"
          phx-change="edit"
          phx-submit="validate"
          class="flex flex-col gap-3"
        >
          <section id="conduct-card" class="ta-section overflow-hidden">
            <header class="flex flex-wrap items-center gap-3 border-b border-base-300 px-4 py-3">
              <h2 class="min-w-0 flex-1 text-[0.95rem] font-semibold">
                {@cg.label} · {ngettext(
                  "%{count} élève avec incident",
                  "%{count} élèves avec incident",
                  @incidents
                )}
              </h2>
              <label class="flex cursor-pointer items-center gap-2 text-sm text-base-content/75">
                <input
                  id="only-incidents"
                  type="checkbox"
                  class="toggle toggle-sm toggle-primary"
                  checked={@only_incidents}
                  phx-click="toggle_incidents"
                />
                {gettext("Seulement les incidents")}
              </label>
            </header>

            <div
              :for={row <- @shown_rows}
              id={"conduct-row-#{row.enrollment.id}"}
              class="ta-row-rule px-4 py-3"
            >
              <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
                <span class="flex min-w-0 flex-1 basis-48 flex-col">
                  <button
                    type="button"
                    id={"conduct-name-#{row.enrollment.id}"}
                    phx-click="toggle"
                    phx-value-id={row.enrollment.id}
                    aria-expanded={to_string(@open == row.enrollment.id)}
                    class="w-fit text-left font-semibold hover:text-primary"
                  >
                    {row.student.full_name}
                  </button>
                  <span
                    :if={row.suggestion.deductions != []}
                    class="text-xs text-warning"
                  >
                    {incident_line(row)}
                  </span>
                  <span :if={row.suggestion.deductions == []} class="text-xs text-base-content/60">
                    {gettext("Aucun incident")}
                  </span>
                </span>
                <span class="flex items-center gap-1.5">
                  <span
                    :for={s <- row.sanctions}
                    class="badge badge-sm badge-ghost hidden sm:inline-flex"
                  >
                    {SanctionType.label(s.type)} −{shown(@rules.sanction_points[s.type])}
                  </span>
                </span>
                <span class="text-xs text-base-content/70">
                  {gettext("Suggestion")}
                  <span class="ta-num ml-1 text-sm font-semibold text-base-content">
                    {shown(row.suggestion.mark)}
                  </span>
                </span>
                <span class="ml-auto flex items-center gap-1.5">
                  <span :if={adjusted?(row, @values)} class="badge badge-warning badge-xs">
                    {gettext("ajustée")}
                  </span>
                  <input
                    id={"conduct-input-#{row.enrollment.id}"}
                    name={"marks[#{row.enrollment.id}]"}
                    value={@values[row.enrollment.id]}
                    inputmode="decimal"
                    aria-label={gettext("Note de conduite de %{name}", name: row.student.full_name)}
                    class="input ta-num w-20 text-center font-semibold"
                  />
                </span>
              </div>
              <p
                :if={@open == row.enrollment.id}
                id={"deductions-#{row.enrollment.id}"}
                class="mt-2 rounded-lg bg-base-200/60 px-3 py-2 text-xs"
              >
                <span :if={row.suggestion.deductions == []}>{gettext("Aucune déduction.")}</span>
                <span :for={d <- row.suggestion.deductions} class="mr-3">
                  {deduction_label(d)} : −{shown(Decimal.round(d.points, 2))}
                </span>
              </p>
            </div>

            <input
              :for={row <- @folded}
              type="hidden"
              id={"conduct-folded-#{row.enrollment.id}"}
              name={"marks[#{row.enrollment.id}]"}
              value={@values[row.enrollment.id]}
            />

            <div
              :if={@folded != []}
              id="conduct-folded"
              class="flex items-center gap-3 px-4 py-3 text-sm text-base-content/70"
            >
              <span class="flex-1">
                {ngettext(
                  "%{count} autre élève sans incident : %{mark}/20",
                  "%{count} autres élèves sans incident : %{mark}/20",
                  length(@folded),
                  mark: shown(hd(@folded).suggestion.mark)
                )}
              </span>
              <button
                type="button"
                id="show-folded"
                phx-click="toggle_incidents"
                class="font-semibold text-primary hover:underline"
              >
                {gettext("Afficher")}
              </button>
            </div>
            <p
              :if={@shown_rows == [] and @folded == []}
              class="px-4 py-3 text-sm text-base-content/70"
            >
              {gettext("Aucun élève dans cette classe.")}
            </p>
          </section>

          <p :if={@error} id="conduct-error" class="text-sm text-error">{@error}</p>

          <div class="flex flex-wrap justify-end gap-2">
            <button
              type="submit"
              id="validate-class"
              class="btn btn-primary"
              phx-disable-with={gettext("Enregistrement…")}
            >
              {if @next,
                do:
                  gettext("Valider %{class} et passer à %{next}", class: @cg.label, next: @next.label),
                else: gettext("Valider %{class}", class: @cg.label)}
            </button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
