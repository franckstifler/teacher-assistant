defmodule TeacherAssistantWeb.BulletinPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Discipline
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Print"
      })

    scope = school_scope(head, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})

    {:ok, _} =
      Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f, matricule: "M-1"})

    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob Eyong", sex: :m})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    roster = Enrollment.list_roster(scope, cg)

    for %{student: s} <- roster,
        do: Assessment.upsert_marks(scope, a, [%{student_id: s.id, score: Decimal.new(14)}])

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, roster: roster, head: head, scope: scope}
  end

  test "single bulletin print shows the school and the student", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster
  } do
    %{enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))

    conn =
      get(
        conn,
        ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}"
      )

    body = html_response(conn, 200)
    assert body =~ "Lycée Print"
    assert body =~ "Awa Ngo"
    assert body =~ "Maths"
    # 14/20: appreciation "Bien", moyenne 14 earns Encouragements
    assert body =~ "Appréciation"
    assert body =~ "Bien"
    assert body =~ "Encouragements"
  end

  test "single bulletin print shows the conduct figures", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster,
    scope: scope
  } do
    %{enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))

    :ok = Attendance.build_default_periods(scope)
    [tc] = Curriculum.list_assignments_for_class(scope, cg)
    [period1, period2 | _] = Attendance.list_periods(scope) |> Enum.filter(&(&1.kind == :lesson))

    {:ok, slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period1.id,
        teaching_context_id: tc.id
      })

    _ = slot
    date = seq.start_date

    {:ok, _} =
      Attendance.record_period(scope, cg, period1, tc, date, [{enr.id, :absent}])

    {:ok, _} = Attendance.justify_day(scope, enr, date, :maladie, "Certificat médical")

    {:ok, _} =
      Attendance.record_period(scope, cg, period2, tc, date, [{enr.id, :late}])

    conn =
      get(
        conn,
        ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}"
      )

    body = html_response(conn, 200)
    assert body =~ "Assiduité"
    assert body =~ "Absences justifiées"
    assert body =~ "Absences non justifiées"
    assert body =~ "Retards"
  end

  test "single bulletin print shows the sanctions, consignes and note de conduite figures", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster,
    scope: scope
  } do
    %{enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))
    date = seq.start_date

    {:ok, _} =
      Discipline.add_sanction(scope, enr, %{type: :consigne, date: date, reason: "Bavardage"})

    {:ok, _} =
      Discipline.add_sanction(
        scope,
        enr,
        %{type: :avertissement, date: date, reason: "Retards répétés"}
      )

    {:ok, _} =
      Discipline.add_sanction(
        scope,
        enr,
        %{type: :exclusion_temporaire, date: date, duration_days: 3, reason: "Bagarre"}
      )

    {:ok, _} = Discipline.set_conduct_mark(scope, enr, seq, 14)

    conn =
      get(
        conn,
        ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}"
      )

    body = html_response(conn, 200)
    assert body =~ "Consignes"
    assert body =~ "Avertissement"
    assert body =~ "Exclusion temporaire"
    assert body =~ "3 j"
    assert body =~ "Note de conduite"
    assert body =~ "14"
  end

  test "whole-class print includes every enrolled student", %{conn: conn, cg: cg, seq: seq} do
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    body = html_response(conn, 200)
    assert body =~ "Awa Ngo"
    assert body =~ "Bob Eyong"
  end

  test "a non-admin member is redirected", %{school: school, cg: cg, seq: seq, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    assert redirected_to(conn) == "/school"
  end

  test "the form master can print their class", %{
    cg: cg,
    seq: seq,
    head: head,
    school: school,
    scope: scope
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(fm.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: fm}, inv.token)
    {:ok, _} = Enrollment.set_form_master(scope, cg, fm.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, fm.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    assert html_response(conn, 200) =~ "Awa Ngo"
  end

  test "the bulletin names the form master when set", %{
    conn: conn,
    cg: cg,
    seq: seq,
    head: head,
    scope: scope
  } do
    {:ok, _} = Enrollment.set_form_master(scope, cg, head.id)
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    assert html_response(conn, 200) =~ to_string(head.email)
  end

  test "the whole-class print renders a trimester with séquence columns", %{
    conn: conn,
    cg: cg,
    seq: seq,
    scope: scope
  } do
    year = TeacherAssistant.Organization.current_academic_year(scope)
    [_s1, s2 | _] = TeacherAssistant.Organization.list_sequences(scope, year)
    [term1 | _] = TeacherAssistant.Organization.list_terms(scope, year)
    _ = seq

    [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)

    {:ok, a2} =
      TeacherAssistant.Assessment.create_assessment(scope, tc, s2, %{
        label: "D2",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    for %{student: s} <- TeacherAssistant.Enrollment.list_roster(scope, cg),
        do:
          TeacherAssistant.Assessment.upsert_marks(scope, a2, [
            %{student_id: s.id, score: Decimal.new(15)}
          ])

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term1.id}")
    body = html_response(conn, 200)
    assert body =~ "Trimestre 1"
    assert body =~ "Séq 1"
    assert body =~ "Awa Ngo"
  end

  test "the whole-class print renders the annual period with trimester columns", %{
    conn: conn,
    cg: cg
  } do
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=annee")
    body = html_response(conn, 200)
    assert body =~ "Trim 1"
    assert body =~ "Moy. ann."
    assert body =~ "Awa Ngo"
  end

  test "an unverified school cannot print bulletins", %{conn: conn} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Non Vérifié"
      })

    unverified_scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(unverified_scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(unverified_scope, year)
    [seq | _] = Organization.list_sequences(unverified_scope, year)

    {:ok, cg} =
      Enrollment.create_class_group(unverified_scope, year, %{label: "6e A", level: "6ème"})

    {:ok, _} = Enrollment.add_student(unverified_scope, cg, %{full_name: "Awa Ngo", sex: :f})

    conn =
      conn
      |> Plug.Conn.put_session(:user_id, head.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    assert redirected_to(conn) == "/school"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "vérification"
  end

  test "print lists subjects under their bulletin group; subtotals only when enabled", %{
    conn: conn,
    cg: cg,
    seq: seq,
    scope: scope
  } do
    path = ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}"
    html = conn |> get(path) |> html_response(200)
    assert html =~ "Groupe 3 · Autres"
    refute html =~ "Total groupe"

    {:ok, _} = Curriculum.set_bulletin_group_subtotals(scope, true)
    assert conn |> get(path) |> html_response(200) =~ "Total groupe"
  end

  defp with_year(scope) do
    %{scope | current_academic_year: TeacherAssistant.Organization.current_academic_year(scope)}
  end

  defp teacher_conn(scope, cg) do
    %{teacher: teacher} =
      TeacherAssistant.TeacherFixtures.school_teacher_fixture(scope, %{
        class_group: cg,
        subject: "SVT"
      })

    build_conn()
    |> log_in_user(teacher)
    |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)
  end

  defp first_term(scope),
    do: scope |> TeacherAssistant.Organization.list_terms(scope.current_academic_year) |> hd()

  describe "publication" do
    test "a draft trimester prints with the BROUILLON watermark; a published one with its date",
         %{conn: conn, cg: cg, scope: scope} do
      scope = with_year(scope)
      term = first_term(scope)
      url = ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}"

      assert conn |> get(url) |> html_response(200) =~ "BROUILLON"

      {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      html = conn |> get(url) |> html_response(200)
      refute html =~ "BROUILLON"
      assert html =~ Calendar.strftime(TeacherAssistant.ReportCards.published_on(pub), "%d/%m/%Y")
    end

    test "a séquence print has no watermark", %{conn: conn, cg: cg, seq: seq} do
      html =
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
        |> html_response(200)

      refute html =~ "BROUILLON"
    end

    test "a teacher cannot print an unpublished period", %{cg: cg, scope: scope} do
      scope = with_year(scope)
      term = first_term(scope)
      tconn = teacher_conn(scope, cg)
      conn = get(tconn, ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}")

      assert URI.decode(redirected_to(conn)) ==
               "/school/classes/#{cg.id}/results?period=trim:#{term.id}"
    end
  end

  describe "class council (I3)" do
    test "a trimester print carries the council's appreciation", %{
      conn: conn,
      cg: cg,
      scope: scope,
      roster: roster
    } do
      scope = with_year(scope)
      term = first_term(scope)
      [%{student: st} | _] = roster

      {:ok, _} =
        TeacherAssistant.Councils.set_decision(scope, cg, {:trimester, term}, st.id, %{
          "appreciation" => "Très bon trimestre"
        })

      html =
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}")
        |> html_response(200)

      assert html =~ "Très bon trimestre"
    end
  end

  describe "passage (I4)" do
    test "the annual print fills the Décision slot", %{conn: conn, cg: cg} do
      html =
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=annee")
        |> html_response(200)

      assert html =~ ~s(class="decision")
      assert html =~ "Admis"
    end
  end

  describe "template (spec I5)" do
    defp print(conn, cg, seq),
      do:
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
        |> html_response(200)

    test "a francophone class prints in French with the official header", %{
      conn: conn,
      cg: cg,
      seq: seq,
      scope: scope
    } do
      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

      {:ok, _} =
        TeacherAssistant.Accounts.update_school_profile(
          profile,
          %{region: :littoral, department: "Wouri", motto: "Discipline – Travail"},
          scope: scope
        )

      html = print(conn, cg, seq)
      assert html =~ ~s(<html lang="fr">)
      assert html =~ "République du Cameroun"
      assert html =~ "Ministère des Enseignements secondaires"
      assert html =~ "Délégation régionale des Enseignements secondaires du Littoral"
      assert html =~ "Wouri"
      assert html =~ "Discipline – Travail"
      assert html =~ "Matière"
      refute html =~ "Subject"
    end

    test "an anglophone class prints in English with grades", %{
      conn: conn,
      scope: scope,
      seq: seq
    } do
      {:ok, en} =
        TeacherAssistant.Enrollment.create_class_group(
          scope,
          scope.current_academic_year ||
            TeacherAssistant.Organization.current_academic_year(scope),
          %{
            label: "Form 1 A",
            level: "Form 1",
            subsystem: :anglophone
          }
        )

      {:ok, _} =
        TeacherAssistant.Enrollment.add_student(scope, en, %{full_name: "Ngum Che", sex: :f})

      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, en, scope.current_user, %{
          subject: "Biology",
          coefficient: Decimal.new(2)
        })

      {:ok, a} =
        TeacherAssistant.Assessment.create_assessment(scope, tc, seq, %{
          label: "T1",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(scope, en)

      TeacherAssistant.Assessment.upsert_marks(scope, a, [
        %{student_id: s.id, score: Decimal.new(15)}
      ])

      html = print(conn, en, seq)
      assert html =~ ~s(<html lang="en">)
      assert html =~ "Republic of Cameroon"
      assert html =~ "Subject"
      assert html =~ "Grade"
      # 15/20 on the default scale: B, Very good
      assert html =~ "Very good"
      refute html =~ "Matière"
    end

    test "bilingual: both labels, an identical word printed once", %{
      conn: conn,
      cg: cg,
      seq: seq,
      scope: scope
    } do
      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "bilingual",
          "elements" =>
            Enum.map(TeacherAssistant.Academics.BulletinElement.defaults(), &Atom.to_string/1)
        })

      html = print(conn, cg, seq)
      assert html =~ "Matière / Subject"
      assert html =~ "République du Cameroun"
      assert html =~ "Republic of Cameroon"
      refute html =~ "Coefficient / Coefficient"
    end

    test "hidden elements disappear and rows stay balanced", %{
      conn: conn,
      cg: cg,
      seq: seq,
      scope: scope
    } do
      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => [""]
        })

      html = print(conn, cg, seq)
      refute html =~ "Rang"
      refute html =~ "Cote classe"
      refute html =~ "Visa Professeur Principal"
      refute html =~ "Moyenne de la classe"
      refute html =~ "Absences non justifiées"
      assert html =~ "Moyenne générale"
      assert html =~ "Visa Chef d&#39;établissement"

      # Every body row has as many cells as the header (3 columns: Matière, Coefficient, Note, Note×Coef → 4).
      [thead | _] = Regex.run(~r/<thead>.*?<\/thead>/s, html)
      header_cells = length(Regex.scan(~r/<th[ >]/, thead))
      [tfoot | _] = Regex.run(~r/<tfoot>.*?<\/tfoot>/s, html)
      assert length(Regex.scan(~r/<th[ >]/, tfoot)) == header_cells
    end

    test "the class average prints when shown", %{conn: conn, cg: cg, seq: seq} do
      html = print(conn, cg, seq)
      assert html =~ "Moyenne de la classe"
    end

    test "a published card ignores later template changes", %{conn: conn, cg: cg, scope: scope} do
      scope = with_year(scope)
      term = first_term(scope)
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "bilingual",
          "elements" => [""]
        })

      html =
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}")
        |> html_response(200)

      refute html =~ "Matière / Subject"
      assert html =~ "Rang"
    end

    test "the QR prints on published cards only, when chosen", %{conn: conn, cg: cg, scope: scope} do
      scope = with_year(scope)
      term = first_term(scope)
      url = ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}"

      elements = [
        "qr_code"
        | Enum.map(TeacherAssistant.Academics.BulletinElement.defaults(), &Atom.to_string/1)
      ]

      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => elements
        })

      refute conn |> get(url) |> html_response(200) =~ "<svg"
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      assert conn |> get(url) |> html_response(200) =~ "<svg"
    end
  end
end
