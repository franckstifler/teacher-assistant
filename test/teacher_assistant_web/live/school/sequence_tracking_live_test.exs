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

  test "the censorat sees the classes × subjects grid, without KPI tiles", %{conn: conn} = ctx do
    {:ok, view, html} = live(conn, ~p"/school/sequences")

    assert html =~ "Suivi de la saisie des notes"
    refute has_element?(view, "#tracking-kpis")
    refute has_element?(view, "#kpi-overall")

    assert view |> element(col(view, ctx.cg, "Maths")) |> render() =~ "50 %"
    assert view |> element(col(view, ctx.cg, "Anglais")) |> render() =~ "0 %"
    # 4e B does not take Maths: a dashed, non-clickable cell.
    assert has_element?(view, "#{col(view, ctx.cg2, "Maths")}.border-dashed")
    # as in the mockup, the first incomplete course is selected on arrival
    assert has_element?(view, "#cell-detail")
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

  test "séquence tabs name their state", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
    assert has_element?(view, "#seq-tab-#{ctx.seq.id}", "en cours")
    assert has_element?(view, "#seq-tabs")
  end

  test "late courses are listed per teacher with a per-teacher and a global button",
       %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")

    assert has_element?(view, "#late-#{ctx.english.id}", "Anglais")
    assert has_element?(view, "#late-#{ctx.english.id}", "3e A (0 %)")
    assert has_element?(view, "#late-#{ctx.english.id}", "4e B (0 %)")
    assert has_element?(view, "#late-#{ctx.head.id}", "Maths")
    assert has_element?(view, "#late-#{ctx.head.id}", "(50 %)")
    assert has_element?(view, "#late-teachers #remind-late")
    refute render(view) =~ "chaque cours a au moins une note"
  end

  test "a complete cell shows ✓", %{conn: conn, scope: scope} = ctx do
    {:ok, a} = Assessment.create_assessment(scope, ctx.tc4, ctx.seq, %{label: "Contrôle"})
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: ctx.t1.id, score: Decimal.new(14)}])

    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
    assert view |> element(col(view, ctx.cg2, "Anglais")) |> render() =~ "✓"
  end

  test "« Relancer » per teacher notifies once and flips to Relancé", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")

    html = view |> element("#remind-teacher-#{ctx.english.id}") |> render_click()
    assert html =~ "2 rappels envoyés"
    assert has_element?(view, "#remind-teacher-#{ctx.english.id}", "Relancé")
    assert %{unread: 2} = Notifications.bell(english_scope(ctx))
    # the other teacher is untouched
    refute has_element?(view, "#remind-teacher-#{ctx.head.id}", "Relancé")
  end

  test "remind-teacher ignores a teacher who is not late", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
    render_click(view, "remind-teacher", %{"teacher" => Ecto.UUID.generate()})
    assert %{unread: 0} = Notifications.bell(english_scope(ctx))
    refute render(view) =~ "rappel"
  end

  test "?seq= selects a séquence; an unknown one falls back", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=#{ctx.seq2.id}")
    assert has_element?(view, "#seq-tab-#{ctx.seq2.id}[aria-current]")
    refute has_element?(view, "#seq-tab-#{ctx.seq.id}[aria-current]")

    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=garbage")
    assert has_element?(view, "#seq-tab-#{ctx.seq.id}[aria-current]")

    {:ok, view, _html} = live(conn, ~p"/school/sequences?seq=#{Ecto.UUID.generate()}")
    assert has_element?(view, "#seq-tab-#{ctx.seq.id}[aria-current]")
  end

  test "switching tabs patches the URL", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/sequences")

    view |> element("#seq-tab-#{ctx.seq2.id}") |> render_click()
    assert_patch(view, ~p"/school/sequences?seq=#{ctx.seq2.id}")
    assert has_element?(view, "#seq-tab-#{ctx.seq2.id}[aria-current]")
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
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
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

  test "« Relancer tous les retards » reminds each lagging course, once",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")

    html = view |> element("#remind-late") |> render_click()
    # Anglais 3e A, Anglais 4e B and Maths 3e A (50 %).
    assert html =~ "3 rappels envoyés"
    assert %{unread: 2} = Notifications.bell(english_scope(ctx))

    html = view |> element("#remind-late") |> render_click()
    assert html =~ "Aucune nouvelle relance"
    assert %{unread: 2} = Notifications.bell(english_scope(ctx))
  end
end
