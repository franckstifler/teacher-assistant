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
    assert {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
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

    assert {:ok, republished} =
             TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

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
    assert {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
    assert {:error, :already_published} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:ok, annual} = TeacherAssistant.TeacherFixtures.publish_annual(scope, cg, year)
    assert annual.period_key == "annee"
    assert annual.term_id == nil
    assert length(ReportCards.history(scope, cg, {:trimester, term})) == 1
  end

  test "a withdrawal needs a reason", %{scope: scope, cg: cg, term: term} do
    {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
    assert {:error, %Ash.Error.Invalid{}} = ReportCards.withdraw(scope, pub, "   ")
    assert {:published, _, _} = ReportCards.class_view(scope, cg, {:trimester, term})
  end

  test "only the admin axis publishes and withdraws", %{scope: scope, cg: cg, term: term} do
    teacher_scope = TeacherFixtures.member_scope_fixture(scope)
    teacher_scope = %{teacher_scope | current_academic_year: scope.current_academic_year}

    {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:trimester, term})

    assert {:error, %Ash.Error.Forbidden{}} =
             ReportCards.publish(teacher_scope, cg, {:trimester, term})

    {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
    assert {:error, %Ash.Error.Forbidden{}} = ReportCards.withdraw(teacher_scope, pub, "Non")
  end

  test "published_on is the school-local date", %{scope: scope, cg: cg, term: term} do
    {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
    assert %Date{} = ReportCards.published_on(pub)

    assert ReportCards.published_on(%{pub | published_at: ~U[2026-01-10 23:30:00Z]}) ==
             ~D[2026-01-11]
  end

  test "a stale withdrawal is refused and leaves the history alone", %{
    scope: scope,
    cg: cg,
    term: term
  } do
    period = {:trimester, term}
    {:ok, pub} = TeacherFixtures.publish_trimester(scope, cg, term)
    {:ok, _} = ReportCards.withdraw(scope, pub, "First reason")

    # a second page still holding the published struct
    assert {:error, :not_published} = ReportCards.withdraw(scope, pub, "Second reason")

    assert [%{status: :withdrawn, withdrawal_reason: "First reason"}] =
             ReportCards.history(scope, cg, period)

    # republished meanwhile: the stale page must not report success on the old row
    {:ok, republished} = TeacherFixtures.publish_trimester(scope, cg, term)
    assert {:error, :not_published} = ReportCards.withdraw(scope, pub, "Stale")
    assert %{id: id} = ReportCards.current_publication(scope, cg, period)
    assert id == republished.id
  end

  describe "class council (I3)" do
    test "publishing a trimester or the year needs its held council", ctx do
      %{scope: scope, cg: cg, term: term, year: year} = ctx
      assert {:error, :council_not_held} = ReportCards.publish(scope, cg, {:trimester, term})
      {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:trimester, term})
      assert {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
      assert pub.snapshot_version == 2
      assert {:error, :council_not_held} = ReportCards.publish(scope, cg, {:annual, year})
      {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:annual, year})
      assert {:ok, annual} = ReportCards.publish(scope, cg, {:annual, year})
      [%{student: %{id: id}}] = annual.snapshot.roster
      assert annual.snapshot.council.outcomes[id].passage == :admis
    end

    test "the snapshot freezes the council", ctx do
      %{scope: scope, cg: cg, term: term, st: st} = ctx
      alias TeacherAssistant.Councils

      {:ok, _} =
        Councils.set_decision(scope, cg, {:trimester, term}, st.id, %{
          "distinction_choice" => "tableau_honneur",
          "appreciation" => "Bon trimestre"
        })

      {:ok, _} = Councils.hold(scope, cg, {:trimester, term})
      {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
      assert pub.snapshot.council.held?
      assert pub.snapshot.council.outcomes[st.id].distinction == :tableau_honneur
      assert {:error, :locked} = Councils.reopen(scope, cg, {:trimester, term})

      {:ok, _} = ReportCards.withdraw(scope, pub, "Appréciation à revoir")

      {:ok, _} =
        Councils.set_decision(scope, cg, {:trimester, term}, st.id, %{"appreciation" => "Nouveau"})

      {:ok, _} = ReportCards.publish(scope, cg, {:trimester, term})

      assert [current, old] = ReportCards.history(scope, cg, {:trimester, term})
      assert current.snapshot.council.outcomes[st.id].appreciation == "Nouveau"
      assert old.snapshot.council.outcomes[st.id].appreciation == "Bon trimestre"
    end

    test "final_distinction follows the council, else the computed one", ctx do
      %{scope: scope, cg: cg, term: term, seq: seq, st: st} = ctx

      {:ok, _} =
        TeacherAssistant.Councils.set_decision(scope, cg, {:trimester, term}, st.id, %{
          "distinction_choice" => "none"
        })

      {:draft, view} = ReportCards.class_view(scope, cg, {:trimester, term})
      data = view.results.per_student[st.id]
      assert data.distinction == :encouragements
      assert ReportCards.final_distinction(view, st.id, data) == nil

      {:draft, seq_view} = ReportCards.class_view(scope, cg, {:sequence, seq})
      assert seq_view.council == nil
      seq_data = seq_view.results.per_student[st.id]
      assert ReportCards.final_distinction(seq_view, st.id, seq_data) == seq_data.distinction
      assert ReportCards.outcome(Map.delete(view, :council), st.id) == nil
    end

    test "published_class_ids lists the published classes of a period", ctx do
      %{scope: scope, cg: cg, term: term} = ctx
      assert ReportCards.published_class_ids(scope, {:trimester, term}) == MapSet.new()
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      assert ReportCards.published_class_ids(scope, {:trimester, term}) == MapSet.new([cg.id])
    end
  end
end
