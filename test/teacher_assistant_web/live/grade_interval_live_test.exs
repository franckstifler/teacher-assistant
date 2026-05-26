defmodule TeacherAssistantWeb.GradeIntervalLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  require Ash.Query

  describe "Index" do
    setup [:register_and_log_in_user]

    test "admin creates and deletes grade intervals", %{conn: conn, tenant: tenant, actor: actor} do
      {:ok, view, _html} = live(conn, "/configurations/grade_intervals")

      assert has_element?(view, "#grade-interval-form")
      assert has_element?(view, "#grade-intervals")

      assert view
             |> form("#grade-interval-form",
               grade_interval: %{
                 min_score: "16",
                 max_score: "20",
                 label: "Excellent",
                 appreciation: "Very good mastery",
                 position: "1"
               }
             )
             |> render_submit()

      interval =
        TeacherAssistant.Academics.GradeInterval
        |> Ash.Query.filter(label == "Excellent")
        |> Ash.read_one!(tenant: tenant, actor: actor)

      assert has_element?(view, "#grade-interval-#{interval.id}")

      assert view
             |> element("#grade-interval-#{interval.id} button", "Delete")
             |> render_click()

      refute has_element?(view, "#grade-interval-#{interval.id}")
    end
  end
end
