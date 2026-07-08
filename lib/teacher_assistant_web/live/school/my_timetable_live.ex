defmodule TeacherAssistantWeb.School.MyTimetableLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.Timetables

  @days [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type != :school do
      {:ok, push_navigate(socket, to: ~p"/teacher")}
    else
      {:ok,
       assign(socket,
         periods: Timetables.list_periods(scope.current_workspace),
         grid: Timetables.teacher_timetable(scope.current_workspace, scope.current_user),
         days: @days
       )}
    end
  end

  defp day_label(:monday), do: gettext("Lundi")
  defp day_label(:tuesday), do: gettext("Mardi")
  defp day_label(:wednesday), do: gettext("Mercredi")
  defp day_label(:thursday), do: gettext("Jeudi")
  defp day_label(:friday), do: gettext("Vendredi")
  defp day_label(:saturday), do: gettext("Samedi")

  defp cell_text(nil), do: nil
  defp cell_text(slot), do: "#{slot.class_label} · #{slot.subject}"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="my-timetable" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Mon emploi du temps")} />

        <div class="flex justify-end">
          <a
            id="print-my-timetable"
            href={~p"/school/timetable/me/print"}
            target="_blank"
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer")}
          </a>
        </div>

        <%= if @grid == %{} do %>
          <.empty_state
            icon="hero-calendar-days"
            title={gettext("Aucun cours placé pour le moment")}
            message={gettext("Vous n'avez pas encore de créneau dans l'emploi du temps.")}
          />
        <% else %>
          <div class="overflow-x-auto">
            <table id="my-timetable-grid" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Période")}</th>
                  <th :for={day <- @days}>{day_label(day)}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={period <- @periods} id={"period-row-#{period.id}"}>
                  <%= if period.kind == :break do %>
                    <td colspan={length(@days) + 1} class="text-center italic text-base-content/60">
                      {period.label}
                    </td>
                  <% else %>
                    <td class="font-semibold">{period.label}</td>
                    <td :for={day <- @days} id={"cell-#{day}-#{period.id}"}>
                      <% slot = @grid[{day, period.id}] %>
                      {cell_text(slot)}
                      <.link
                        :if={slot}
                        navigate={
                          ~p"/school/classes/#{slot.class_group_id}/attendance/#{period.id}?date=#{Date.to_iso8601(Date.utc_today())}"
                        }
                        class="link link-primary block text-xs"
                      >
                        {gettext("Faire l'appel")}
                      </.link>
                    </td>
                  <% end %>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
