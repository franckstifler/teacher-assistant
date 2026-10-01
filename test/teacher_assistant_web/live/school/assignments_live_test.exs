defmodule TeacherAssistantWeb.School.AssignmentsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Curriculum, Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

    :ok =
      Curriculum.update_coefficient_grid(scope, %{
        "cells" => %{maths.id => %{Curriculum.cell_token({:francophone, "6ème", nil}) => "4"}},
        "groups" => %{}
      })

    other = TeacherFixtures.membership_fixture(scope)
    %{scope: scope, cg: cg, maths: maths, other: other}
  end

  test "settings links to the grid; an unassigned grid subject reads À affecter",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#assignments-link")
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    assert has_element?(view, "#cell-#{ctx.cg.id}-#{ctx.maths.id}", "À affecter")
    assert has_element?(view, "#pp-#{ctx.cg.id}", "Sans professeur principal")
  end

  test "assigns from the panel with its hours, then removes", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> element("#cell-#{ctx.cg.id}-#{ctx.maths.id}") |> render_click()
    view |> form("#hours-form", %{hours: "5"}) |> render_change()
    view |> element("#pick-#{ctx.other.user_id}") |> render_click()

    tc = Curriculum.assignment_at(ctx.scope, ctx.cg, ctx.maths.id)
    assert tc.teacher_user_id == ctx.other.user_id
    assert tc.weekly_hours == 5
    assert has_element?(view, "#load-#{ctx.other.user_id}")

    view |> element("#remove-assignment") |> render_click()
    assert Curriculum.assignment_at(ctx.scope, ctx.cg, ctx.maths.id) == nil
  end

  test "removing an assignment with marks is refused", %{conn: conn} = ctx do
    {:ok, tc} = Curriculum.place_assignment(ctx.scope, ctx.cg, ctx.maths, ctx.other.user_id, "4")
    [seq | _] = Organization.list_sequences(ctx.scope, ctx.scope.current_academic_year)

    {:ok, _} =
      TeacherAssistant.Assessment.create_assessment(ctx.scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> element("#cell-#{ctx.cg.id}-#{ctx.maths.id}") |> render_click()
    view |> element("#remove-assignment") |> render_click()
    assert has_element?(view, "#panel-error", "des notes ou une progression existent")
    assert Curriculum.assignment_at(ctx.scope, ctx.cg, ctx.maths.id)
  end

  test "sets the form master from the grid", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> element("#pp-#{ctx.cg.id}") |> render_click()
    view |> element("#pp-pick-#{ctx.other.user_id}") |> render_click()
    {:ok, cg} = Enrollment.fetch_owned_class_group(ctx.scope, ctx.cg.id)
    assert cg.form_master_user_id == ctx.other.user_id
  end

  test "saves the school's statutory service", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> form("#service-form", %{service: "20"}) |> render_submit()
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)
    assert profile.statutory_hours == 20
  end

  test "a plain teacher is sent back to settings", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(conn, ~p"/school/settings/assignments")
  end
end
