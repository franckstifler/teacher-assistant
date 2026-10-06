defmodule TeacherAssistantWeb.School.ConductLive do
  @moduledoc """
  SG → Conduite (spec KLM3, V05): for a class and a séquence, each student's
  unjustified hours, lates and sanctions, the conduct mark the school's scale
  suggests, and an input pre-filled with the current mark (else the
  suggestion). « Valider la classe » saves the class in one go.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{EntryProgress, Reference, SanctionType}
  alias TeacherAssistantWeb.Authz

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Discipline.can_manage_conduct?(scope) do
      year = scope.current_academic_year

      {:ok,
       assign(socket,
         classes: Enrollment.list_class_groups(scope, year),
         sequences: Organization.list_sequences(scope, year),
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
    cg = Enum.find(socket.assigns.classes, &(&1.id == params["class"])) || List.first(socket.assigns.classes)

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

  def handle_event("pick", %{"class" => class, "seq" => seq}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/conduct?class=#{class}&seq=#{seq}")}

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
        name = Enum.find_value(socket.assigns.rows, &(&1.enrollment.id == id && &1.student.full_name))

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

  defp adjusted?(row, values),
    do: Map.get(values, row.enrollment.id) not in [shown(row.suggestion.mark), nil, ""]

  defp shown(nil), do: ""

  defp shown(%Decimal{} = d),
    do: d |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp deduction_label(%{kind: :absences, count: hours}),
    do: gettext("%{hours} h non justifiées", hours: shown(Decimal.round(hours, 2)))

  defp deduction_label(%{kind: :retards, count: n}),
    do: ngettext("%{count} retard", "%{count} retards", n)

  defp deduction_label(%{kind: {:sanction, type}, count: n}), do: "#{n} × #{SanctionType.label(type)}"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="conduct" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Vie scolaire")} title={gettext("Conduite")} />

        <form id="conduct-pick" phx-change="pick" class="flex flex-wrap gap-2">
          <select name="class" class="select select-sm">
            <option :for={c <- @classes} value={c.id} selected={@cg && c.id == @cg.id}>{c.label}</option>
          </select>
          <select name="seq" class="select select-sm">
            <option :for={s <- @sequences} value={s.id} selected={@seq && s.id == @seq.id}>
              {gettext("Séquence %{n}", n: s.number)}
            </option>
          </select>
        </form>

        <p :if={@rows == []} class="text-sm text-base-content/70">{gettext("Aucun élève dans cette classe.")}</p>

        <.form :if={@rows != []} for={%{}} id="conduct-form" phx-change="edit" phx-submit="validate" class="flex flex-col gap-3">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Élève")}</th>
                  <th class="text-right">{gettext("h non justifiées")}</th>
                  <th class="text-right">{gettext("Retards")}</th>
                  <th>{gettext("Sanctions")}</th>
                  <th class="text-right">{gettext("Proposée")}</th>
                  <th class="text-right">{gettext("Actuelle")}</th>
                  <th class="text-right">{gettext("Note")}</th>
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
                        class="font-semibold hover:text-primary"
                      >
                        {row.student.full_name}
                      </button>
                    </td>
                    <td class="ta-num text-right">{shown(Decimal.round(row.unjustified_hours, 1))}</td>
                    <td class="ta-num text-right">{row.retards}</td>
                    <td>
                      <span
                        :for={s <- row.sanctions}
                        class="badge badge-sm badge-ghost mr-1"
                      >
                        {SanctionType.label(s.type)}
                      </span>
                    </td>
                    <td class="ta-num text-right font-semibold">{shown(row.suggestion.mark)}</td>
                    <td class="ta-num text-right">{shown(row.current)}</td>
                    <td class="text-right">
                      <span :if={adjusted?(row, @values)} class="badge badge-warning badge-xs mr-1">
                        {gettext("ajustée")}
                      </span>
                      <input
                        id={"conduct-input-#{row.enrollment.id}"}
                        name={"marks[#{row.enrollment.id}]"}
                        value={@values[row.enrollment.id]}
                        inputmode="decimal"
                        class="input input-xs w-16 text-right"
                      />
                    </td>
                  </tr>
                  <tr :if={@open == row.enrollment.id} id={"deductions-#{row.enrollment.id}"}>
                    <td colspan="7" class="bg-base-200/60 text-xs">
                      <span :if={row.suggestion.deductions == []}>{gettext("Aucune déduction.")}</span>
                      <span :for={d <- row.suggestion.deductions} class="mr-3">
                        {deduction_label(d)} : −{shown(d.points)}
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <p :if={@error} id="conduct-error" class="text-sm text-error">{@error}</p>

          <div class="flex flex-wrap gap-2">
            <button type="button" id="apply-suggestions" phx-click="apply" class="btn btn-ghost btn-sm">
              {gettext("Appliquer les propositions")}
            </button>
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
