defmodule TeacherAssistantWeb.School.SequenceTrackingLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.{Notifications, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, actor: head} do
    seqs = Organization.list_sequences(scope, year)
    [seq, seq2 | _] = seqs

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e A", level: "3ème"})
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "4e B", level: "4ème"})

    {:ok, s1} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, _s3} = Enrollment.add_student(scope, cg, %{full_name: "Carl", sex: :m})
    {:ok, t1} = Enrollment.add_student(scope, cg2, %{full_name: "Dina", sex: :f})

    english = TeacherFixtures.member_scope_fixture(scope).current_user

    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Curriculum.assign_teacher(scope, cg, english, %{subject: "Anglais"})
    {:ok, tc4} = Curriculum.assign_teacher(scope, cg2, english, %{subject: "Anglais"})

    {:ok, a1} = Assessment.create_assessment(scope, tc, seq, %{label: "Interro 1"})
    {:ok, a2} = Assessment.create_assessment(scope, tc, seq, %{label: "Devoir 1"})

    :ok =
      Assessment.upsert_marks(scope, a1, [
        %{student_id: s1.id, score: Decimal.new(10)},
        %{student_id: s2.id, status: :absent}
      ])

    :ok = Assessment.upsert_marks(scope, a2, [%{student_id: s1.id, score: Decimal.new(12)}])

    %{
      t1: t1,
      tc: tc,
      tc4: tc4,
      seq: seq,
      seq2: seq2,
      seqs: seqs,
      cg: cg,
      cg2: cg2,
      english: english,
      head: head
    }
  end

  defp col(view, cg, label) do
    # Column index of `label` in the grid header.
    html = view |> element("#entry-grid") |> render()

    headers =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-subject]")
      |> Enum.flat_map(&LazyHTML.attribute(&1, "title"))

    n = Enum.find_index(headers, &(&1 == label))
    "#cell-#{cg.id}-#{n}"
  end

  test "a teacher is sent back to /school", %{scope: scope, workspace: school} do
    teacher = TeacherFixtures.member_scope_fixture(scope).current_user

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(teacher)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school", flash: %{"error" => _}}}} =
             live(conn, ~p"/school/sequences")
  end

  test "the censorat lands on the teacher table, under four figures", %{conn: conn} = ctx do
    {:ok, view, html} = live(conn, ~p"/school/sequences")

    assert html =~ "Suivi de la saisie"
    assert has_element?(view, "#kpi-assessments", "2")
    assert has_element?(view, "#kpi-assessments", "3 notes saisies")
    assert has_element?(view, "#kpi-started", "1 / 2")
    assert has_element?(view, "#kpi-started", "2 à relancer")
    assert has_element?(view, "#kpi-reminders", "0")
    assert has_element?(view, "#view-teachers[aria-current]")

    # Maths 3e A at 50 % (started), Anglais 3e A and 4e B at 0 %
    assert has_element?(view, "#teacher-#{ctx.head.id}", "Maths")
    assert has_element?(view, "#teacher-#{ctx.head.id}", "1/1")
    assert has_element?(view, "#teacher-#{ctx.english.id}", "Anglais")
    assert has_element?(view, "#teacher-#{ctx.english.id}", "2 cours")
    assert has_element?(view, "#teacher-#{ctx.english.id}", "0/2")
    refute has_element?(view, "#entry-grid")

    # the whole school's relevé des notes for the séquence on screen
    assert has_element?(
             view,
             "#print-mark-sheets[href='/school/mark-sheets/print?period=seq%3A#{ctx.seq.id}']",
             "Imprimer le relevé"
           )
  end

  test "the teachers who started nothing are ticked on arrival", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")

    assert has_element?(view, "#pick-#{ctx.english.id}[checked]")
    refute has_element?(view, "#pick-#{ctx.head.id}[checked]")
    assert has_element?(view, "#remind-picked", "Relancer la sélection · 1")
  end

  test "« Par classe » shows the classes × subjects grid and a course's detail",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?view=classes")

    assert view |> element(col(view, ctx.cg, "Maths")) |> render() =~ "50 %"
    assert view |> element(col(view, ctx.cg, "Anglais")) |> render() =~ "0 %"
    # 4e B does not take Maths: a dashed, non-clickable cell.
    assert has_element?(view, "#{col(view, ctx.cg2, "Maths")}.border-dashed")
    # the first incomplete course is selected on arrival
    assert has_element?(view, "#cell-detail")
    refute has_element?(view, "#teacher-table")
  end

  test "clicking a cell shows its detail", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences?view=classes")

    view |> element(col(view, ctx.cg, "Maths")) |> render_click()

    detail = view |> element("#cell-detail") |> render()
    assert detail =~ "Notes saisies"
    assert detail =~ ~r/3\s*\/\s*6/
    assert detail =~ ctx.head.email |> to_string()
    assert detail =~ "Interro 1"
    assert detail =~ "Devoir 1"
    assert detail =~ "Dernière saisie"
  end

  test "« Par matière » groups the courses by subject", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/sequences")

    view |> element("#view-subjects") |> render_click()
    assert has_element?(view, "#view-subjects[aria-current]")
    assert has_element?(view, "#subject-table tr", "Anglais")
    assert has_element?(view, "#subject-table tr", "Maths")
    assert view |> element("#subject-table") |> render() =~ "0/2"
  end

  test "the search narrows the table", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences")

    view |> form("#tracking-search", %{"q" => "angl"}) |> render_change()
    assert has_element?(view, "#teacher-#{ctx.english.id}")
    refute has_element?(view, "#teacher-#{ctx.head.id}")

    view |> form("#tracking-search", %{"q" => "zzz"}) |> render_change()
    assert has_element?(view, "#teacher-table", "Aucun enseignant ne correspond")
  end

  test "the séquence select names each state", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
    assert has_element?(view, "#seq-option-#{ctx.seq.id}", "en cours")
    assert has_element?(view, "#seq-option-#{ctx.seq.id}[selected]")
  end

  test "a complete cell shows ✓", %{conn: conn, scope: scope} = ctx do
    {:ok, a} = Assessment.create_assessment(scope, ctx.tc4, ctx.seq, %{label: "Contrôle"})
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: ctx.t1.id, score: Decimal.new(14)}])

    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}&view=classes")
    assert view |> element(col(view, ctx.cg2, "Anglais")) |> render() =~ "✓"
  end

  describe "APC competences" do
    setup %{scope: scope} do
      {:ok, _} =
        Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => ["apc", "rank"]
        })

      :ok
    end

    test "cells without a competence carry a marker, counted above the grid",
         %{conn: conn, scope: scope} = ctx do
      :ok = Assessment.put_sequence_competence(scope, ctx.tc, ctx.seq, "Lire un graphique")
      {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}&view=classes")

      refute has_element?(view, "#{col(view, ctx.cg, "Maths")} [data-role='no-competence']")
      assert has_element?(view, "#{col(view, ctx.cg, "Anglais")} [data-role='no-competence']")
      assert has_element?(view, "#{col(view, ctx.cg2, "Anglais")} [data-role='no-competence']")
      assert has_element?(view, "#kpi-competences", "2")
      # per teacher: the competences still to write
      view |> element("#view-teachers") |> render_click()
      assert has_element?(view, "#teacher-#{ctx.english.id}", "2 à saisir")
      assert has_element?(view, "#teacher-#{ctx.head.id}", "Toutes ✓")
    end

    test "the course detail shows its competence or « à saisir »",
         %{conn: conn, scope: scope} = ctx do
      :ok = Assessment.put_sequence_competence(scope, ctx.tc, ctx.seq, "Lire un graphique")
      {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}&view=classes")

      view |> element(col(view, ctx.cg, "Maths")) |> render_click()
      assert has_element?(view, "#cell-detail #detail-competence", "Lire un graphique")

      view |> element(col(view, ctx.cg, "Anglais")) |> render_click()
      assert has_element?(view, "#cell-detail #detail-competence", "à saisir")
    end

    test "on the phone list a course with all its marks but no competence is listed, without Relancer",
         %{conn: conn, scope: scope} = ctx do
      {:ok, a} = Assessment.create_assessment(scope, ctx.tc4, ctx.seq, %{label: "Contrôle"})
      :ok = Assessment.upsert_marks(scope, a, [%{student_id: ctx.t1.id, score: Decimal.new(14)}])

      {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}&view=classes")
      row = "#entry-row-#{ctx.cg2.id}"
      assert has_element?(view, row, "Anglais")
      assert has_element?(view, row, "compétence à saisir")
      refute has_element?(view, "#{row} button", "Relancer")
    end
  end

  test "no competence marker when the school's report cards are not APC", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}&view=classes")
    refute has_element?(view, "[data-role='no-competence']")
    assert has_element?(view, "#kpi-competences", "bulletins sans APC")
    refute has_element?(view, "#detail-competence")
  end

  test "« Relancer la sélection » notifies the picked teachers once and flips them to Relancé",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")

    html = view |> element("#remind-picked") |> render_click()
    assert html =~ "2 rappels envoyés"
    assert has_element?(view, "#reminded-#{ctx.english.id}")
    refute has_element?(view, "#pick-#{ctx.english.id}")
    assert %{unread: 2} = Notifications.bell(english_scope(ctx))
    # the other teacher is untouched, and the selection is cleared
    refute has_element?(view, "#reminded-#{ctx.head.id}")
    refute has_element?(view, "#remind-bar")
  end

  test "pick ignores a teacher who is not late", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
    view |> element("#remind-bar button", "Désélectionner") |> render_click()

    render_click(view, "pick", %{"id" => Ecto.UUID.generate()})
    refute has_element?(view, "#remind-bar")
  end

  test "?seq= selects a séquence; an unknown one falls back", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=#{ctx.seq2.id}")
    assert has_element?(view, "#seq-option-#{ctx.seq2.id}[selected]")
    refute has_element?(view, "#seq-option-#{ctx.seq.id}[selected]")

    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=garbage")
    assert has_element?(view, "#seq-option-#{ctx.seq.id}[selected]")

    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=#{Ecto.UUID.generate()}")
    assert has_element?(view, "#seq-option-#{ctx.seq.id}[selected]")
  end

  test "picking another séquence patches the URL", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences")

    view |> form("#seq-form", %{"seq" => ctx.seq2.id}) |> render_change()
    assert_patch(view, ~p"/school/sequences?seq=#{ctx.seq2.id}&view=teachers")
    assert has_element?(view, "#seq-option-#{ctx.seq2.id}[selected]")
  end

  test "a school without séquences shows an empty state" do
    %{workspace: school, head_user: head, scope: scope, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    scope |> Organization.list_sequences(year) |> Enum.each(&Ash.destroy!(&1, scope: scope))

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(head)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/sequences")
    assert has_element?(view, "#no-sequences")
    refute has_element?(view, "#entry-grid")
  end

  defp english_scope(ctx), do: TeacherAssistant.DataCase.school_scope(ctx.english, ctx.workspace)

  defp tc_id_of(view, cell) do
    view
    |> element(cell)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-tc")
    |> hd()
  end

  test "« Relancer » notifies the course's teacher once a day and marks the cell",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}&view=classes")
    cell = col(view, ctx.cg, "Anglais")
    view |> element(cell) |> render_click()

    html = view |> element("#remind-course") |> render_click()
    assert html =~ "Relance envoyée"

    assert %{unread: 1, latest: [%{kind: :entry_reminder}]} =
             Notifications.bell(english_scope(ctx))

    assert has_element?(view, "#{cell}[data-reminded]")
    assert has_element?(view, "#reminded-on")
    refute has_element?(view, "#remind-course")

    # A forged second click the same day is refused quietly.
    render_click(view, "remind", %{"tc" => tc_id_of(view, cell)})
    assert %{unread: 1} = Notifications.bell(english_scope(ctx))
    refute render(view) =~ "n'a pas pu"
  end

  test "ticking every late teacher reminds each lagging course, once", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")

    view |> element("#pick-all") |> render_click()
    assert has_element?(view, "#remind-picked", "· 2")

    html = view |> element("#remind-picked") |> render_click()
    # Anglais 3e A, Anglais 4e B and Maths 3e A (50 %).
    assert html =~ "3 rappels envoyés"
    assert %{unread: 2} = Notifications.bell(english_scope(ctx))

    # everyone was reminded today: nothing left to tick
    assert has_element?(view, "#pick-all[disabled]")
  end
end
