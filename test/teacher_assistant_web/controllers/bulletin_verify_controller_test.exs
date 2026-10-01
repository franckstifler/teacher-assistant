defmodule TeacherAssistantWeb.BulletinVerifyControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistantWeb.BulletinVerification

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture(%{name: "Lycée Vérif"})
    :ok = TeacherFixtures.verify_school!(scope)
    TeacherFixtures.complete_school_setup!(scope)
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    [term | _] = Organization.list_terms(scope, year)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e V", level: "3ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, scope.current_user, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{label: "D1", weight: Decimal.new(1), max_score: Decimal.new(20)})

    [%{student: student}] = Enrollment.list_roster(scope, cg)
    Assessment.upsert_marks(scope, a, [%{student_id: student.id, score: Decimal.new(12)}])
    {:ok, pub} = TeacherFixtures.publish_trimester(scope, cg, term)
    %{scope: scope, cg: cg, term: term, pub: pub, student: student}
  end

  test "a published card is authentic, without logging in", %{pub: pub, student: student} do
    html = build_conn() |> get(~p"/verify/bulletin/#{BulletinVerification.token(pub, student.id)}") |> html_response(200)
    assert html =~ "Bulletin authentique"
    assert html =~ "Awa Ngo"
    assert html =~ "Lycée Vérif"
    assert html =~ "3e V"
    refute html =~ "Maths"
  end

  test "withdrawn then republished: the old code says withdrawn, the new one authentic",
       %{scope: scope, cg: cg, term: term, pub: pub, student: student} do
    {:ok, _} = ReportCards.withdraw(scope, pub, "Erreur de saisie")
    {:ok, new_pub} = ReportCards.publish(scope, cg, {:trimester, term})

    old = build_conn() |> get(~p"/verify/bulletin/#{BulletinVerification.token(pub, student.id)}") |> html_response(200)
    assert old =~ "Ce bulletin a été retiré"
    refute old =~ "Erreur de saisie"

    new = build_conn() |> get(~p"/verify/bulletin/#{BulletinVerification.token(new_pub, student.id)}") |> html_response(200)
    assert new =~ "Bulletin authentique"
  end

  test "tampered, foreign-school and wrong-student tokens are invalid", %{pub: pub, student: student} do
    invalid = fn token ->
      build_conn() |> get(~p"/verify/bulletin/#{token}") |> html_response(200) =~ "Lien de vérification invalide"
    end

    assert invalid.(BulletinVerification.token(pub, student.id) <> "x")
    assert invalid.("not-a-token")

    %{workspace: other} = TeacherFixtures.school_fixture()
    foreign = Phoenix.Token.sign(TeacherAssistantWeb.Endpoint, "bulletin-verify", {other.id, pub.id, student.id})
    assert invalid.(foreign)

    assert invalid.(BulletinVerification.token(pub, Ecto.UUID.generate()))
  end
end
