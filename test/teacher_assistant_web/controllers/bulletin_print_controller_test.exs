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
      Discipline.add_sanction(scope, enr, %{
        type: :consigne,
        date: date,
        reason: "Bavardage",
        duration_hours: 2
      })

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
      |> put_user_in_session(other)
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
    fm = TeacherAssistant.TeacherFixtures.user_fixture(%{name: "Pauline Atangana"})

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
      |> put_user_in_session(fm)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    html = html_response(conn, 200)
    assert html =~ "Awa Ngo"
    # The form master is printed by name, never by e-mail.
    assert html =~ "Pauline Atangana"
    refute html =~ to_string(fm.email)
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
    [_s1, s2 | _] = TeacherAssistant.MarksFixtures.start_sequences!(scope, year)
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
    assert body =~ "Bulletin scolaire du premier trimestre"
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
      |> put_user_in_session(head)
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

    test "a published card drops a logo the school has since removed", %{
      conn: conn,
      cg: cg,
      scope: scope
    } do
      scope = with_year(scope)
      term = first_term(scope)
      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

      {:ok, profile} =
        TeacherAssistant.Accounts.set_school_logo(profile, "logo.png", scope: scope)

      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      url = ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}"
      assert conn |> get(url) |> html_response(200) =~ ~s(src="/school/logo")

      {:ok, _} =
        TeacherAssistant.Accounts.set_school_logo(profile, nil, scope: scope)

      refute conn |> get(url) |> html_response(200) =~ ~s(src="/school/logo")
    end
  end

  test "prints date and place of birth when known", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster,
    scope: scope
  } do
    %{student: awa, enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))

    {:ok, _} =
      Enrollment.update_student(awa, %{birth_date: ~D[2013-04-02], birth_place: "Yaoundé"},
        scope: scope
      )

    body =
      conn
      |> get(~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}")
      |> html_response(200)

    assert body =~ "Né(e) le"
    assert body =~ "02/04/2013"
    assert body =~ "Yaoundé"
  end

  test "the head's slot prints the signature and the stamp when set", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster,
    scope: scope
  } do
    %{enrollment: enr} = hd(roster)

    {:ok, _} =
      TeacherAssistant.Accounts.update_official_header(scope, %{
        signature_path: "s.png",
        stamp_path: "c.png"
      })

    body =
      conn
      |> get(~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}")
      |> html_response(200)

    assert body =~ "/school/logo?kind=signature"
    assert body =~ "/school/logo?kind=stamp"
  end

  test "custom header lines print once on a bilingual card", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster,
    scope: scope
  } do
    %{enrollment: enr} = hd(roster)

    {:ok, _} =
      TeacherAssistant.Accounts.update_official_header(scope, %{
        official_header_lines: ["Ligne propre à l'école"]
      })

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    {:ok, _} =
      TeacherAssistant.Accounts.update_school_profile(profile, %{bulletin_language: :bilingual},
        scope: scope
      )

    body =
      conn
      |> get(~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}")
      |> html_response(200)

    assert length(String.split(body, "Ligne propre à l&#39;école")) == 2
  end

  describe "report card elements (pilotage)" do
    defp awa_print(ctx, period \\ nil) do
      %{enrollment: enr} = Enum.find(ctx.roster, &(&1.student.full_name == "Awa Ngo"))
      period = period || "seq:#{ctx.seq.id}"

      ctx.conn
      |> get(~p"/school/classes/#{ctx.cg.id}/students/#{enr.id}/bulletin/print?period=#{period}")
      |> html_response(200)
    end

    defp old_elements,
      do: ~w(rank class_average min_max subject_appreciation effectif birth absences conduct
             pp_signature signature stamp qr_code)

    defp save_elements(scope, elements),
      do:
        {:ok, _} =
          TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
            "language" => "by_class",
            "elements" => elements
          })

    test "shows subject teacher, subject rank, class extremes, PP and parent visa", ctx do
      %{teacher: _} =
        TeacherAssistant.TeacherFixtures.school_teacher_fixture(ctx.scope, %{
          class_group: ctx.cg,
          subject: "SVT",
          teacher: TeacherAssistant.TeacherFixtures.user_fixture(%{name: "Jean Mbarga"})
        })

      {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, ctx.head.id)
      html = awa_print(ctx)
      assert html =~ ~r/<div class="teacher">\s*Jean Mbarga\s*<\/div>/
      assert html =~ ~r/<th class="num">\s*Rang\s*<\/th>/
      assert html =~ "Plus forte"
      assert html =~ "plus faible"
      assert html =~ "Professeur principal"
      assert html =~ "Visa du parent"
      assert html =~ "Redoublant(e)"
      assert html =~ ~s(class="head-name")
      assert html =~ Accounts.User.display_name(ctx.head)
    end

    test "a repeater is marked as such", ctx do
      {:ok, _} =
        Enrollment.add_student(ctx.scope, ctx.cg, %{
          full_name: "Carine Redo",
          sex: :f,
          repeater: true
        })

      %{enrollment: enr} =
        Enum.find(
          Enrollment.list_roster(ctx.scope, ctx.cg),
          &(&1.student.full_name == "Carine Redo")
        )

      html =
        ctx.conn
        |> get(
          ~p"/school/classes/#{ctx.cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{ctx.seq.id}"
        )
        |> html_response(200)

      assert html =~ ~r/Redoublant\(e\)<\/td>\s*<td>\s*oui/
      assert awa_print(ctx) =~ ~r/Redoublant\(e\)<\/td>\s*<td>\s*non/
    end

    test "an element switched off disappears", ctx do
      save_elements(ctx.scope, ["rank"])
      html = awa_print(ctx)
      refute html =~ "Visa du parent"
      refute html =~ "Plus forte"
      refute html =~ ~r/<th class="num">\s*Rang\s*<\/th>/
      refute html =~ ~s(class="teacher")
      refute html =~ "Redoublant(e)"
      refute html =~ "Professeur principal"
      refute html =~ ~s(class="head-name")
    end

    test "a school with only the old elements prints none of the new pieces", ctx do
      save_elements(ctx.scope, old_elements())
      scope = with_year(ctx.scope)
      term = first_term(scope)
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, ctx.cg, term)
      html = awa_print(ctx, "trim:#{term.id}")

      assert html =~ "<svg"
      refute html =~ "Vérifiable en ligne"
      refute html =~ "Visa du parent"
      refute html =~ "Plus forte"
      refute html =~ ~s(class="teacher")
      refute html =~ "Redoublant(e)"
      refute html =~ ~s(class="head-name")

      # Rows stay balanced: the footer has as many cells as the header.
      [thead | _] = Regex.run(~r/<thead>.*?<\/thead>/s, html)
      [tfoot | _] = Regex.run(~r/<tfoot>.*?<\/tfoot>/s, html)

      assert length(Regex.scan(~r/<th[ >]/, tfoot)) ==
               length(Regex.scan(~r/<th[ >]/, thead))
    end

    test "the verification link prints next to the QR on a published card", ctx do
      save_elements(ctx.scope, ["qr_code", "verify_link"])
      scope = with_year(ctx.scope)
      term = first_term(scope)
      refute awa_print(ctx, "trim:#{term.id}") =~ "Vérifiable en ligne"

      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, ctx.cg, term)
      html = awa_print(ctx, "trim:#{term.id}")
      assert html =~ "Vérifiable en ligne"
      assert html =~ "/verify/bulletin/"
    end

    test "the subject rank column keeps every row balanced", ctx do
      save_elements(ctx.scope, ["subject_rank"])
      {:ok, _} = Curriculum.set_bulletin_group_subtotals(ctx.scope, true)
      html = awa_print(ctx)
      assert html =~ ~r/<th class="num">\s*Rang\s*<\/th>/

      [thead | _] = Regex.run(~r/<thead>.*?<\/thead>/s, html)
      header_cells = length(Regex.scan(~r/<th[ >]/, thead))
      [tfoot | _] = Regex.run(~r/<tfoot>.*?<\/tfoot>/s, html)
      assert length(Regex.scan(~r/<th[ >]/, tfoot)) == header_cells
      [total | _] = Regex.run(~r/<tr[^>]*bulletin-group-total.*?<\/tr>/s, html)
      assert length(Regex.scan(~r/<td[ >]/, total)) == header_cells
    end

    test "a snapshot published before this cycle still prints", ctx do
      scope = with_year(ctx.scope)
      term = first_term(scope)
      {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, ctx.cg, term)

      # An older snapshot: no teachers, no repeater flag, no subject ranks nor extremes,
      # and a template carrying every element (as a school without a saved list).
      old =
        pub.snapshot
        |> Map.delete(:teachers)
        |> Map.update!(:roster, fn roster ->
          Enum.map(roster, &%{&1 | enrollment: Map.delete(&1.enrollment, :repeater)})
        end)
        |> Map.update!(:results, fn results ->
          results
          |> Map.drop([:highest, :lowest])
          |> Map.update!(:per_student, fn per ->
            Map.new(per, fn {id, d} ->
              {id,
               %{
                 d
                 | subjects: Enum.map(d.subjects, &Map.delete(&1, :subject_rank)),
                   groups:
                     Enum.map(d.groups, fn g ->
                       %{g | rows: Enum.map(g.rows, &Map.delete(&1, :subject_rank))}
                     end)
               }}
            end)
          end)
        end)
        |> Map.update!(:template, fn t ->
          %{t | elements: TeacherAssistant.Academics.BulletinElement.values()}
        end)

      {:ok, id} = Ecto.UUID.dump(pub.id)

      import Ecto.Query, only: [from: 2]

      {1, _} =
        TeacherAssistant.Repo.update_all(
          from(p in "bulletin_publications", where: p.id == ^id),
          set: [snapshot: :erlang.term_to_binary(old)]
        )

      html = awa_print(ctx, "trim:#{term.id}")
      assert html =~ "Bulletin de notes"
      assert html =~ "Visa du parent"
      refute html =~ "Plus forte"
    end
  end

  # Moved from the on-screen bulletin's tests: the page now embeds this document.
  describe "content once shown by the on-screen bulletin" do
    test "the make-up rule turns a zero into an R with its legend", ctx do
      [tc] = Curriculum.list_assignments_for_class(ctx.scope, ctx.cg)

      {:ok, a2} =
        Assessment.create_assessment(ctx.scope, tc, ctx.seq, %{
          label: "D2",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      %{student: st, enrollment: enr} =
        Enum.find(ctx.roster, &(&1.student.full_name == "Awa Ngo"))

      :ok =
        Assessment.upsert_marks(ctx.scope, a2, [%{student_id: st.id, score: nil, status: :absent}])

      path =
        ~p"/school/classes/#{ctx.cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{ctx.seq.id}"

      html = ctx.conn |> get(path) |> html_response(200)
      assert html =~ "7,00"
      refute html =~ "R : rattrapage attendu"

      {:ok, _} = Assessment.update_grading_rules(ctx.scope, %{"absence_rule" => "makeup"})
      html = ctx.conn |> get(path) |> html_response(200)
      assert html =~ "<sup>R</sup>"
      assert html =~ "R : rattrapage attendu"
    end

    test "the card uses the school's own appreciation scale", ctx do
      {:ok, _} =
        Assessment.update_appreciation_bands(ctx.scope, [
          %{from: "0", label: "À revoir"},
          %{from: "14", label: "Réussi"}
        ])

      %{enrollment: enr} = hd(ctx.roster)

      html =
        ctx.conn
        |> get(
          ~p"/school/classes/#{ctx.cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{ctx.seq.id}"
        )
        |> html_response(200)

      assert html =~ "Réussi"
    end

    test "a trimester card carries the council's warning and withheld distinction", ctx do
      scope = with_year(ctx.scope)
      term = first_term(scope)

      %{student: st, enrollment: enr} =
        Enum.find(ctx.roster, &(&1.student.full_name == "Awa Ngo"))

      {:ok, _} =
        TeacherAssistant.Councils.set_decision(scope, ctx.cg, {:trimester, term}, st.id, %{
          "distinction_choice" => "none",
          "conduct_warning" => "blame_conduite",
          "appreciation" => "Trimestre fragile"
        })

      html =
        ctx.conn
        |> get(
          ~p"/school/classes/#{ctx.cg.id}/students/#{enr.id}/bulletin/print?period=trim:#{term.id}"
        )
        |> html_response(200)

      assert html =~ "Blâme de conduite"
      assert html =~ "Trimestre fragile"
      refute html =~ "Encouragements"
    end
  end

  test "the print document may be framed by the app's own pages only", ctx do
    %{enrollment: enr} = hd(ctx.roster)

    conn =
      get(
        ctx.conn,
        ~p"/school/classes/#{ctx.cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{ctx.seq.id}"
      )

    assert html_response(conn, 200)
    [csp] = Plug.Conn.get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors 'self'"
    refute "DENY" in Plug.Conn.get_resp_header(conn, "x-frame-options")
  end

  describe "student photo (spec 2026-10-12 §6)" do
    defp tmp_jpeg do
      path = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
      File.cp!("test/support/fixtures/files/1x1.jpg", path)
      path
    end

    test "a published bulletin keeps the photo of the publication; a draft shows the current one",
         %{conn: conn, cg: cg, scope: scope, roster: roster} do
      scope = with_year(scope)
      term = first_term(scope)
      url = ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}"
      [%{student: st} | _] = roster

      {:ok, first} = TeacherAssistant.StudentPhotos.store(scope, st, tmp_jpeg())
      {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      # A different file, so serving the current photo instead of the frozen one would show.
      second_src = tmp_jpeg()
      File.write!(second_src, "different tail", [:append])
      {:ok, second} = TeacherAssistant.StudentPhotos.store(scope, first, second_src)

      html = conn |> get(url) |> html_response(200)
      assert html =~ ~s(src="/school/bulletins/#{pub.id}/photo/#{st.id}")

      frozen = get(conn, ~p"/school/bulletins/#{pub.id}/photo/#{st.id}")
      {:ok, first_abs} = TeacherAssistant.Uploads.resolve(first.photo_path)
      {:ok, second_abs} = TeacherAssistant.Uploads.resolve(second.photo_path)
      assert frozen.status == 200
      assert frozen.resp_body == File.read!(first_abs)
      refute frozen.resp_body == File.read!(second_abs)

      # The draft of another period shows the current photo, versioned so no cache serves the old one.
      seq_html =
        conn
        |> get(
          ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{hd(Organization.list_sequences(scope, scope.current_academic_year)).id}"
        )
        |> html_response(200)

      assert seq_html =~
               ~s(src="/school/students/#{st.id}/photo?v=#{Path.basename(second.photo_path, ".jpg")}")
    end

    test "a student published without photo prints no image", %{conn: conn, cg: cg, scope: scope} do
      scope = with_year(scope)
      term = first_term(scope)
      {:ok, _pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      html =
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}")
        |> html_response(200)

      refute html =~ ~s(class="student-photo")
    end

    test "unchecking the photo element hides it", %{
      conn: conn,
      cg: cg,
      scope: scope,
      roster: roster
    } do
      scope = with_year(scope)
      term = first_term(scope)
      [%{student: st} | _] = roster
      {:ok, _} = TeacherAssistant.StudentPhotos.store(scope, st, tmp_jpeg())

      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

      {:ok, _} =
        TeacherAssistant.Accounts.update_school_profile(
          profile,
          %{bulletin_elements: TeacherAssistant.Academics.BulletinElement.defaults() -- [:photo]},
          scope: scope
        )

      html =
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}")
        |> html_response(200)

      refute html =~ ~s(class="student-photo")
    end

    test "photo_url/2: v1–v3 snapshot entries (no :photo_path key) give no image" do
      alias TeacherAssistantWeb.BulletinPrintController, as: C
      student = %{id: Ecto.UUID.generate(), full_name: "Awa"}
      assert C.photo_url(%{id: Ecto.UUID.generate()}, student) == nil

      assert C.photo_url(nil, Map.put(student, :photo_path, "student_photos/w/abc.jpg")) ==
               "/school/students/#{student.id}/photo?v=abc"
    end

    test "another school cannot read a frozen photo", %{cg: cg, scope: scope, roster: roster} do
      scope = with_year(scope)
      [%{student: st} | _] = roster
      {:ok, _} = TeacherAssistant.StudentPhotos.store(scope, st, tmp_jpeg())

      {:ok, pub} =
        TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, first_term(scope))

      %{head_user: h, workspace: w} =
        TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

      conn = build_conn() |> log_in_user(h) |> Plug.Conn.put_session(:workspace_id, w.id)
      assert get(conn, ~p"/school/bulletins/#{pub.id}/photo/#{st.id}").status == 404
    end
  end

  describe "v2 header, title and identity" do
    defp set_profile(scope, attrs) do
      {:ok, profile} = Accounts.fetch_school_profile(scope)
      {:ok, _} = profile |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
    end

    defp v2_print(ctx, period) do
      %{enrollment: enr} = Enum.find(ctx.roster, &(&1.student.full_name == "Awa Ngo"))

      ctx.conn
      |> get(~p"/school/classes/#{ctx.cg.id}/students/#{enr.id}/bulletin/print?period=#{period}")
      |> html_response(200)
    end

    defp v2_terms(ctx),
      do: Organization.list_terms(ctx.scope, Organization.class_year(ctx.scope, ctx.cg))

    test "French card prints both header columns with logo and code between", ctx do
      set_profile(ctx.scope, %{school_code: "5MN1TEF110431106"})
      html = v2_print(ctx, "seq:#{ctx.seq.id}")

      assert html =~ "République du Cameroun"
      assert html =~ "Republic of Cameroon"
      assert html =~ "Ministry of Secondary Education"
      assert html =~ "CODE : 5MN1TEF110431106"
      assert html =~ ~s(class="flag")
    end

    test "English name in the right column; workspace name when blank", ctx do
      html = v2_print(ctx, "seq:#{ctx.seq.id}")
      assert length(String.split(html, "Lycée Print")) >= 3

      set_profile(ctx.scope, %{name_en: "G.T.H.S Print"})
      assert v2_print(ctx, "seq:#{ctx.seq.id}") =~ "G.T.H.S Print"
    end

    test "no code line when school_code is nil", ctx do
      refute v2_print(ctx, "seq:#{ctx.seq.id}") =~ "CODE :"
    end

    test "title names the period", ctx do
      t3 = List.last(v2_terms(ctx))
      assert v2_print(ctx, "trim:#{t3.id}") =~ ~r/bulletin scolaire du troisième trimestre/i
      assert v2_print(ctx, "seq:#{ctx.seq.id}") =~ ~r/bulletin de la séquence 1/i
      assert v2_print(ctx, "annee") =~ ~r/bulletin annuel/i
    end

    test "identity shows national ID and guardians only with their elements", ctx do
      %{student: awa} = Enum.find(ctx.roster, &(&1.student.full_name == "Awa Ngo"))
      {:ok, awa} = Enrollment.update_student(awa, %{national_id: "241592812"}, scope: ctx.scope)

      {:ok, _} =
        Enrollment.add_guardian(ctx.scope, awa, %{
          full_name: "Mme Ngo",
          phone: "677123456",
          relationship: :mere
        })

      html = v2_print(ctx, "seq:#{ctx.seq.id}")
      assert html =~ "Identifiant unique"
      assert html =~ "241592812"
      assert html =~ "Mme Ngo"

      {:ok, _} =
        Assessment.update_bulletin_settings(ctx.scope, %{
          "language" => "by_class",
          "elements" => ["rank"]
        })

      html = v2_print(ctx, "seq:#{ctx.seq.id}")
      refute html =~ "241592812"
      refute html =~ "Mme Ngo"
    end
  end

  describe "v2 subject table, boxes and signatures" do
    defp elements(scope, list) do
      {:ok, _} =
        Assessment.update_bulletin_settings(scope, %{"language" => "by_class", "elements" => list})
    end

    defp maths(ctx), do: ctx.scope |> Curriculum.list_assignments_for_class(ctx.cg) |> hd()

    test "APC trimester card: one line per sequence with its competence and mark", ctx do
      elements(ctx.scope, ["apc"])

      :ok =
        Assessment.put_sequence_competence(
          ctx.scope,
          maths(ctx),
          ctx.seq,
          "Résoudre une équation"
        )

      t1 = hd(v2_terms(ctx))
      html = v2_print(ctx, "trim:#{t1.id}")

      assert html =~ "Compétences évaluées"
      assert html =~ "Résoudre une équation"
      assert html =~ ~s(rowspan="2")
      assert html =~ "N/20"
    end

    test "APC off: no Compétences, Cote or cotes box", ctx do
      elements(ctx.scope, ["rank"])
      html = v2_print(ctx, "trim:#{hd(v2_terms(ctx)).id}")
      refute html =~ "Compétences évaluées"
      refute html =~ ~r/<th class="num">\s*Cote\s*<\/th>/
      refute html =~ ~s(id="cotes-box")
    end

    test "letter-graded class with APC: competence lines but no Cote column", ctx do
      elements(ctx.scope, ["apc"])
      year = Organization.class_year(ctx.scope, ctx.cg)

      {:ok, en} =
        Enrollment.create_class_group(ctx.scope, year, %{
          label: "Form 1 A",
          level: "Form 1",
          subsystem: :anglophone
        })

      {:ok, _} = Enrollment.add_student(ctx.scope, en, %{full_name: "Ngum Che", sex: :f})
      {:ok, tc} = Curriculum.assign_teacher(ctx.scope, en, ctx.head, %{subject: "Biology"})
      :ok = Assessment.put_sequence_competence(ctx.scope, tc, ctx.seq, "Describe a cell")
      t1 = hd(v2_terms(ctx))

      html =
        ctx.conn
        |> get(~p"/school/classes/#{en.id}/bulletin/print?period=trim:#{t1.id}")
        |> html_response(200)

      assert html =~ "Describe a cell"
      refute html =~ ~r/<th class="num">\s*Cote\s*<\/th>/
      refute html =~ ~s(id="cotes-box")
    end

    test "sequence card with APC shows that sequence's competence on the subject's line", ctx do
      elements(ctx.scope, ["apc"])

      :ok =
        Assessment.put_sequence_competence(ctx.scope, maths(ctx), ctx.seq, "Calculer une aire")

      html = v2_print(ctx, "seq:#{ctx.seq.id}")
      assert html =~ "Calculer une aire"
      refute html =~ ~s(rowspan="2")
    end

    test "annual card never shows competences", ctx do
      elements(ctx.scope, ["apc"])

      :ok =
        Assessment.put_sequence_competence(ctx.scope, maths(ctx), ctx.seq, "Calculer une aire")

      html = v2_print(ctx, "annee")
      refute html =~ "Compétences évaluées"
      refute html =~ "Calculer une aire"
    end

    test "cotes box counts subjects per code", ctx do
      elements(ctx.scope, ["apc"])

      rows =
        Enum.map(
          TeacherAssistant.Academics.Appreciations.apc_bands(),
          &%{from: Decimal.to_string(&1.from), label: &1.label, code: &1.code}
        )

      {:ok, _} = Assessment.update_appreciation_bands(ctx.scope, rows)
      html = v2_print(ctx, "trim:#{hd(v2_terms(ctx)).id}")

      assert html =~ ~s(id="cotes-box")
      assert html =~ ~r/CBA<\/td>\s*<td class="v">\s*1\s*</
      assert html =~ ~r/CTBA<\/td>\s*<td class="v">\s*0\s*</
      assert html =~ ~r/<th class="num">\s*Cote\s*<\/th>/
    end

    test "term 2 shows term 1 average; term 3 shows annual average, rank and decision", ctx do
      [_t1, t2, t3] = v2_terms(ctx)
      html = v2_print(ctx, "trim:#{t2.id}")
      assert html =~ "Moyenne trim. 1"

      html = v2_print(ctx, "trim:#{t3.id}")
      assert html =~ "Moyenne trim. 2"
      assert html =~ "Moyenne annuelle"
      assert html =~ "Rang annuel"
      assert html =~ ~s(class="decision")
    end

    test "class profile box shows passing count and rate with the element", ctx do
      elements(ctx.scope, ["class_profile"])
      html = v2_print(ctx, "seq:#{ctx.seq.id}")
      assert html =~ "Moyennes ≥ 10"
      assert html =~ "Taux de réussite"
      assert html =~ "100 %"

      elements(ctx.scope, ["rank"])
      refute v2_print(ctx, "seq:#{ctx.seq.id}") =~ "Taux de réussite"
    end

    test "teacher visa column only with the element", ctx do
      elements(ctx.scope, ["teacher_visa"])
      assert v2_print(ctx, "seq:#{ctx.seq.id}") =~ ~r/<th>\s*Visa\s*<\/th>/
      elements(ctx.scope, ["rank"])
      refute v2_print(ctx, "seq:#{ctx.seq.id}") =~ ~r/<th>\s*Visa\s*<\/th>/
    end

    test "head visa shows title and name with « Fait à <town>, le <date> »", ctx do
      set_profile(ctx.scope, %{
        school_type: :lycee,
        town: "Ngog-Mapubi",
        head_name: "Mme Ngo Tonye"
      })

      html = v2_print(ctx, "seq:#{ctx.seq.id}")
      assert html =~ "Le Proviseur"
      assert html =~ "Fait à Ngog-Mapubi"
      assert html =~ "Mme Ngo Tonye"
    end

    test "a pre-v2 snapshot still renders", ctx do
      scope = with_year(ctx.scope)
      t1 = first_term(scope)
      {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, ctx.cg, t1)

      old =
        pub.snapshot
        |> Map.drop([:competences, :sequences_per_term, :prior_terms, :annual])
        |> Map.update!(:roster, fn roster ->
          Enum.map(roster, fn e ->
            e |> Map.delete(:guardians) |> Map.update!(:student, &Map.delete(&1, :national_id))
          end)
        end)
        |> Map.update!(:template, &Map.delete(&1, :cote_codes))

      {:ok, id} = Ecto.UUID.dump(pub.id)

      TeacherAssistant.Repo.query!(
        "UPDATE bulletin_publications SET snapshot = $1 WHERE id = $2",
        [:erlang.term_to_binary(old), id]
      )

      html = v2_print(ctx, "trim:#{t1.id}")
      assert html =~ "Awa Ngo"
    end
  end
end
