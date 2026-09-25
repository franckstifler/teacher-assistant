defmodule TeacherAssistant.TeacherFixtures do
  alias TeacherAssistant.{Accounts, Organization, Scope}
  import TeacherAssistant.DataCase, only: [school_scope: 2]

  def user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, "teacher-#{System.unique_integer([:positive])}@example.com")

    {:ok, user} =
      Accounts.create_user(%{
        email: email,
        password: Map.get(attrs, :password, "password1234"),
        password_confirmation: Map.get(attrs, :password_confirmation, "password1234")
      })

    user
  end

  def admin_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Accounts.promote_to_admin(user)
    admin
  end

  @doc "A new school created by `attrs[:head_user]` (or a fresh user), with the head's scope."
  def school_fixture(attrs \\ %{}) do
    user = attrs[:head_user] || user_fixture()
    name = attrs[:name] || "Lycée #{System.unique_integer([:positive])}"
    {:ok, workspace} = Organization.create_school(user, %{name: name})
    %{workspace: workspace, head_user: user, scope: school_scope(user, workspace)}
  end

  @doc """
  Creates an active academic year for the scope's school, builds its default
  calendar and seeds its starter classes, so `Scope.setup_complete?/1` is true.
  """
  def complete_school_setup!(%Scope{current_workspace: workspace} = scope, attrs \\ %{}) do
    {:ok, year} =
      Organization.create_academic_year(workspace, %{
        name: attrs[:name] || "Année de référence",
        start_date: attrs[:start_date] || ~D[2025-09-08],
        end_date: attrs[:end_date] || ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(year)
    {:ok, _count} = TeacherAssistant.Academics.Seeding.seed_starter_classes(scope, year)

    year
  end

  @doc "Verifies the scope's school as a fresh operator (the only role allowed to)."
  def verify_school!(%Scope{current_workspace: workspace}) do
    operator = admin_user_fixture()
    {:ok, profile} = Accounts.fetch_school_profile(workspace)
    {:ok, _} = Accounts.verify_school(profile, operator.id)
    :ok
  end

  @doc """
  A school whose setup is complete (active year + classes) and, unless
  `attrs[:verified]` is `false`, verified — ready to operate. `scope` is the
  head's scope, built after setup so it carries the year and the status.
  """
  def setup_complete_school_fixture(attrs \\ %{}) do
    %{workspace: ws, head_user: head, scope: scope} = school_fixture(attrs)
    year = complete_school_setup!(scope)
    if Map.get(attrs, :verified, true), do: verify_school!(scope)
    %{workspace: ws, head_user: head, year: year, scope: school_scope(head, ws)}
  end

  def membership_fixture(%Scope{current_workspace: workspace}, attrs \\ %{}) do
    user = attrs[:user] || user_fixture()
    roles = attrs[:roles] || [:teacher]

    {:ok, m} =
      Accounts.SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        roles: roles,
        status: attrs[:status],
        active: true
      })
      |> Ash.Changeset.set_tenant(workspace.id)
      |> Ash.create(authorize?: false)

    m
  end

  @doc "A fresh member of the scope's school with `attrs[:roles]` (default `[:teacher]`); returns their scope."
  def member_scope_fixture(%Scope{current_workspace: workspace} = scope, attrs \\ %{}) do
    user = attrs[:user] || user_fixture()
    membership_fixture(scope, Map.put(attrs, :user, user))
    school_scope(user, workspace)
  end

  @doc """
  Invites, accepts and assigns a plain `:teacher` member to a class of the
  scope's school (the scope acts as the inviting head). Reuses an existing
  membership when `attrs[:teacher]` already belongs to the school.
  """
  def school_teacher_fixture(
        %Scope{current_workspace: workspace, current_user: head} = scope,
        attrs \\ %{}
      ) do
    teacher = attrs[:teacher] || user_fixture()

    membership =
      case Accounts.fetch_school_membership(workspace, teacher) do
        {:ok, membership} ->
          membership

        {:error, _} ->
          {:ok, inv} =
            Accounts.invite_member(workspace, head, %{
              email: to_string(teacher.email),
              roles: [:teacher]
            })

          {:ok, _} = Accounts.accept_invitation(inv.token, teacher)
          {:ok, membership} = Accounts.fetch_school_membership(workspace, teacher)
          membership
      end

    year = Organization.current_academic_year(workspace)

    class_group =
      attrs[:class_group] ||
        TeacherAssistant.Enrollment.list_class_groups(scope, year) |> List.first()

    {:ok, tc} =
      TeacherAssistant.Curriculum.assign_teacher(scope, class_group, teacher, %{
        subject: attrs[:subject] || "Maths"
      })

    %{
      teacher: teacher,
      membership: membership,
      class_group: class_group,
      teaching_context: tc,
      scope: school_scope(teacher, workspace)
    }
  end

  @doc """
  A teaching context on the scope's school and `year` for a real member
  teacher and a real class group, via `Curriculum.assign_teacher/4`.
  """
  def assigned_context_fixture(
        %Scope{current_workspace: workspace, current_user: head} = scope,
        year,
        attrs \\ %{}
      ) do
    teacher = attrs[:teacher] || member_teacher(workspace, head)
    class_group = attrs[:class_group] || new_class_group(scope, year, attrs)

    {:ok, tc} =
      TeacherAssistant.Curriculum.assign_teacher(scope, class_group, teacher, %{
        subject: attrs[:subject] || "Maths",
        coefficient: attrs[:coefficient] || Decimal.new(1)
      })

    tc
  end

  # Invites, accepts and returns a fresh `:teacher` member of `workspace`.
  defp member_teacher(workspace, head) do
    u = user_fixture()

    {:ok, inv} =
      Accounts.invite_member(workspace, head, %{
        email: to_string(u.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(inv.token, u)
    u
  end

  defp new_class_group(%Scope{} = scope, year, attrs) do
    {:ok, cg} =
      TeacherAssistant.Enrollment.create_class_group(scope, year, %{
        label: "#{attrs[:level] || "3ème"} #{System.unique_integer([:positive])}",
        level: attrs[:level] || "3ème",
        serie: attrs[:serie]
      })

    cg
  end
end
