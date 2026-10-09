defmodule TeacherAssistant.PilotageTest do
  use TeacherAssistant.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias TeacherAssistant.{Assessment, Councils, Curriculum, Enrollment, Organization, Pilotage}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.TeacherFixtures

  test "to-do facts" do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, cg} = Enrollment.create_class_group(head, year, %{label: "6e Z", level: "6ème"})
    todo = Pilotage.todo(%{head | current_academic_year: year})
    assert Enum.any?(todo.classes_without_pp, &(&1.id == cg.id))
    assert todo.pending_accounts.count >= 0
    assert todo.oldest_correction == nil
    assert todo.pending_corrections == 0
  end

  test "a form master takes the class off the list" do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    head = %{head | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(head, year, %{label: "6e Z", level: "6ème"})
    {:ok, _} = Enrollment.set_form_master(head, cg, head.current_user.id)

    refute Enum.any?(Pilotage.todo(head).classes_without_pp, &(&1.id == cg.id))
  end

  test "subjects without a teacher follow the coefficient grid" do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    head = %{head | current_academic_year: year}
    todo = Pilotage.todo(head)

    overview = Curriculum.assignment_overview(head)
    assert overview.to_assign > 0
    assert length(todo.unassigned) == overview.to_assign
    assert Enum.all?(todo.unassigned, &(is_binary(&1.class) and is_binary(&1.subject)))
  end

  test "accounts awaiting first sign-in, with the expired ones" do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    head = %{head | current_academic_year: year}

    for phone <- ["6 77 12 34 56", "6 77 12 34 57"] do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(
          :create_by_school,
          %{name: "Awa", phone: phone, created_in_workspace_id: head.current_workspace.id},
          scope: head
        )
        |> Ash.create()

      TeacherFixtures.membership_fixture(head, %{user: user})
      user
    end
    |> hd()
    |> then(fn user ->
      TeacherAssistant.Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [temporary_password_expires_at: DateTime.add(DateTime.utc_now(), -1, :day)]
      )
    end)

    assert Pilotage.todo(head).pending_accounts == %{count: 2, expired: 1}
  end

  test "councils to plan in the current term" do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    head = %{head | current_academic_year: year}
    classes = Enrollment.list_class_groups(head, year)
    assert Pilotage.todo(head).councils_to_plan == length(classes)

    term = Councils.default_term(Organization.list_terms(head, year), Reference.today())

    {:ok, _} =
      Councils.schedule(head, hd(classes), {:trimester, term}, ~D[2025-12-10], ~T[14:00:00])

    assert Pilotage.todo(head).councils_to_plan == length(classes) - 1
  end

  test "the oldest pending correction's date" do
    world = TeacherAssistant.MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    TeacherAssistant.MarksFixtures.lock!(world, Date.add(Reference.today(), -1))

    {:ok, c} =
      Assessment.request_correction(world.t, %{
        assessment_id: world.a.id,
        student_id: world.s1.id,
        requested_status: :graded,
        requested_score: Decimal.new(14),
        motive: :erreur_saisie
      })

    todo = Pilotage.todo(world.head)
    assert todo.pending_corrections == 1
    assert todo.oldest_correction == DateTime.to_date(c.inserted_at)
  end
end
