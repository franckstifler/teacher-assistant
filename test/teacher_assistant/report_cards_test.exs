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

  test "a phone-only form master carries their phone, and no empty email", ctx do
    %{scope: scope, cg: cg, term: term} = ctx

    {:ok, %{user: fm}} =
      TeacherAssistant.Accounts.add_member_by_phone(scope, %{
        name: "Prof Tél",
        phone: "677123456",
        roles: [:teacher]
      })

    {:ok, cg} = Enrollment.set_form_master(scope, cg, fm.id)

    {:draft, view} = ReportCards.class_view(scope, cg, {:trimester, term})
    assert %{name: "Prof Tél", email: nil, phone: "+237677123456"} = view.form_master

    assert TeacherAssistant.Accounts.User.display_name(%{view.form_master | name: nil}) ==
             TeacherAssistant.Accounts.Phone.format("+237677123456")
  end

  test "publishing notifies the form master and the class's teachers, not the publisher", ctx do
    %{scope: scope, cg: cg, term: term} = ctx
    fm = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    t = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, cg} = Enrollment.set_form_master(scope, cg, fm.current_user.id)

    {:ok, _} =
      Curriculum.assign_teacher(scope, cg, t.current_user, %{
        subject: "SVT",
        coefficient: Decimal.new(2)
      })

    {:ok, _} = TeacherFixtures.publish_trimester(scope, cg, term)

    kinds = fn s ->
      s |> TeacherAssistant.Notifications.inbox(1) |> Map.get(:results) |> Enum.map(& &1.kind)
    end

    assert :bulletins_published in kinds.(fm)
    assert :bulletins_published in kinds.(t)
    refute :bulletins_published in kinds.(scope)

    [n] = fm |> TeacherAssistant.Notifications.inbox(1) |> Map.get(:results)
    assert n.params["class"] == "6e P"
    assert n.params["period_kind"] == "trimester"
    assert n.params["position"] == "1"
    assert n.link == "/school/bulletins?class=#{cg.id}&period=trim:#{term.id}"
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

  test "publish checklist: notes, conduct, council", ctx do
    %{scope: scope, cg: cg, term: term} = ctx
    checks = ReportCards.publish_checklist(scope, cg, {:trimester, term})

    assert [
             %{key: :notes, ok?: false, data: %{rate: rate, unassigned: _}},
             %{key: :conduct, ok?: false, data: %{entered: 0, effectif: 1}},
             %{key: :form_master, ok?: false},
             %{key: :council, ok?: false, data: %{status: :to_plan}},
             %{key: :paper_roll_calls, ok?: true, data: %{count: 0}},
             %{key: :page_fit, ok?: true, data: %{subjects: 1}}
           ] = checks

    assert rate < 100

    {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:trimester, term})
    {:ok, cg} = Enrollment.set_form_master(scope, cg, scope.current_user.id)

    assert [
             _,
             _,
             %{key: :form_master, ok?: true},
             %{key: :council, ok?: true, data: %{status: :held}},
             _,
             _
           ] =
             ReportCards.publish_checklist(scope, cg, {:trimester, term})
  end

  describe "readiness (bulletins overview)" do
    test "every class's steps for a trimester, from batched reads", ctx do
      %{scope: scope, cg: cg, term: term, year: year} = ctx
      {:ok, empty} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
      period = {:trimester, term}

      rows = ReportCards.readiness(scope, period)
      row = Enum.find(rows, &(&1.class_group.id == cg.id))

      assert row.students == 1
      assert row.rate < 100
      assert row.conduct == %{entered: 0, effectif: 1}
      refute row.form_master?
      assert row.council == :to_plan
      refute row.published?
      assert :notes in row.steps
      assert :conduct in row.steps
      assert :form_master in row.steps
      assert :council in row.steps
      refute row.ready?
      assert Enum.any?(rows, &(&1.class_group.id == empty.id))
    end

    test "a class with its marks, conduct, PP and council done; publish_many keeps the guards",
         ctx do
      %{scope: scope, cg: cg, a: a, st: st, year: year} = ctx
      TeacherAssistant.MarksFixtures.start_sequences!(scope, year)
      [term | _] = Organization.list_terms(scope, year)
      period = {:trimester, term}

      # every séquence of the term entered, conduct written, PP and council done
      for seq <- tl(term.sequences) do
        [tc] = Curriculum.list_assignments_for_class(scope, cg)

        {:ok, a2} =
          Assessment.create_assessment(scope, tc, seq, %{label: "D", max_score: Decimal.new(20)})

        :ok = Assessment.upsert_marks(scope, a2, [%{student_id: st.id, score: Decimal.new(12)}])
      end

      _ = a
      [%{enrollment: e}] = Enrollment.list_roster(scope, cg)

      for seq <- term.sequences,
          do:
            {:ok, _} =
              TeacherAssistant.Discipline.set_conduct_mark(scope, e, seq, Decimal.new(15))

      {:ok, cg} = Enrollment.set_form_master(scope, cg, scope.current_user.id)
      {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, period)

      row = scope |> ReportCards.readiness(period) |> Enum.find(&(&1.class_group.id == cg.id))
      assert row.rate == 100
      assert row.conduct == %{entered: 1, effectif: 1}
      assert row.form_master?
      assert row.council == :held
      # the coefficient grid still expects subjects without a teacher in 6ème
      assert row.unassigned > 0
      assert row.steps == [:notes]
      refute row.ready?

      assert %{published: 1, failed: []} = ReportCards.publish_many(scope, [cg], period)
      row = scope |> ReportCards.readiness(period) |> Enum.find(&(&1.class_group.id == cg.id))
      assert row.published?
      # publishing again keeps the guard
      assert %{published: 0, failed: [{_, :already_published}]} =
               ReportCards.publish_many(scope, [cg], period)
    end
  end

  test "a séquence is never publishable", %{scope: scope, cg: cg, seq: seq} do
    assert {:error, :not_publishable} = ReportCards.publish(scope, cg, {:sequence, seq})
  end

  describe "class council (I3)" do
    test "publishing a trimester or the year needs its held council", ctx do
      %{scope: scope, cg: cg, term: term, year: year} = ctx
      assert {:error, :council_not_held} = ReportCards.publish(scope, cg, {:trimester, term})
      {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:trimester, term})
      assert {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
      assert pub.snapshot_version == 5
      assert {:error, :council_not_held} = ReportCards.publish(scope, cg, {:annual, year})
      {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:annual, year})
      assert {:ok, annual} = ReportCards.publish(scope, cg, {:annual, year})
      [%{student: %{id: id}}] = annual.snapshot.roster
      assert annual.snapshot.council.outcomes[id].passage == :admis
    end

    test "the snapshot freezes the student's photo path (v4)", ctx do
      %{scope: scope, cg: cg, term: term, st: st} = ctx
      tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
      File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
      {:ok, with_photo} = TeacherAssistant.StudentPhotos.store(scope, st, tmp)
      {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:trimester, term})
      {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})

      assert [%{student: %{photo_path: path}}] = pub.snapshot.roster
      assert path == with_photo.photo_path
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

      # A3: the history carries no snapshot; load it to read the frozen council.
      assert [current, old] =
               scope
               |> ReportCards.history(cg, {:trimester, term})
               |> Ash.load!(:snapshot, scope: scope)

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

    # Queries run by this process during `fun` whose SQL mentions `needle` (A3).
    defp count_queries(needle, fun) do
      parent = self()
      counter = :counters.new(1, [])
      handler = {__MODULE__, needle, make_ref()}

      :telemetry.attach(
        handler,
        [:teacher_assistant, :repo, :query],
        fn _e, _m, %{query: q}, _ ->
          if self() == parent and q =~ needle, do: :counters.add(counter, 1, 1)
        end,
        nil
      )

      result = fun.()
      :telemetry.detach(handler)
      {result, :counters.get(counter, 1)}
    end

    test "status checks never read the snapshot column (A3)", ctx do
      %{scope: scope, cg: cg, term: term} = ctx
      period = {:trimester, term}
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      {ids, n1} =
        count_queries(~s("snapshot"), fn -> ReportCards.published_class_ids(scope, period) end)

      {pub, n2} =
        count_queries(~s("snapshot"), fn -> ReportCards.current_publication(scope, cg, period) end)

      {history, n3} =
        count_queries(~s("snapshot"), fn -> ReportCards.history(scope, cg, period) end)

      assert ids == MapSet.new([cg.id])
      assert %{status: :published, snapshot: %Ash.NotLoaded{}} = pub
      assert [%{snapshot: %Ash.NotLoaded{}}] = history
      assert {n1, n2, n3} == {0, 0, 0}
    end

    test "current_publication with snapshot: true returns the frozen view (A3)", ctx do
      %{scope: scope, cg: cg, term: term} = ctx
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      pub = ReportCards.current_publication(scope, cg, {:trimester, term}, snapshot: true)
      assert %{results: %{per_student: _}} = pub.snapshot

      assert {:published, _, %{results: _}} =
               ReportCards.class_view(scope, cg, {:trimester, term})
    end

    test "withdraw then republish: current is the new one, history has both (A3)", ctx do
      %{scope: scope, cg: cg, term: term} = ctx
      period = {:trimester, term}
      {:ok, first} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      {:ok, _} = ReportCards.withdraw(scope, first, "erreur")
      assert nil == ReportCards.current_publication(scope, cg, period)
      {:ok, second} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      assert ReportCards.current_publication(scope, cg, period).id == second.id
      assert length(ReportCards.history(scope, cg, period)) == 2
    end

    test "published_class_ids lists the published classes of a period", ctx do
      %{scope: scope, cg: cg, term: term} = ctx
      assert ReportCards.published_class_ids(scope, {:trimester, term}) == MapSet.new()
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      assert ReportCards.published_class_ids(scope, {:trimester, term}) == MapSet.new([cg.id])
    end
  end

  describe "template (spec I5)" do
    test "a published card keeps the template it was issued with", %{scope: scope, cg: cg} do
      term =
        scope |> TeacherAssistant.Organization.list_terms(scope.current_academic_year) |> hd()

      {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      assert pub.snapshot_version == 5
      assert %{language: :fr, elements: elements} = pub.snapshot.template
      assert :rank in elements

      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "bilingual",
          "elements" => ["qr_code"]
        })

      {:published, pub, view} =
        TeacherAssistant.ReportCards.class_view(scope, cg, {:trimester, term})

      assert %{language: :fr} = TeacherAssistant.ReportCards.template_of(scope, cg, view)
      assert pub.snapshot.template.elements == elements

      [_, term2 | _] =
        TeacherAssistant.Organization.list_terms(scope, scope.current_academic_year)

      {:draft, draft} = TeacherAssistant.ReportCards.class_view(scope, cg, {:trimester, term2})
      assert %{language: :bilingual, elements: [:qr_code]} = draft.template
    end

    test "a snapshot from before I5 renders with the current settings", %{scope: scope, cg: cg} do
      old_view = %{results: nil, roster: []}
      assert %{language: :fr} = TeacherAssistant.ReportCards.template_of(scope, cg, old_view)
    end
  end

  describe "latest_published_result/2" do
    test "nothing before a publication, then the trimester, then the year", ctx do
      %{scope: scope, cg: cg, term: term, year: year, st: st} = ctx
      [enrollment] = Enrollment.student_history(scope, st)

      assert ReportCards.latest_published_result(scope, enrollment) == nil

      {:ok, _} = TeacherFixtures.publish_trimester(scope, cg, term)

      assert %{period: {:trimester, %{id: term_id}}, average: average, rank: 1, effectif: 1} =
               ReportCards.latest_published_result(scope, enrollment)

      assert term_id == term.id
      assert Decimal.equal?(average, 15)

      {:ok, _} = TeacherFixtures.publish_annual(scope, cg, year)

      assert %{period: :annual, rank: 1} =
               ReportCards.latest_published_result(scope, enrollment)
    end
  end

  describe "head_name/1 (bulletin v2)" do
    test "prefers the profile's head_name, else the member holding the head role" do
      %{scope: scope} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

      assert ReportCards.head_name(scope) ==
               TeacherAssistant.Accounts.User.display_name(scope.current_user)

      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

      {:ok, _} =
        profile
        |> Ash.Changeset.for_update(:update, %{head_name: "M. Ndenge"}, scope: scope)
        |> Ash.update()

      assert ReportCards.head_name(scope) == "M. Ndenge"
    end
  end

  describe "snapshot data (bulletin v2)" do
    defp tc_of(scope, a) do
      {:ok, tc} = Curriculum.get_teaching_context(scope, a.teaching_context_id)
      tc
    end

    defp terms(scope, year), do: Organization.list_terms(scope, year)

    defp entry(view), do: hd(view.roster)

    test "snapshot carries guardians, national ID and competences", %{
      scope: scope,
      cg: cg,
      term: term,
      seq: seq,
      a: a,
      st: st
    } do
      st
      |> Ash.Changeset.for_update(:update, %{national_id: "241592812"}, scope: scope)
      |> Ash.update!()

      for {name, phone} <- [
            {"Mme Mbarga", "677123456"},
            {"M. Mbarga", "699001122"},
            {"Tante", "650000000"}
          ] do
        {:ok, _} =
          Enrollment.add_guardian(scope, st, %{
            full_name: name,
            phone: phone,
            relationship: :tuteur
          })
      end

      :ok = Assessment.put_sequence_competence(scope, tc_of(scope, a), seq, "Lire une carte")

      view = ReportCards.live_view(scope, cg, {:trimester, term})

      assert entry(view).student.national_id == "241592812"

      assert [%{name: "Mme Mbarga", phone: "677123456"}, %{name: "M. Mbarga"}] =
               entry(view).guardians

      assert view.sequences_per_term == 2

      assert [%{position: 1, number: 1, text: "Lire une carte"}, %{position: 2, text: nil}] =
               view.competences[a.teaching_context_id]
    end

    test "term 2 view carries term 1 average and rank, from term 1's publication when published",
         %{
           scope: scope,
           year: year,
           cg: cg,
           term: term,
           a: a,
           st: st
         } do
      {:ok, _} = TeacherFixtures.publish_trimester(scope, cg, term)
      :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new(5)}])

      [_t1, t2 | _] = terms(scope, year)
      view = ReportCards.live_view(scope, cg, {:trimester, t2})

      assert [%{position: 1, average: avg, rank: 1}] = view.prior_terms[st.id]
      assert Decimal.equal?(avg, Decimal.new(15))
    end

    test "prior_terms falls back to live results when the earlier term is unpublished", %{
      scope: scope,
      year: year,
      cg: cg,
      a: a,
      st: st
    } do
      :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new(5)}])
      [_t1, t2 | _] = terms(scope, year)

      assert [%{position: 1, average: avg}] =
               ReportCards.live_view(scope, cg, {:trimester, t2}).prior_terms[st.id]

      assert Decimal.equal?(avg, Decimal.new(5))

      assert ReportCards.live_view(scope, cg, {:trimester, hd(terms(scope, year))}).prior_terms ==
               %{}
    end

    test "annual summary only on the last term and only with the element", %{
      scope: scope,
      year: year,
      cg: cg,
      st: st
    } do
      [_t1, t2, t3] = terms(scope, year)
      assert ReportCards.last_term?(scope, t3)
      refute ReportCards.last_term?(scope, t2)

      view = ReportCards.live_view(scope, cg, {:trimester, t3})
      assert %{per_student: %{} = per_student, council: %{held?: false}} = view.annual
      assert %{average: %Decimal{}, rank: 1} = per_student[st.id]
      assert ReportCards.live_view(scope, cg, {:trimester, t2}).annual == nil

      {:ok, _} =
        Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => ["rank", "previous_terms"]
        })

      assert ReportCards.live_view(scope, cg, {:trimester, t3}).annual == nil
    end

    test "published snapshot keeps the competence after it is edited", %{
      scope: scope,
      cg: cg,
      term: term,
      seq: seq,
      a: a
    } do
      tc = tc_of(scope, a)
      :ok = Assessment.put_sequence_competence(scope, tc, seq, "Avant")
      {:ok, _} = TeacherFixtures.publish_trimester(scope, cg, term)
      :ok = Assessment.put_sequence_competence(scope, tc, seq, "Après")

      {:published, _pub, snapshot} = ReportCards.class_view(scope, cg, {:trimester, term})
      assert [%{text: "Avant"} | _] = snapshot.competences[tc.id]
    end
  end

  describe "term 3 publication (bulletin v2)" do
    alias TeacherAssistant.Councils

    defp last_term(scope, year), do: scope |> Organization.list_terms(year) |> List.last()

    test "term 3 with annual summary refuses publishing before the annual council", %{
      scope: scope,
      year: year,
      cg: cg
    } do
      t3 = last_term(scope, year)
      {:ok, _} = Councils.hold(scope, cg, {:trimester, t3})

      assert {:error, :annual_council_not_held} = ReportCards.publish(scope, cg, {:trimester, t3})

      {:ok, _} = Councils.hold(scope, cg, {:annual, year})
      assert {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, t3})
      assert %{per_student: _} = pub.snapshot.annual
    end

    test "term 3 without annual summary publishes as today", %{scope: scope, year: year, cg: cg} do
      {:ok, _} =
        Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => ["rank"]
        })

      assert {:ok, _} = TeacherFixtures.publish_trimester(scope, cg, last_term(scope, year))
    end

    test "publishing term 3 with annual summary locks the annual council; withdrawing unlocks it",
         %{scope: scope, year: year, cg: cg, st: st} do
      t3 = last_term(scope, year)
      {:ok, _} = Councils.hold(scope, cg, {:annual, year})
      {:ok, pub} = TeacherFixtures.publish_trimester(scope, cg, t3)

      assert Councils.locked?(scope, cg, {:annual, year})

      assert {:error, :locked} =
               Councils.set_decision(scope, cg, {:annual, year}, st.id, %{
                 "passage_decision" => "redouble"
               })

      {:ok, _} = ReportCards.withdraw(scope, pub, "Erreur de saisie")
      refute Councils.locked?(scope, cg, {:annual, year})

      assert {:ok, _} =
               Councils.set_decision(scope, cg, {:annual, year}, st.id, %{
                 "passage_decision" => "redouble"
               })
    end

    test "checklist lists missing competences and page fit", %{
      scope: scope,
      year: year,
      cg: cg,
      term: term
    } do
      {:ok, _} =
        Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => ["apc", "rank"]
        })

      checks = ReportCards.publish_checklist(scope, cg, {:trimester, term})

      assert %{ok?: false, data: %{missing: ["Maths"]}} =
               Enum.find(checks, &(&1.key == :competences))

      assert %{ok?: true} = Enum.find(checks, &(&1.key == :page_fit))
      refute Enum.find(checks, &(&1.key == :annual_council))

      t3 = last_term(scope, year)

      {:ok, _} =
        Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => ["annual_summary"]
        })

      checks = ReportCards.publish_checklist(scope, cg, {:trimester, t3})
      assert %{ok?: false} = Enum.find(checks, &(&1.key == :annual_council))
      refute Enum.find(checks, &(&1.key == :competences))
    end
  end
end
