defmodule TeacherAssistantWeb.School.AbsenceTotalsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Academics.TypedAbsence
  alias TeacherAssistant.{Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, workspace: ws} do
    scope = %{scope | current_academic_year: year}
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob Eto", sex: :m})
    [%{enrollment: awa}, %{enrollment: bob}] = Enrollment.list_roster(scope, cg)
    [t1 | _] = Organization.list_terms(scope, year)
    [s1 | _] = Enum.sort_by(t1.sequences, & &1.position_in_term)
    %{scope: scope, ws: ws, year: year, cg: cg, awa: awa, bob: bob, t1: t1, s1: s1}
  end

  # Awa: 25 h typed for the first séquence; Bob: no figure.
  defp typed_awa(ctx) do
    {:ok, cg} = Enrollment.set_absence_hours_source(ctx.scope, ctx.cg, :typed_per_sequence)

    {:ok, _} =
      TypedAbsence
      |> Ash.Changeset.for_create(
        :set_for_sequence,
        %{enrollment_id: ctx.awa.id, sequence_id: ctx.s1.id, hours: Decimal.new(25)},
        scope: ctx.scope
      )
      |> Ash.create()

    cg
  end

  defp path(params), do: ~p"/school/absence-totals?#{params}"

  test "lists every student of one class with source and figures", ctx do
    {:ok, view, _} = live(ctx.conn, path(class: ctx.cg.id, period: "seq:#{ctx.s1.id}"))

    assert has_element?(view, "#absence-row-#{ctx.awa.id}", "Awa Ngo")
    assert has_element?(view, "#absence-row-#{ctx.bob.id}", "Bob Eto")
    assert has_element?(view, "#absence-source-#{ctx.cg.id}", "appel")
  end

  test "a typed class names its source, marks a flagged student and an unrecorded one", ctx do
    typed_awa(ctx)
    {:ok, view, _} = live(ctx.conn, path(class: ctx.cg.id, period: "seq:#{ctx.s1.id}"))

    assert has_element?(view, "#absence-source-#{ctx.cg.id}", "saisi")
    assert has_element?(view, "#absence-row-#{ctx.awa.id}[data-flagged]")
    refute has_element?(view, "#absence-row-#{ctx.bob.id}[data-flagged]")
    assert has_element?(view, "#absence-row-#{ctx.bob.id}", "non saisi")
  end

  test "all classes shows only students at or over the threshold", ctx do
    typed_awa(ctx)
    {:ok, view, _} = live(ctx.conn, path(period: "seq:#{ctx.s1.id}"))

    assert has_element?(view, "#absence-class-#{ctx.cg.id} #absence-row-#{ctx.awa.id}")
    refute has_element?(view, "#absence-row-#{ctx.bob.id}")
    # Every class names its source, here too.
    assert has_element?(view, "#absence-source-#{ctx.cg.id}", "saisi")

    {:ok, view, _} = live(ctx.conn, path(period: "seq:#{ctx.s1.id}", seuil: "30"))
    assert has_element?(view, "#absence-empty", "Aucun élève au-dessus du seuil")
  end

  test "a trimester pre-fills 20 h per séquence", ctx do
    {:ok, view, _} = live(ctx.conn, path(period: "trim:#{ctx.t1.id}"))
    expected = Integer.to_string(20 * length(ctx.t1.sequences))

    assert has_element?(view, "#absence-threshold[value='#{expected}']")
    assert has_element?(view, "#absence-threshold-line", "20 h × #{length(ctx.t1.sequences)}")
  end

  test "changing the pickers patches the URL", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/absence-totals")

    view
    |> form("#absence-totals-form", %{period: "annee", class: ctx.cg.id, seuil: "5"})
    |> render_change()

    assert_patch(view, path(period: "annee", class: ctx.cg.id, seuil: "5"))
  end

  test "a new period starts from its own default threshold", ctx do
    {:ok, view, _} = live(ctx.conn, path(period: "seq:#{ctx.s1.id}"))

    # The form sends the threshold shown (the séquence's 20 h) with the new period.
    view
    |> form("#absence-totals-form", %{period: "trim:#{ctx.t1.id}", class: "", seuil: "20"})
    |> render_change()

    assert_patch(view, path(period: "trim:#{ctx.t1.id}"))
    expected = Integer.to_string(20 * length(ctx.t1.sequences))
    assert has_element?(view, "#absence-threshold[value='#{expected}']")
  end

  test "a typed threshold is kept when the period changes", ctx do
    {:ok, view, _} = live(ctx.conn, path(period: "seq:#{ctx.s1.id}", seuil: "5"))

    view
    |> form("#absence-totals-form", %{period: "annee", class: "", seuil: "5"})
    |> render_change()

    assert_patch(view, path(period: "annee", seuil: "5"))
  end

  test "a threshold change re-filters without changing the figures", ctx do
    typed_awa(ctx)
    {:ok, view, _} = live(ctx.conn, path(period: "seq:#{ctx.s1.id}"))
    assert has_element?(view, "#absence-row-#{ctx.awa.id}")

    view
    |> form("#absence-totals-form", %{period: "seq:#{ctx.s1.id}", class: "", seuil: "30"})
    |> render_change()

    refute has_element?(view, "#absence-row-#{ctx.awa.id}")
    assert has_element?(view, "#absence-empty")
  end

  test "a non-finite threshold falls back to the default", ctx do
    {:ok, view, _} = live(ctx.conn, path(period: "seq:#{ctx.s1.id}", seuil: "inf"))
    assert has_element?(view, "#absence-threshold[value='20']")
  end

  test "a foreign class id falls back to all classes", ctx do
    {:ok, view, _} = live(ctx.conn, path(class: Ecto.UUID.generate()))

    assert has_element?(view, "#absence-class-select option[value=''][selected]")
  end

  test "the print link carries the pickers", ctx do
    {:ok, view, _} = live(ctx.conn, path(class: ctx.cg.id, period: "seq:#{ctx.s1.id}"))

    assert has_element?(
             view,
             "#absence-print[href^='/school/absence-totals/print?'][href*='class=#{ctx.cg.id}'][href*='period=seq']"
           )
  end

  test "a teacher is refused", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]}).current_user

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(teacher)
      |> Plug.Conn.put_session(:workspace_id, ctx.ws.id)

    assert {:error, {_kind, %{to: "/school"}}} = live(conn, ~p"/school/absence-totals")
  end

  test "a year without séquences shows an empty state" do
    %{workspace: school, head_user: head, scope: scope, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    scope |> Organization.list_sequences(year) |> Enum.each(&Ash.destroy!(&1, scope: scope))

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(head)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _} = live(conn, ~p"/school/absence-totals")
    assert has_element?(view, "#absence-no-sequences")
  end
end
