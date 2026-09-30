defmodule TeacherAssistantWeb.Teacher.MarksLockTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.MarksFixtures

  setup %{conn: conn} do
    world = MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    conn =
      conn
      |> log_in_user(world.t.current_user)
      |> Plug.Conn.put_session(:workspace_id, world.head.current_workspace.id)

    path = ~p"/teacher/contexts/#{world.tc.id}/marks?seq=#{world.seq.id}&assessment=#{world.a.id}"
    Map.merge(world, %{conn: conn, path: path})
  end

  test "an open séquence is editable", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)
    refute has_element?(view, "#locked-banner")
    assert has_element?(view, "#marks-submit")
    assert has_element?(view, "#new-assessment-form")
    refute has_element?(view, "#mark-input-#{ctx.s1.id}[disabled]")
  end

  test "a locked séquence is read-only and points to a correction request", ctx do
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), -1))
    {:ok, view, _} = live(ctx.conn, ctx.path)

    assert view |> element("#locked-banner") |> render() =~ "verrouillée"
    assert has_element?(view, "#locked-request-link")
    assert has_element?(view, "#mark-input-#{ctx.s1.id}[disabled]")
    assert has_element?(view, "#marks-sheet-header", "verrouillée")
    refute has_element?(view, "#marks-submit")
    refute has_element?(view, "#new-assessment-form")

    html = render_submit(view, "save", %{"scores" => %{ctx.s1.id => "3"}})
    assert html =~ "Séquence verrouillée."
    [mark] = Assessment.list_marks(ctx.head, ctx.a)
    assert Decimal.equal?(mark.score, 12)
  end
end
