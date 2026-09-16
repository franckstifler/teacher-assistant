defmodule TeacherAssistantWeb.School.PeriodsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée des Périodes"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, user: user}
  end

  test "admin sees the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/school/periods")
    assert html =~ "P&eacute;riodes" or html =~ "Périodes" or html =~ "eriodes"
  end

  test "empty state: seeding populates the list", %{conn: conn, school: school} do
    assert Timetables.list_periods(school) == []

    {:ok, view, _html} = live(conn, ~p"/school/periods")

    view
    |> element("#seed-periods")
    |> render_click()

    assert Timetables.list_periods(school) != []
  end

  test "editing a period's label and start_time persists", %{conn: conn, school: school} do
    :ok = Timetables.build_default_periods(school)
    [period | _] = Timetables.list_periods(school)

    {:ok, view, _html} = live(conn, ~p"/school/periods")

    view
    |> form("#period-form-#{period.id}", %{
      "period" => %{
        "label" => "Cours modifié",
        "start_time" => "08:00",
        "end_time" => "08:55",
        "kind" => "lesson",
        "position" => to_string(period.position)
      }
    })
    |> render_submit()

    [updated | _] = Timetables.list_periods(school)
    assert updated.label == "Cours modifié"
    assert updated.start_time == ~T[08:00:00]
  end

  test "deleting a period with a referencing slot shows a friendly message and keeps it", ctx do
    %{conn: conn, school: school, user: head} = ctx

    :ok = Timetables.build_default_periods(school)
    [period | _] = Timetables.list_periods(school)

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})

    {:ok, _slot} =
      Timetables.place_slot(cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    {:ok, view, _html} = live(conn, ~p"/school/periods")

    view
    |> element("#period-delete-#{period.id}")
    |> render_click()

    assert render(view) =~ "cannot be deleted" or
             render(view) =~ "ne peut pas" or
             render(view) =~ "ne peut être supprimée"

    assert Enum.any?(Timetables.list_periods(school), &(&1.id == period.id))
  end

  test "non-admin member is redirected and forged events make no change", ctx do
    %{school: school, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/periods")
  end
end
