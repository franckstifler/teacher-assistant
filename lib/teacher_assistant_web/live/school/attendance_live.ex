defmodule TeacherAssistantWeb.School.AttendanceLive do
  @moduledoc "The roll call of one class at one period on one date (`?date=`, default today)."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{CombinedCourse, Reference}
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.School.RollCall
  alias TeacherAssistantWeb.Spaces

  # Reached from Ma journée, Mes cours, the school's day or a class: the member's
  # own entry is lit and leads back.
  @nav ["today", "day", "courses", "classes"]

  def mount(%{"id" => id, "period_id" => period_id} = params, _session, socket) do
    case RollCall.open(socket.assigns.current_scope, id, period_id, parse_date(params["date"])) do
      {:ok, roll} ->
        {:ok,
         assign(socket,
           page_title: "#{unit_label(roll)} · #{gettext("Appel")}",
           roll: roll,
           nav: @nav,
           parent: Spaces.owner_item_for(socket.assigns.current_scope, @nav)
         )}

      {:error, :forbidden} ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp parse_date(nil), do: Reference.today()

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> Reference.today()
    end
  end

  def handle_event("all_present", _params, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.all_present(&1)))}

  def handle_event("minutes", %{"minutes" => minutes}, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.set_minutes(&1, minutes)))}

  def handle_event("set", %{"enrollment_id" => id, "status" => status}, socket),
    do: {:noreply, update(socket, :roll, &RollCall.set(&1, id, status))}

  def handle_event("record", _params, socket) do
    case RollCall.record(socket.assigns.current_scope, socket.assigns.roll) do
      {:ok, roll} ->
        {:noreply, socket |> assign(:roll, roll) |> put_flash(:info, gettext("Appel enregistré"))}

      {:error, reason} ->
        {:noreply, RollCall.put_error(socket, reason)}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={@nav}
    >
      <section id="class-attendance" class="mx-auto flex max-w-2xl flex-col gap-5">
        <.breadcrumb :if={@parent}>
          <:crumb id="attendance-back" navigate={@parent.path}>{@parent.label}</:crumb>
          <:crumb>{gettext("Appel")}</:crumb>
        </.breadcrumb>
        <.page_header
          eyebrow={gettext("Appel · %{date}", date: Dates.long(@roll.date))}
          title={unit_label(@roll)}
        />
        <RollCall.roll_panel roll={@roll} title={panel_title(@roll)} />
      </section>
    </Layouts.app>
    """
  end

  defp unit_label(%{course: %CombinedCourse{label: label}}), do: label
  defp unit_label(%{cg: cg}), do: cg.label

  defp panel_title(roll),
    do:
      "#{roll.period.label} · #{unit_label(roll)} — #{Calendar.strftime(roll.period.start_time, "%H:%M")}"
end
