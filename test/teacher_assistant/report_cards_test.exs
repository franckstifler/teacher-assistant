defmodule TeacherAssistant.ReportCardsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    [term | _] = Organization.list_terms(scope, year)
    [seq | _] = term.sequences
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M1"})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(2)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: st}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new(15)}])

    %{scope: scope, year: year, term: term, seq: seq, cg: cg, a: a, st: st, head: head}
  end

  defp moyenne(%{results: r, roster: [%{student: %{id: id}} | _]}),
    do: r.per_student[id].moyenne_generale

  test "a draft is live; a séquence is always a draft", %{
    scope: scope,
    cg: cg,
    term: term,
    seq: seq
  } do
    assert {:draft, view} = ReportCards.class_view(scope, cg, {:trimester, term})

    assert [%{student: %{full_name: "Awa", matricule: "M1"}, enrollment: %{repeater: false}}] =
             view.roster

    assert Decimal.equal?(moyenne(view), 15)
    assert {:error, :not_publishable} = ReportCards.publish(scope, cg, {:sequence, seq})
    assert {:draft, _} = ReportCards.class_view(scope, cg, {:sequence, seq})
  end

  test "publishing freezes the report cards", ctx do
    %{scope: scope, cg: cg, term: term, a: a, st: st} = ctx
    assert {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert pub.status == :published
    assert pub.period_key == "trim:" <> term.id
    assert pub.published_by_user_id == scope.current_user.id

    # changes after publication: a mark, the averaging rounding, the appreciation scale
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new(4)}])
    {:ok, _} = Assessment.update_grading_rules(scope, %{"average_rounding" => "quarter"})

    {:ok, _} =
      Assessment.update_appreciation_bands(scope, [
        %{from: "0", label: "X"},
        %{from: "10", label: "Y"}
      ])

    assert {:published, %{id: pub_id}, view} =
             ReportCards.class_view(scope, cg, {:trimester, term})

    assert pub_id == pub.id
    assert Decimal.equal?(moyenne(view), 15)
    [%{student: %{id: id}}] = view.roster
    assert view.results.per_student[id].mention.label == "Bien"

    # withdraw + republish picks the change up
    assert {:ok, withdrawn} = ReportCards.withdraw(scope, pub, "Erreur de saisie en maths")
    assert withdrawn.status == :withdrawn
    assert withdrawn.withdrawal_reason == "Erreur de saisie en maths"
    assert {:draft, live} = ReportCards.class_view(scope, cg, {:trimester, term})
    assert Decimal.equal?(moyenne(live), 4)

    assert {:ok, republished} = ReportCards.publish(scope, cg, {:trimester, term})
    assert [first, second] = ReportCards.history(scope, cg, {:trimester, term})
    assert first.id == republished.id
    assert first.status == :published
    assert second.status == :withdrawn
  end

  test "publishing twice is refused; annual is its own period", %{
    scope: scope,
    cg: cg,
    term: term,
    year: year
  } do
    assert {:ok, _} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:error, :already_published} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:ok, annual} = ReportCards.publish(scope, cg, {:annual, year})
    assert annual.period_key == "annee"
    assert annual.term_id == nil
    assert length(ReportCards.history(scope, cg, {:trimester, term})) == 1
  end

  test "a withdrawal needs a reason", %{scope: scope, cg: cg, term: term} do
    {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:error, %Ash.Error.Invalid{}} = ReportCards.withdraw(scope, pub, "   ")
    assert {:published, _, _} = ReportCards.class_view(scope, cg, {:trimester, term})
  end

  test "only the admin axis publishes and withdraws", %{scope: scope, cg: cg, term: term} do
    teacher_scope = TeacherFixtures.member_scope_fixture(scope)
    teacher_scope = %{teacher_scope | current_academic_year: scope.current_academic_year}

    assert {:error, %Ash.Error.Forbidden{}} =
             ReportCards.publish(teacher_scope, cg, {:trimester, term})

    {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:error, %Ash.Error.Forbidden{}} = ReportCards.withdraw(teacher_scope, pub, "Non")
  end

  test "published_on is the school-local date", %{scope: scope, cg: cg, term: term} do
    {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert %Date{} = ReportCards.published_on(pub)

    assert ReportCards.published_on(%{pub | published_at: ~U[2026-01-10 23:30:00Z]}) ==
             ~D[2026-01-11]
  end
end
