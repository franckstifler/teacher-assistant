defmodule TeacherAssistant.TeacherFixtures do
  alias TeacherAssistant.{Accounts, Organization}

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

  def school_fixture(attrs \\ %{}) do
    user = attrs[:head_user] || user_fixture()
    name = attrs[:name] || "Lycée #{System.unique_integer([:positive])}"
    {:ok, workspace} = Organization.create_school(user, %{name: name})
    %{workspace: workspace, head_user: user}
  end

  @doc """
  Creates an active academic year for `workspace` and seeds its starter
  classes, so `TeacherAssistant.Scope.setup_complete?/1` is true for it.
  Requires `workspace` to already have a `SchoolProfile` (as
  `Organization.create_school/2` sets up) — `Seeding.seed_starter_classes/2`
  reads it to pick the class template.
  """
  def complete_school_setup!(workspace, attrs \\ %{}) do
    {:ok, year} =
      Organization.create_academic_year(workspace, %{
        name: attrs[:name] || "Année de référence",
        start_date: attrs[:start_date] || ~D[2025-09-08],
        end_date: attrs[:end_date] || ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(year)
    {:ok, _count} = TeacherAssistant.Academics.Seeding.seed_starter_classes(workspace, year)

    year
  end

  @doc """
  A school whose setup is already complete (active academic year + at least
  one class group), so it never hits the `:require_school_setup` gate.
  """
  def setup_complete_school_fixture(attrs \\ %{}) do
    %{workspace: ws, head_user: head} = school_fixture(attrs)
    year = complete_school_setup!(ws)
    %{workspace: ws, head_user: head, year: year}
  end

  def membership_fixture(workspace, attrs \\ %{}) do
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

  @doc """
  Invites, accepts and assigns a plain `:teacher` member to a class of
  `school`. When `attrs[:teacher]` is already a member of `workspace`, the
  existing membership is reused instead of inviting them again.
  """
  def school_teacher_fixture(workspace, head, attrs \\ %{}) do
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
        TeacherAssistant.Enrollment.list_class_groups(workspace, year) |> List.first()

    {:ok, tc} =
      TeacherAssistant.Curriculum.assign_teacher(class_group, teacher, %{
        subject: attrs[:subject] || "Maths"
      })

    %{teacher: teacher, membership: membership, class_group: class_group, teaching_context: tc}
  end

  @doc """
  A teaching context on `workspace`/`year` for a real member teacher and a real
  class group, via `Curriculum.assign_teacher/3`.
  """
  def assigned_context_fixture(workspace, year, attrs \\ %{}) do
    head =
      case Accounts.fetch_school_profile(workspace) do
        {:ok, profile} ->
          {:ok, u} = Accounts.get_user(profile.owner_user_id)
          u
      end

    teacher = attrs[:teacher] || member_teacher(workspace, head)
    class_group = attrs[:class_group] || new_class_group(workspace, year, attrs)

    {:ok, tc} =
      TeacherAssistant.Curriculum.assign_teacher(class_group, teacher, %{
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

  defp new_class_group(workspace, year, attrs) do
    {:ok, cg} =
      TeacherAssistant.Enrollment.create_class_group(workspace, year, %{
        label: "#{attrs[:level] || "3ème"} #{System.unique_integer([:positive])}",
        level: attrs[:level] || "3ème",
        serie: attrs[:serie]
      })

    cg
  end
end
