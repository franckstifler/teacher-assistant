defmodule TeacherAssistant.Academics.TeacherMVPTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Academics

  test "ensures one personal workspace per teacher" do
    user = user_fixture()

    first = Accounts.ensure_personal_workspace!(user)
    second = Accounts.ensure_personal_workspace!(user)

    assert first.id == second.id
    assert first.owner_user_id == user.id
    assert first.name == "Personal workspace"
  end

  test "creates and selects a simple personal academic year" do
    user = user_fixture()
    workspace = Accounts.ensure_personal_workspace!(user)

    assert {:ok, year} =
             Academics.create_academic_year(workspace, %{
               name: "2026-2027",
               start_date: ~D[2026-09-01],
               end_date: ~D[2027-06-30],
               active: true
             })

    assert year.active
    assert Academics.current_academic_year(workspace).id == year.id
  end

  test "creates class-subject personal classrooms and learners" do
    {_user, workspace, year} = academic_year_fixture()

    assert {:ok, classroom} =
             Academics.create_personal_classroom(workspace, year, %{
               class_label: "Form 3",
               subject: "Mathematics"
             })

    assert classroom.class_label == "Form 3"
    assert classroom.subject == "Mathematics"

    assert {:ok, learner} =
             Academics.create_learner(classroom, %{
               first_name: "Grace",
               last_name: "Nkom",
               identifier: "M-001"
             })

    assert learner.full_name == "Grace Nkom"
  end

  test "records roll call with duplicate-safe attendance records" do
    {_user, _workspace, _year, classroom} = classroom_fixture()
    learner = learner_fixture(classroom)

    assert {:ok, session} =
             Academics.create_attendance_session(classroom, %{
               date: ~D[2026-10-05],
               notes: "Monday morning"
             })

    assert {:ok, first_record} =
             Academics.record_attendance(session, learner, %{
               status: :absent,
               note: "No excuse"
             })

    assert {:ok, second_record} =
             Academics.record_attendance(session, learner, %{
               status: :excused,
               note: "Medical note"
             })

    assert first_record.id == second_record.id
    assert second_record.status == :excused
    assert second_record.note == "Medical note"
  end

  test "tracks planned lesson entries and taught logs" do
    {_user, _workspace, _year, classroom} = classroom_fixture()

    assert {:ok, plan} =
             Academics.create_lesson_plan_entry(classroom, %{
               title: "Linear equations",
               planned_on: ~D[2026-10-06],
               planned_hours: Decimal.new("2.0"),
               objectives: "Solve one-variable equations"
             })

    assert {:ok, log} =
             Academics.create_teaching_log_entry(plan, %{
               taught_on: ~D[2026-10-07],
               taught_hours: Decimal.new("1.5"),
               notes: "Completed examples, exercises next time"
             })

    assert log.lesson_plan_entry_id == plan.id
    assert log.taught_hours == Decimal.new("1.5")
  end
end
