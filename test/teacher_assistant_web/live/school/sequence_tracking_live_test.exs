defmodule TeacherAssistantWeb.School.SequenceTrackingLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, actor: head} do
    seqs = Organization.list_sequences(scope, year)
    [seq, seq2 | _] = seqs

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e A", level: "3ème"})
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "4e B", level: "4ème"})

    {:ok, s1} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, _s3} = Enrollment.add_student(scope, cg, %{full_name: "Carl", sex: :m})
    {:ok, _t1} = Enrollment.add_student(scope, cg2, %{full_name: "Dina", sex: :f})

    english = TeacherFixtures.member_scope_fixture(scope).current_user

    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Curriculum.assign_teacher(scope, cg, english, %{subject: "Anglais"})
    {:ok, _} = Curriculum.assign_teacher(scope, cg2, english, %{subject: "Anglais"})

    {:ok, a1} = Assessment.create_assessment(scope, tc, seq, %{label: "Interro 1"})
    {:ok, a2} = Assessment.create_assessment(scope, tc, seq, %{label: "Devoir 1"})

    :ok =
      Assessment.upsert_marks(scope, a1, [
        %{student_id: s1.id, score: Decimal.new(10)},
        %{student_id: s2.id, status: :absent}
      ])

    :ok = Assessment.upsert_marks(scope, a2, [%{student_id: s1.id, score: Decimal.new(12)}])

    %{seq: seq, seq2: seq2, seqs: seqs, cg: cg, cg2: cg2, english: english, head: head}
  end

  defp col(view, cg, label) do
    # Column index of `label` in the grid header.
    html = view |> element("#entry-grid") |> render()

    headers =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-subject]")
      |> Enum.map(&LazyHTML.text/1)
      |> Enum.map(&String.trim/1)

    n = Enum.find_index(headers, &(&1 == label))
    "#cell-#{cg.id}-#{n}"
  end

  test "a teacher is sent back to /school", %{scope: scope, workspace: school} do
    teacher = TeacherFixtures.member_scope_fixture(scope).current_user

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school", flash: %{"error" => _}}}} =
             live(conn, ~p"/school/sequences")
  end

  test "the censorat sees KPIs and the classes × subjects grid", %{conn: conn} = ctx do
    {:ok, view, html} = live(conn, ~p"/school/sequences")

    assert html =~ "Suivi des séquences"
    # Maths 3e A 50, Anglais 3e A 0, Anglais 4e B 0
    assert view |> element("#kpi-overall") |> render() =~ "16"
    assert view |> element("#kpi-complete") |> render() =~ ~r/0\s*\/\s*\d+/
    assert view |> element("#kpi-late") |> render() =~ "1"
    assert has_element?(view, "#kpi-council")

    assert view |> element(col(view, ctx.cg, "Maths")) |> render() =~ "50%"
    # 4e B does not take Maths: a dashed, non-clickable cell.
    assert has_element?(view, "#{col(view, ctx.cg2, "Maths")}.border-dashed")
    refute has_element?(view, "#cell-detail")
  end

  test "clicking a cell shows its detail", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences")

    view |> element(col(view, ctx.cg, "Maths")) |> render_click()

    detail = view |> element("#cell-detail") |> render()
    assert detail =~ "Notes saisies"
    assert detail =~ ~r/3\s*\/\s*6/
    assert detail =~ ctx.head.email |> to_string()
    assert detail =~ "Interro 1"
    assert detail =~ "Devoir 1"
    assert detail =~ "Dernière saisie"
  end

  test "late teachers are listed without reminder buttons", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences")

    late = view |> element("#late-teachers") |> render()
    assert late =~ to_string(ctx.english.email)
    assert late =~ "Anglais · 3e A, 4e B · rien saisi"
    refute late =~ "<button"
  end

  test "?seq= selects a séquence; an unknown one falls back", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=#{ctx.seq2.id}")
    assert has_element?(view, "#seq-tab-#{ctx.seq2.number}[aria-current]")
    refute has_element?(view, "#seq-tab-#{ctx.seq.number}[aria-current]")

    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=garbage")
    assert has_element?(view, "#seq-tab-#{ctx.seq.number}[aria-current]")

    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=#{Ecto.UUID.generate()}")
    assert has_element?(view, "#seq-tab-#{ctx.seq.number}[aria-current]")
  end

  test "switching tabs patches the URL", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences")

    view |> element("#seq-tab-#{ctx.seq2.number}") |> render_click()
    assert_patch(view, ~p"/school/sequences?seq=#{ctx.seq2.id}")
    assert has_element?(view, "#seq-tab-#{ctx.seq2.number}[aria-current]")
  end

  test "a school without séquences shows an empty state" do
    %{workspace: school, head_user: head, scope: scope, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    scope |> Organization.list_sequences(year) |> Enum.each(&Ash.destroy!(&1, scope: scope))

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, head.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/sequences")
    assert has_element?(view, "#no-sequences")
    refute has_element?(view, "#entry-grid")
  end
end
