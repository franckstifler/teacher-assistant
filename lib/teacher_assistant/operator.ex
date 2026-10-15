defmodule TeacherAssistant.Operator do
  @moduledoc """
  Reads for the operator console (operator console spec §5). The operator spans every
  school, so each function first checks the actor is an operator, then reads without
  authorization: per school with its tenant, and platform totals as plain table
  counts (tenant-scoped resources refuse a read with no tenant). Never call these
  from a school screen.
  """
  require Ash.Query
  import Ecto.Query, only: [from: 2]

  alias TeacherAssistant.Academics.{ClassGroup, Enrollment, Workspace}
  alias TeacherAssistant.Accounts.{Phone, SchoolMembership, SchoolProfile, User}
  alias TeacherAssistant.{Repo, Scope}

  @read [authorize?: false]

  @doc "Schools by status, active members, enrolled students and the last 7 days' activity."
  def overview(%Scope{} = scope) do
    ensure_operator!(scope)
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)
    profiles = Ash.read!(SchoolProfile, @read)

    %{
      schools: %{
        unverified: Enum.count(profiles, &(&1.verification_status == :unverified)),
        verified: Enum.count(profiles, &(&1.verification_status == :verified)),
        rejected: Enum.count(profiles, &(&1.verification_status == :rejected)),
        suspended: Workspace |> Ash.Query.filter(not is_nil(suspended_at)) |> Ash.count!(@read)
      },
      members: count(from(m in "school_memberships", where: m.active == true)),
      students:
        count(
          from(e in "enrollments",
            join: y in "academic_years",
            on: y.id == e.academic_year_id,
            where: y.active == true
          )
        ),
      roll_calls_7d: count(from(a in "attendance_entries", where: a.inserted_at >= ^week_ago)),
      marks_7d: count(from(m in "mark_events", where: m.inserted_at >= ^week_ago))
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

  @doc "One school: workspace, profile, active members (with user), counts, last activity."
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
         last_activity: last_activity(ws.id)
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

  defp memberships_of(user) do
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user.id})
    |> Ash.read!(@read)
  end

  defp last_activity(workspace_id) do
    ["attendance_entries", "mark_events"]
    |> Enum.map(fn table ->
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
