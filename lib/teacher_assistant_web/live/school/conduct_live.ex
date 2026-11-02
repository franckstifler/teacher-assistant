defmodule TeacherAssistantWeb.School.ConductLive do
  @moduledoc """
  SG → Conduite (spec KLM3, V05; Vie scolaire redesign §2.3): for a class and a
  séquence, each student's unjustified hours and sanctions, the conduct mark the
  school's scale suggests (row click: the deductions, lates included), and an
  input pre-filled with the current mark (else the suggestion). « Valider la
  classe » saves the class in one go.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{EntryProgress, Reference, SanctionType}
  alias TeacherAssistantWeb.Authz

  # More classes than this: a select instead of tabs (and always on phones).
  @max_tabs 8

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Discipline.can_manage_conduct?(scope) do
      year = scope.current_academic_year

      {:ok,
       assign(socket,
         page_title: gettext("Conduite"),
         classes: Enrollment.list_class_groups(scope, year),
         sequences: Organization.list_sequences(scope, year),
         rules: Attendance.school_life_rules(scope),
         open: nil,
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

    {:noreply, socket |> assign(cg: cg, seq: seq, open: nil, error: nil) |> load()}
  end

  defp load(%{assigns: %{cg: cg, seq: seq}} = socket) when not is_nil(cg) and not is_nil(seq) do
    rows = Discipline.conduct_sheet(socket.assigns.current_scope, cg, seq)
    values = Map.new(rows, &{&1.enrollment.id, shown(&1.current || &1.suggestion.mark)})
    assign(socket, rows: rows, values: values)
  end

  defp load(socket), do: assign(socket, rows: [], values: %{})

  # A year without séquences (or classes) posts no value for that select.
  def handle_event("pick", params, socket) do
    query = params |> Map.take(["class", "seq"]) |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    {:noreply, push_patch(socket, to: ~p"/school/conduct?#{query}")}
  end

  def handle_event("edit", %{"marks" => marks}, socket),
    do: {:noreply, assign(socket, values: Map.merge(socket.assigns.values, marks))}

  def handle_event("apply", _params, socket) do
    values = Map.new(socket.assigns.rows, &{&1.enrollment.id, shown(&1.suggestion.mark)})
    {:noreply, assign(socket, values: values)}
  end

  def handle_event("toggle", %{"id" => id}, socket),
    do: {:noreply, assign(socket, open: if(socket.assigns.open == id, do: nil, else: id))}

  def handle_event("validate", %{"marks" => marks}, socket) do
    %{current_scope: scope, cg: cg, seq: seq} = socket.assigns

    case Discipline.set_conduct_marks(scope, cg, seq, marks) do
      {:ok, count} ->
        {:noreply,
         socket
         |> load()
         |> assign(error: nil)
         |> put_flash(
           :info,
           ngettext(
             "%{count} note de conduite enregistrée",
             "%{count} notes de conduite enregistrées",
             count
           )
         )}

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

  defp rule_text(rules) do
    gettext(
      "règle : 20 − %{per_hour} pt / h injustifiée − %{per_late} pt / retard − points par sanction",
      per_hour: shown(rules.points_per_absence_hour),
      per_late: shown(rules.points_per_late)
    )
  end

  def render(assigns) do
    assigns = assign(assigns, tabs?: length(assigns.classes) <= @max_tabs)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="conduct" class="flex flex-col gap-4">
        <.page_header
          eyebrow={gettext("Vie scolaire")}
          title={gettext("Conduite")}
          subtitle={gettext("Note de conduite /20 par séquence, portée sur le bulletin.")}
        >
          <:actions :if={@rows != []}>
            <button
              type="button"
              id="apply-suggestions"
              phx-click="apply"
              class="btn btn-primary btn-sm"
            >
              {gettext("Appliquer les suggestions")}
            </button>
          </:actions>
        </.page_header>

        <div class="flex flex-wrap items-center gap-2.5">
          <nav
            :if={@tabs? and @classes != []}
            id="conduct-class-tabs"
            class="hidden gap-0.5 rounded-[0.55rem] border border-base-300 bg-base-200 p-[3px] sm:flex"
          >
            <.link
              :for={c <- @classes}
              id={"conduct-tab-#{c.id}"}
              patch={~p"/school/conduct?#{[class: c.id] ++ if(@seq, do: [seq: @seq.id], else: [])}"}
              aria-current={@cg && c.id == @cg.id && "page"}
              class={[
                "rounded-[0.45rem] px-3 py-2 text-[0.8rem] font-semibold transition-colors",
                if(@cg && c.id == @cg.id,
                  do: "bg-primary text-primary-content",
                  else: "text-base-content/85 hover:text-base-content"
                )
              ]}
            >
              {c.label}
            </.link>
          </nav>
          <form id="conduct-pick" phx-change="pick" class="flex flex-wrap gap-2">
            <select
              name="class"
              aria-label={gettext("Classe")}
              class={["select select-sm w-auto", @tabs? && "sm:hidden"]}
            >
              <option :for={c <- @classes} value={c.id} selected={@cg && c.id == @cg.id}>
                {c.label}
              </option>
            </select>
            <select name="seq" aria-label={gettext("Séquence")} class="select select-sm w-auto">
              <option :for={s <- @sequences} value={s.id} selected={@seq && s.id == @seq.id}>
                {gettext("Séquence %{n}", n: s.number)}
              </option>
            </select>
          </form>
          <span id="conduct-rule" class="text-[0.82rem] text-base-content/80">
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
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Élève")}</th>
                  <th class="text-right">{gettext("Abs. injust.")}</th>
                  <th class="hidden sm:table-cell">{gettext("Sanctions")}</th>
                  <th class="text-right">{gettext("Suggestion")}</th>
                  <th class="text-right sm:w-[130px]">{gettext("Note /20")}</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @rows do %>
                  <tr id={"conduct-row-#{row.enrollment.id}"}>
                    <td>
                      <button
                        type="button"
                        id={"conduct-name-#{row.enrollment.id}"}
                        phx-click="toggle"
                        phx-value-id={row.enrollment.id}
                        class="text-left font-semibold hover:text-primary"
                      >
                        {row.student.full_name}
                      </button>
                    </td>
                    <td class="ta-num text-right">
                      {shown(Decimal.round(row.unjustified_hours, 1))} h
                    </td>
                    <td class="hidden sm:table-cell">
                      <span :if={row.sanctions == []} class="text-base-content/70">—</span>
                      <span
                        :for={s <- row.sanctions}
                        class="badge badge-sm badge-ghost mr-1"
                      >
                        {SanctionType.label(s.type)} −{shown(@rules.sanction_points[s.type])}
                      </span>
                    </td>
                    <td class="ta-num text-right font-semibold text-warning">
                      {shown(row.suggestion.mark)}
                    </td>
                    <td class="text-right">
                      <span :if={adjusted?(row, @values)} class="badge badge-warning badge-xs mr-1">
                        {gettext("ajustée")}
                      </span>
                      <input
                        id={"conduct-input-#{row.enrollment.id}"}
                        name={"marks[#{row.enrollment.id}]"}
                        value={@values[row.enrollment.id]}
                        inputmode="decimal"
                        aria-label={
                          gettext("Note de conduite de %{name}", name: row.student.full_name)
                        }
                        class="input input-sm w-20 text-right"
                      />
                    </td>
                  </tr>
                  <tr :if={@open == row.enrollment.id} id={"deductions-#{row.enrollment.id}"}>
                    <td colspan="5" class="bg-base-200/60 text-xs">
                      <span :if={row.suggestion.deductions == []}>{gettext("Aucune déduction.")}</span>
                      <span :for={d <- row.suggestion.deductions} class="mr-3">
                        {deduction_label(d)} : −{shown(Decimal.round(d.points, 2))}
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <p :if={@error} id="conduct-error" class="text-sm text-error">{@error}</p>

          <div class="flex flex-wrap gap-2">
            <button type="submit" id="validate-class" class="btn btn-primary btn-sm">
              {gettext("Valider la classe")}
            </button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
