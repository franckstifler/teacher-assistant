defmodule TeacherAssistant.Operator do
  @moduledoc """
  Reads for the operator console (operator console spec §5). The operator spans every
  school, so each function first checks the actor is an operator, then reads without
  authorization: per school with its tenant, and platform totals as plain table
  counts (tenant-scoped resources refuse a read with no tenant). Never call these
  from a school screen.
  """
  require Ash.Query
  import Ecto.Query, only: [from: 2, subquery: 1, union_all: 2]

  alias TeacherAssistant.Academics.{ClassGroup, Enrollment, Workspace}
  alias TeacherAssistant.Accounts.{Phone, SchoolMembership, SchoolProfile, User}
  alias TeacherAssistant.{Repo, Scope}

  @read [authorize?: false]

  # What counts as a school « acting »: a row someone typed in, with who typed it and the
  # module it belongs to. Screens with no such trail (timetable, photos) have no usage figure.
  @activity [
    {"mark_events", :actor_user_id, :notes},
    {"attendance_entries", :recorded_by_user_id, :appel},
    {"typed_absences", :recorded_by_user_id, :appel},
    {"sanction_entries", :issued_by_user_id, :discipline},
    {"payments", :recorded_by_user_id, :frais}
  ]
  @weeks 12
  @quiet_days 14
  # Rows of the overview's school table; the rest is one click away (« Tous → »).
  @school_rows 10

  @doc """
  The platform at a glance: schools by status, what needs the operator (verification queue,
  schools gone quiet or never started), growth, the activation funnel, the last 7 days' use,
  12 weeks of activity, module adoption, a table of schools (most active first, at most
  #{@school_rows}) and system health.
  """
  def overview(%Scope{} = scope) do
    ensure_operator!(scope)
    now = DateTime.utc_now()
    week_ago = DateTime.add(now, -7, :day)
    profiles = SchoolProfile |> Ash.Query.load(:workspace) |> Ash.read!(@read)

    live =
      Enum.filter(
        profiles,
        &(&1.verification_status == :verified and is_nil(&1.workspace.suspended_at))
      )

    per_school = activity_per_school(now)
    with_students = schools_with_students()

    %{
      schools: %{
        unverified: Enum.count(profiles, &(&1.verification_status == :unverified)),
        verified: Enum.count(profiles, &(&1.verification_status == :verified)),
        rejected: Enum.count(profiles, &(&1.verification_status == :rejected)),
        suspended: Enum.count(profiles, &(&1.workspace.suspended_at != nil)),
        total: length(profiles)
      },
      members: count(from(m in "school_memberships", where: m.active == true)),
      students: Enum.sum(Map.values(with_students)),
      roll_calls_7d: count(from(a in "attendance_entries", where: a.inserted_at >= ^week_ago)),
      marks_7d: count(from(m in "mark_events", where: m.inserted_at >= ^week_ago)),
      attention: attention(profiles, live, per_school, now),
      growth: growth(now),
      funnel: funnel(profiles, with_students, per_school),
      usage: usage(live, per_school, week_ago),
      weekly: weekly(now),
      modules: modules(live, now),
      school_rows: school_rows(profiles, per_school, with_students, accounts_per_school()),
      system: system()
    }
  end

  @doc """
  Every school, newest first, with its profile and owner. `filters`: `q` (name or
  town), `status` (verification), `suspended` (true/false), `module` (a module key).
  """
  def list_schools(%Scope{} = scope, filters) do
    ensure_operator!(scope)
    q = filters |> Map.get(:q, "") |> to_string() |> String.trim()

    SchoolProfile
    |> Ash.Query.load([:workspace, :owner_user])
    |> Ash.Query.sort(inserted_at: :desc)
    |> filter_q(q)
    |> filter_status(filters[:status])
    |> Ash.read!(@read)
    |> Enum.filter(&suspended_matches?(&1.workspace, filters[:suspended]))
    |> Enum.filter(&(filters[:module] == nil or filters[:module] in &1.workspace.modules))
    |> Enum.map(&%{workspace: &1.workspace, profile: &1, owner: &1.owner_user})
  end

  @doc """
  One school: workspace, profile, active members (with user), counts, last activity, and
  per module its actions in the last 30 days (`module_use`; nil for a module with no
  activity trail).
  """
  def get_school(%Scope{} = scope, id) do
    ensure_operator!(scope)

    with {:ok, %Workspace{} = ws} <- Ash.get(Workspace, id, [not_found_error?: false] ++ @read),
         [profile] <-
           SchoolProfile |> Ash.Query.filter(workspace_id == ^ws.id) |> Ash.read!(@read) do
      members =
        SchoolMembership
        |> Ash.Query.filter(active == true)
        |> Ash.Query.set_tenant(ws.id)
        |> Ash.Query.load(:user)
        |> Ash.read!(@read)

      {:ok,
       %{
         workspace: ws,
         profile: profile,
         members: members,
         counts: %{
           classes: ClassGroup |> Ash.Query.set_tenant(ws.id) |> Ash.count!(@read),
           students:
             Enrollment
             |> Ash.Query.set_tenant(ws.id)
             |> Ash.Query.filter(academic_year.active == true)
             |> Ash.count!(@read),
           staff: length(members)
         },
         last_activity: last_activity(ws.id),
         module_use: module_use(ws.id, DateTime.utc_now())
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Users whose name, e-mail or phone matches `q` (at most 50), with their schools."
  def search_users(%Scope{} = scope, q) do
    ensure_operator!(scope)

    case q |> to_string() |> String.trim() do
      "" ->
        []

      q ->
        like = "%#{q}%"

        query =
          case Phone.normalize(q) do
            {:ok, phone} -> Ash.Query.filter(User, phone == ^phone)
            _ -> Ash.Query.filter(User, ilike(name, ^like) or contains(email, ^q))
          end

        query
        |> Ash.Query.sort(name: :asc)
        |> Ash.Query.limit(50)
        |> Ash.read!(@read)
        |> Enum.map(&%{user: &1, memberships: memberships_of(&1)})
    end
  end

  @doc "A user by id, for the operator's reset."
  def get_user(%Scope{} = scope, id) do
    ensure_operator!(scope)

    case Ash.get(User, id, [not_found_error?: false] ++ @read) do
      {:ok, %User{} = user} -> {:ok, user}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Starts acting as `user_id` in `workspace_id`: the user must be an active member of that
  school and not an operator. Journaled (`impersonation_started`).
  """
  def start_impersonation(%Scope{} = scope, user_id, workspace_id) do
    ensure_operator!(scope)

    with {:ok, %User{} = user} when user.role != :admin <-
           Ash.get(User, user_id, [not_found_error?: false] ++ @read),
         {:ok, %Workspace{} = ws} <-
           Ash.get(Workspace, workspace_id, [not_found_error?: false] ++ @read),
         true <- active_member?(user, ws) do
      journal(scope, :impersonation_started, ws.id, user.id, %{})
      {:ok, %{user: user, workspace: ws}}
    else
      _ -> {:error, :not_allowed}
    end
  end

  @doc "Ends acting as `user_id` in `workspace_id`; `reason` is kept in the journal."
  def end_impersonation(%Scope{} = scope, user_id, workspace_id, reason) do
    ensure_operator!(scope)
    journal(scope, :impersonation_ended, workspace_id, user_id, %{reason: reason})
  end

  @doc """
  The user the operator is acting as, while that is still allowed: nil once they are an
  operator themselves or gone. Membership is checked by the scope built for them.
  """
  def impersonated_user(%Scope{} = scope, user_id) do
    ensure_operator!(scope)

    case Ash.get(User, user_id, [not_found_error?: false] ++ @read) do
      {:ok, %User{role: role} = user} when role != :admin -> user
      _ -> nil
    end
  end

  defp active_member?(user, ws) do
    SchoolMembership
    |> Ash.Query.filter(user_id == ^user.id and active == true)
    |> Ash.Query.set_tenant(ws.id)
    |> Ash.exists?(@read)
  end

  defp journal(scope, action, workspace_id, target_user_id, details) do
    TeacherAssistant.Accounts.AuditEvent
    |> Ash.Changeset.for_create(:record, %{
      actor_user_id: scope.current_user.id,
      action: action,
      workspace_id: workspace_id,
      target_user_id: target_user_id,
      details: details
    })
    |> Ash.create!(@read)

    :ok
  end

  defp memberships_of(user) do
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user.id})
    |> Ash.read!(@read)
  end

  # Every activity row since `since`, as {workspace_id, user_id, at, module}.
  defp activity_since(%DateTime{} = since) do
    @activity
    |> Enum.map(fn {table, actor, module} ->
      from(r in table,
        where: r.inserted_at >= ^since,
        select: %{
          workspace_id: r.workspace_id,
          user_id: field(r, ^actor),
          at: r.inserted_at,
          module: type(^Atom.to_string(module), :string)
        }
      )
    end)
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
  end

  # Per school over the last 12 weeks: its last action and its actions in the last 7 days.
  defp activity_per_school(now) do
    week_ago = DateTime.add(now, -7, :day)

    from(a in subquery(activity_since(DateTime.add(now, -@weeks * 7, :day))),
      group_by: a.workspace_id,
      select:
        {type(a.workspace_id, Ecto.UUID),
         %{
           last_at: max(a.at),
           actions_7d: fragment("count(*) FILTER (WHERE ? >= ?)", a.at, ^week_ago)
         }}
    )
    |> Repo.all()
    |> Map.new(fn {id, row} -> {id, %{row | last_at: to_datetime(row.last_at)}} end)
  end

  # Students enrolled in an active year, per school.
  defp schools_with_students do
    from(e in "enrollments",
      join: y in "academic_years",
      on: y.id == e.academic_year_id,
      where: y.active == true,
      group_by: e.workspace_id,
      select: {type(e.workspace_id, Ecto.UUID), count()}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp attention(profiles, live, per_school, now) do
    quiet_before = DateTime.add(now, -@quiet_days, :day)
    week_ago = DateTime.add(now, -7, :day)

    %{
      pending:
        profiles
        |> Enum.filter(&(&1.verification_status == :unverified))
        |> Enum.sort_by(& &1.inserted_at, DateTime)
        |> Enum.map(&%{id: &1.workspace.id, name: &1.workspace.name, since: &1.inserted_at}),
      quiet:
        live
        |> Enum.filter(
          &(per_school[&1.workspace.id] &&
              before?(per_school[&1.workspace.id].last_at, quiet_before))
        )
        |> Enum.map(
          &%{
            id: &1.workspace.id,
            name: &1.workspace.name,
            last_at: per_school[&1.workspace.id].last_at
          }
        )
        |> Enum.sort_by(& &1.last_at, DateTime),
      silent:
        live
        |> Enum.filter(
          &(is_nil(per_school[&1.workspace.id]) and before?(&1.workspace.inserted_at, week_ago))
        )
        |> Enum.sort_by(& &1.workspace.inserted_at, DateTime)
        |> Enum.map(
          &%{id: &1.workspace.id, name: &1.workspace.name, since: &1.workspace.inserted_at}
        )
    }
  end

  defp before?(at, limit), do: DateTime.compare(at, limit) == :lt

  # New schools and users in the last 30 days, and in the 30 days before.
  defp growth(now) do
    month_ago = DateTime.add(now, -30, :day)
    two_months_ago = DateTime.add(now, -60, :day)

    new_in = fn table, from_at, to_at ->
      count(from(r in table, where: r.inserted_at >= ^from_at and r.inserted_at < ^to_at))
    end

    %{
      new_schools: new_in.("workspaces", month_ago, now),
      new_schools_before: new_in.("workspaces", two_months_ago, month_ago),
      new_users: new_in.("users", month_ago, now),
      new_users_before: new_in.("users", two_months_ago, month_ago)
    }
  end

  # Each step keeps only the schools of the step before.
  defp funnel(profiles, with_students, per_school) do
    signed_up = Enum.reject(profiles, &(&1.verification_status == :rejected))
    verified = Enum.filter(signed_up, &(&1.verification_status == :verified))
    set_up = Enum.filter(verified, &Map.has_key?(with_students, &1.workspace.id))
    active = Enum.filter(set_up, &((get_in(per_school, [&1.workspace.id, :actions_7d]) || 0) > 0))

    %{
      signed_up: length(signed_up),
      verified: length(verified),
      set_up: length(set_up),
      active: length(active)
    }
  end

  defp usage(live, per_school, week_ago) do
    %{
      live_schools: length(live),
      active_schools: Enum.count(per_school, fn {_id, row} -> row.actions_7d > 0 end),
      active_users:
        Repo.one(
          from(a in subquery(activity_since(week_ago)), select: count(a.user_id, :distinct))
        ),
      actions: per_school |> Enum.map(fn {_id, row} -> row.actions_7d end) |> Enum.sum()
    }
  end

  # Actions and acting schools per week (Monday first), oldest first, this week last.
  defp weekly(now) do
    this_monday = now |> DateTime.to_date() |> Date.beginning_of_week()
    first = Date.add(this_monday, -(@weeks - 1) * 7)

    rows =
      from(a in subquery(activity_since(DateTime.new!(first, ~T[00:00:00]))),
        group_by: fragment("date_trunc('week', ?)::date", a.at),
        select:
          {fragment("date_trunc('week', ?)::date", a.at),
           %{actions: count(), schools: count(a.workspace_id, :distinct)}}
      )
      |> Repo.all()
      |> Map.new()

    for i <- 0..(@weeks - 1) do
      week = Date.add(first, i * 7)
      Map.merge(%{week: week, actions: 0, schools: 0}, Map.get(rows, week, %{}))
    end
  end

  # Per module: live schools that have it, and schools that used it in the last 30 days
  # (nil for a module with no activity trail).
  defp modules(live, now) do
    used =
      from(a in subquery(activity_since(DateTime.add(now, -30, :day))),
        group_by: a.module,
        select: {a.module, count(a.workspace_id, :distinct)}
      )
      |> Repo.all()
      |> Map.new()

    tracked = @activity |> Enum.map(&elem(&1, 2)) |> MapSet.new()

    Map.new(TeacherAssistant.Modules.keys(), fn key ->
      {key,
       %{
         enabled: Enum.count(live, &(key in &1.workspace.modules)),
         used: if(key in tracked, do: Map.get(used, Atom.to_string(key), 0))
       }}
    end)
  end

  # Every school, most active this week first, then by last action, then newest: its
  # status, students, activated accounts (members past their temporary password) and use.
  defp school_rows(profiles, per_school, with_students, accounts) do
    profiles
    |> Enum.map(fn p ->
      id = p.workspace.id
      row = Map.get(per_school, id, %{actions_7d: 0, last_at: nil})
      members = Map.get(accounts, id, %{total: 0, activated: 0})

      %{
        id: id,
        name: p.workspace.name,
        town: p.town,
        status: p.verification_status,
        suspended?: p.workspace.suspended_at != nil,
        students: Map.get(with_students, id, 0),
        members: members.total,
        activated: members.activated,
        actions_7d: row.actions_7d,
        last_at: row.last_at,
        inserted_at: p.workspace.inserted_at
      }
    end)
    |> Enum.sort_by(
      &{-&1.actions_7d, -unix(&1.last_at), -unix(&1.inserted_at)},
      :asc
    )
    |> Enum.take(@school_rows)
  end

  defp unix(nil), do: 0
  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)

  # Active members per school, and how many of them chose their own password.
  defp accounts_per_school do
    from(m in "school_memberships",
      join: u in "users",
      on: u.id == m.user_id,
      where: m.active == true,
      group_by: m.workspace_id,
      select:
        {type(m.workspace_id, Ecto.UUID),
         %{
           total: count(),
           activated: fragment("count(*) FILTER (WHERE NOT ?)", u.must_change_password)
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp system do
    jobs =
      from(j in "oban_jobs", group_by: j.state, select: {j.state, count()})
      |> Repo.all()
      |> Map.new()

    %{rows: [[db_bytes]]} = Repo.query!("SELECT pg_database_size(current_database())")
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      jobs: %{
        waiting: Map.get(jobs, "available", 0) + Map.get(jobs, "scheduled", 0),
        retrying: Map.get(jobs, "retryable", 0),
        failed: Map.get(jobs, "discarded", 0)
      },
      last_job_at:
        from(j in "oban_jobs", where: j.state == "completed", select: max(j.completed_at))
        |> Repo.one()
        |> then(&(&1 && to_datetime(&1))),
      db_bytes: db_bytes,
      memory_bytes: :erlang.memory(:total),
      uptime_ms: uptime_ms,
      version: to_string(Application.spec(:teacher_assistant, :vsn))
    }
  end

  defp module_use(workspace_id, now) do
    used =
      from(a in subquery(activity_since(DateTime.add(now, -30, :day))),
        where: a.workspace_id == type(^workspace_id, :binary_id),
        group_by: a.module,
        select: {a.module, count()}
      )
      |> Repo.all()
      |> Map.new()

    tracked = @activity |> Enum.map(&elem(&1, 2)) |> MapSet.new()

    Map.new(TeacherAssistant.Modules.keys(), fn key ->
      {key, if(key in tracked, do: Map.get(used, Atom.to_string(key), 0))}
    end)
  end

  defp last_activity(workspace_id) do
    @activity
    |> Enum.map(fn {table, _actor, _module} ->
      Repo.one(
        from(r in table,
          where: r.workspace_id == type(^workspace_id, :binary_id),
          select: max(r.inserted_at)
        )
      )
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_datetime/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp count(query), do: Repo.aggregate(query, :count)

  defp filter_q(query, ""), do: query

  defp filter_q(query, q) do
    like = "%#{q}%"
    Ash.Query.filter(query, ilike(workspace.name, ^like) or ilike(town, ^like))
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: Ash.Query.filter(query, verification_status == ^status)

  defp suspended_matches?(_ws, nil), do: true
  defp suspended_matches?(ws, true), do: ws.suspended_at != nil
  defp suspended_matches?(ws, false), do: ws.suspended_at == nil

  defp ensure_operator!(%Scope{current_user: %User{role: :admin}}), do: :ok
  defp ensure_operator!(_scope), do: raise(Ash.Error.Forbidden.exception([]))
end
