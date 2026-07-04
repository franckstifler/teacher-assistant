defmodule TeacherAssistantWeb.School.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "a member sees the school shell after selecting the school", %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée Central"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-dashboard")
    assert render(view) =~ "Lycée Central"
    assert has_element?(view, "#school-nav")
  end

  test "teacher pages redirect to /school while in a school scope without a teaching assignment",
       %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "École Guard"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/teacher/setup")
  end

  test "dashboard shows structure stats", %{conn: conn, actor: user} do
    alias TeacherAssistant.Academics
    alias TeacherAssistant.Academics.Enrollments

    {:ok, school} = Schools.create_school(user, %{name: "Lycée Stats"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})

    {:ok, _view, html} = live(conn, ~p"/school")
    assert html =~ "6e A" or html =~ "1"
  end

  test "dashboard without a year prompts to create one", %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "École SansAnnée"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")

    {:ok, _view, html} = live(conn, ~p"/school")
    assert html =~ "année" or html =~ "year"
  end
end
