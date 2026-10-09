defmodule TeacherAssistantWeb.School.BulletinLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée Bu"})

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

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: student, enrollment: enr}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: student.id, score: Decimal.new(15)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, enr: enr, head: head, scope: scope, tc: tc}
  end

  test "the bulletin page embeds the print document", %{conn: conn, cg: cg, enr: enr, seq: seq} do
    {:ok, view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert html =~ "Awa Ngo"

    assert has_element?(
             view,
             "#bulletin-sheet[src^='/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print']"
           )

    period = URI.encode_www_form("seq:#{seq.id}")
    assert has_element?(view, "#bulletin-sheet[src$='period=#{period}']")
    assert has_element?(view, "a[href='/school/students/#{enr.student_id}']", "Fiche élève")

    assert has_element?(
             view,
             "a[href='/school/bulletins?class=#{cg.id}&period=#{period}']",
             "Bulletins de la 6e A"
           )

    assert has_element?(view, "#bulletin-print[target='_blank']", "Imprimer")
    # The duplicated on-screen table is gone: the sheet shows it.
    refute has_element?(view, "#bulletin-subjects")
  end

  test "changing the period reloads the sheet for that period", %{
    conn: conn,
    cg: cg,
    enr: enr,
    seq: seq,
    scope: scope
  } do
    [term1 | _] = Organization.list_terms(scope, Organization.current_academic_year(scope))

    {:ok, view, _} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    view
    |> form("#bulletin-period-form", %{period: "trim:#{term1.id}"})
    |> render_change()

    period = URI.encode_www_form("trim:#{term1.id}")
    assert has_element?(view, "#bulletin-sheet[src$='period=#{period}']")
  end

  test "an enrollment from another class is rejected", %{
    conn: conn,
    cg: cg,
    seq: seq,
    scope: scope
  } do
    {:ok, cg2} =
      Enrollment.create_class_group(
        scope,
        TeacherAssistant.Organization.current_academic_year(scope),
        %{
          label: "6e B",
          level: "6ème"
        }
      )

    {:ok, _} = Enrollment.add_student(scope, cg2, %{full_name: "Bob", sex: :m})
    [%{enrollment: other_enr}] = Enrollment.list_roster(scope, cg2)

    assert {:error, {:live_redirect, %{}}} =
             live(
               conn,
               ~p"/school/classes/#{cg.id}/students/#{other_enr.id}/bulletin?period=seq:#{seq.id}"
             )
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
    test "a published trimester shows its publication date", %{
      conn: conn,
      cg: cg,
      enr: enr,
      scope: scope
    } do
      scope = with_year(scope)
      term = first_term(scope)
      {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      {:ok, view, _} =
        live(
          conn,
          ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=trim:#{term.id}"
        )

      assert render(element(view, "#bulletin-published")) =~
               Calendar.strftime(TeacherAssistant.ReportCards.published_on(pub), "%d/%m/%Y")
    end

    test "the student page shows the latest published result", %{
      conn: conn,
      cg: cg,
      enr: enr,
      scope: scope
    } do
      scope = with_year(scope)
      term = first_term(scope)
      url = ~p"/school/students/#{enr.student_id}"

      {:ok, view, _} = live(conn, url)
      refute view |> element("#history-#{enr.id}") |> render() =~ "Trim."

      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      {:ok, view, _} = live(conn, url)

      assert view |> element("#history-#{enr.id}") |> render() =~
               "Trim. #{term.position} : 15.00 · 1er / 1"
    end

    test "a teacher of the class reads published cards only", %{
      cg: cg,
      enr: enr,
      scope: scope,
      seq: seq
    } do
      scope = with_year(scope)
      term = first_term(scope)
      tconn = teacher_conn(scope, cg)
      url = ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=trim:#{term.id}"

      {:ok, view, _} = live(tconn, url)
      assert has_element?(view, "#bulletin-not-published")
      refute has_element?(view, "#bulletin-sheet")

      {:ok, view, _} =
        live(tconn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

      assert has_element?(view, "#bulletin-not-published")

      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      {:ok, view, _} = live(tconn, url)
      assert has_element?(view, "#bulletin-sheet")
      assert has_element?(view, "#bulletin-published")
    end

    test "a student enrolled after publication is absent from it", %{
      conn: conn,
      cg: cg,
      scope: scope
    } do
      scope = with_year(scope)
      term = first_term(scope)
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Zoé Late", sex: :f})

      %{enrollment: late} =
        Enum.find(Enrollment.list_roster(scope, cg), &(&1.student.full_name == "Zoé Late"))

      {:ok, view, _} =
        live(
          conn,
          ~p"/school/classes/#{cg.id}/students/#{late.id}/bulletin?period=trim:#{term.id}"
        )

      assert has_element?(view, "#bulletin-absent")
      refute has_element?(view, "#bulletin-sheet")
    end
  end
end
