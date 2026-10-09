defmodule TeacherAssistant.Workers.MissedRollCalls do
  @moduledoc """
  Pilotage redesign §1.3: once per half-day, tells each school's Proviseur and
  Surveillant général which roll calls were not taken. Nothing on a day off, when
  every call is done, or when the same half-day was already reported today.
  """
  use Oban.Worker, queue: :default, unique: [period: 3600]

  require Ash.Query

  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.{Notification, Workspaces}
  alias TeacherAssistant.{Attendance, Notifications, Scope}
  alias TeacherAssistantWeb.School.SchoolLifeComponents, as: Components

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = Reference.now()
    half = half(args, now)

    for scope <- Workspaces.job_scopes(), Scope.school_verified?(scope) do
      notify(scope, Reference.today(), now, half)
    end

    :ok
  end

  defp half(%{"half" => half}, _now) when half in ["morning", "afternoon"], do: half
  defp half(_args, now), do: if(now.hour < 13, do: "morning", else: "afternoon")

  defp notify(scope, today, now, half) do
    with nil <- Attendance.day_off(scope, today),
         [_ | _] = missed <-
           scope
           |> Attendance.roll_call_counts(today, now)
           |> Map.fetch!(:missed)
           |> Enum.filter(&(half_of(&1.period) == half)),
         false <- already_sent?(scope, half) do
      Notifications.deliver(
        scope,
        :missed_roll_calls,
        recipient_ids(scope),
        %{count: length(missed), half: half, list: list(missed)},
        "/school/day"
      )
    end
  end

  defp half_of(period), do: if(period.start_time.hour < 13, do: "morning", else: "afternoon")

  defp list(missed) do
    Enum.map_join(missed, " · ", fn cell ->
      "#{cell.class_group.label} #{Components.hm(cell.period.start_time)} (#{Components.teacher_name(cell.teacher)})"
    end)
  end

  defp recipient_ids(scope) do
    for m <- Accounts.list_members(scope),
        Enum.any?(m.roles, &(&1 in [:head, :discipline_master])),
        do: m.user_id
  end

  # A retry of the same half-day sends nothing new: the two daily runs are 5 h apart
  # and carry different halves, so a same-half notice in the last 12 h is a retry.
  defp already_sent?(scope, half) do
    since = DateTime.add(DateTime.utc_now(), -12, :hour)

    Notification
    |> Ash.Query.filter(kind == :missed_roll_calls and inserted_at >= ^since)
    |> Ash.read!(tenant: scope.current_workspace.id, authorize?: false)
    |> Enum.any?(&(&1.params["half"] == half))
  end
end
