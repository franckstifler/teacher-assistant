defmodule TeacherAssistantWeb.School.AttendanceLive do
  @moduledoc """
  The roll call of one class (or combined course) at one period on one date
  (`?date=`, default today). On phones a task header « Appel · Matière · Niveau »
  over « mar. 3 nov. · Cours 4 · 10:15 · 39 élèves », without the tab bar.
  """
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
           page_title: "#{unit_title(roll)} · #{gettext("Appel")}",
           roll: roll,
           nav: @nav,
           parent: Spaces.owner_item_for(socket.assigns.current_scope, @nav)
         )}

      {:error, :forbidden} ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      {:error, reason} when reason in [:not_started, :too_old] ->
        {:ok,
         socket
         |> put_flash(:error, RollCall.error_message(reason))
         |> push_navigate(to: ~p"/school")}

      {:error, {:held_by, _who} = reason} ->
        {:ok,
         socket
         |> put_flash(:error, RollCall.error_message(reason))
         |> push_navigate(to: ~p"/school")}

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
    do: {:noreply, update(socket, :roll, &RollCall.toggle(&1, id, status))}

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
      immersive
    >
      <section id="class-attendance" class="mx-auto flex max-w-2xl flex-col gap-4 pb-4">
        <.back_header
          task
          back={@parent && @parent.path}
          back_label={@parent && @parent.label}
          title={gettext("Appel · %{what}", what: unit_title(@roll))}
          subtitle={roll_line(@roll)}
        />
        <RollCall.roll_panel roll={@roll} />
      </section>
    </Layouts.app>
    """
  end

  # « Maths · 6e A », or the combined course's label.
  defp unit_title(%{course: %CombinedCourse{label: label}}), do: label

  defp unit_title(%{teaching_context: %{subject: subject}, cg: cg}),
    do: "#{subject} · #{cg.label}"

  defp unit_title(%{cg: cg}), do: cg.label

  # « mar. 3 nov. · Cours 4 · 10:15 · 39 élèves »
  defp roll_line(roll),
    do:
      Enum.join(
        [
          Dates.short(roll.date),
          roll.period.label,
          Calendar.strftime(roll.period.start_time, "%H:%M"),
          ngettext("%{count} élève", "%{count} élèves", length(roll.students))
        ],
        " · "
      )
end
