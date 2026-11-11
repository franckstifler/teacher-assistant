defmodule TeacherAssistant.Workers.AnonymiseDepartedStudentsTest do
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  alias TeacherAssistant.{Enrollment, TeacherFixtures}
  alias TeacherAssistant.Workers.AnonymiseDepartedStudents

  test "the weekly job anonymises every school's due students" do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e W", level: "6ème"})

    {:ok, %{enrollment: e, student: s}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, _} = Enrollment.leave(scope, e, %{departure_reason: :dropout, left_on: ~D[2022-01-10]})

    assert :ok = perform_job(AnonymiseDepartedStudents, %{})

    assert Ash.get!(TeacherAssistant.Academics.Student, s.id, scope: scope).full_name ==
             "Élève parti"
  end
end
