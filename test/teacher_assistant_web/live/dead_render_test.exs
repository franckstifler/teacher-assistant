defmodule TeacherAssistantWeb.DeadRenderTest do
  @moduledoc """
  The six heaviest pages read their data once, on the connected render (A8): the
  first HTTP render shows a loading panel and reads no marks; the connected one shows
  the page.
  """
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Curriculum, Enrollment, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, actor: head} do
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    %{tc: tc, cg: cg}
  end

  defp dead(conn, path) do
    {conn, _total, counts} =
      TeacherAssistant.QueryCount.count(fn -> get(conn, path) end, [~s(FROM "marks")])

    {html_response(conn, 200), counts[~s(FROM "marks")]}
  end

  for {name, id} <- [
        {"dashboard", "dashboard-loading"},
        {"bulletins", "bulletins-loading"},
        {"sequences", "sequence-tracking-loading"},
        {"day", "day-loading"},
        {"students", "students-loading"},
        {"marks", "marks-loading"}
      ] do
    @tag page: name
    test "#{name}: the dead render shows the loading panel and reads no marks", ctx do
      path = page_path(ctx, unquote(name))
      {html, marks} = dead(ctx.conn, path)
      assert html =~ ~s(id="#{unquote(id)}")
      assert html =~ "Chargement…"
      assert marks == 0

      {:ok, _view, connected} = live(ctx.conn, path)
      refute connected =~ ~s(id="#{unquote(id)}")
    end
  end

  defp page_path(_ctx, "dashboard"), do: ~p"/school"
  defp page_path(_ctx, "bulletins"), do: ~p"/school/bulletins"
  defp page_path(_ctx, "sequences"), do: ~p"/school/sequences"
  defp page_path(_ctx, "day"), do: ~p"/school/day"
  defp page_path(_ctx, "students"), do: ~p"/school/students"
  defp page_path(ctx, "marks"), do: ~p"/teacher/contexts/#{ctx.tc.id}/marks"

  test "a member without the conduct rights is still sent away from the day view", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.workspace.id)

    assert {:error, {_, %{to: _}}} = live(conn, ~p"/school/day")
  end
end
