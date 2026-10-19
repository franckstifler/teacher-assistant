defmodule TeacherAssistantWeb.School.AvailabilityLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    _ = Attendance.build_default_periods(scope)
    lessons = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    teacher = TeacherFixtures.member_scope_fixture(scope).current_user
    %{scope: scope, year: year, lessons: lessons, teacher: teacher}
  end

  defp blocked(scope, teacher),
    do:
      scope
      |> Timetabling.unavailability()
      |> Enum.filter(&(elem(&1, 0) == teacher.id))
      |> MapSet.new(fn {_, d, p} -> {d, p} end)

  defp afternoon(lessons),
    do: Enum.filter(lessons, &(Time.compare(&1.start_time, ~T[13:00:00]) != :lt))

  test "a plain teacher is redirected", %{scope: scope, teacher: teacher} do
    conn =
      build_conn()
      |> log_in_user(teacher)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/timetable/availability")
  end

  test "picking a teacher and toggling a cell blocks then unblocks it", ctx do
    %{conn: conn, scope: scope, teacher: t, lessons: [p1 | _]} = ctx
    {:ok, view, _} = live(conn, ~p"/school/timetable/availability?teacher=#{t.id}")
    assert has_element?(view, "#teacher-#{t.id}")

    view |> element("#avail-monday-#{p1.id}") |> render_click()
    assert blocked(scope, t) == MapSet.new([{:monday, p1.id}])
    assert has_element?(view, "#avail-monday-#{p1.id}.blocked")

    view |> element("#avail-monday-#{p1.id}") |> render_click()
    assert blocked(scope, t) == MapSet.new()
  end

  test "the day header blocks every open period of the day; again unblocks", ctx do
    %{conn: conn, scope: scope, teacher: t, lessons: lessons} = ctx
    {:ok, view, _} = live(conn, ~p"/school/timetable/availability?teacher=#{t.id}")

    view |> element("#avail-day-tuesday") |> render_click()
    assert blocked(scope, t) == MapSet.new(lessons, &{:tuesday, &1.id})
    assert has_element?(view, "#teacher-#{t.id}", "Indisponible : mardi")

    view |> element("#avail-day-tuesday") |> render_click()
    assert blocked(scope, t) == MapSet.new()
  end

  test "afternoon blocks only periods from 13:00; the summary reads « mercredi après-midi »",
       ctx do
    %{conn: conn, scope: scope, teacher: t, lessons: lessons} = ctx
    {:ok, view, _} = live(conn, ~p"/school/timetable/availability?teacher=#{t.id}")

    view |> element("#avail-afternoon-wednesday") |> render_click()
    assert blocked(scope, t) == MapSet.new(afternoon(lessons), &{:wednesday, &1.id})
    assert has_element?(view, "#teacher-#{t.id}", "Indisponible : mercredi après-midi")
  end

  test "a cell holding the teacher's lesson shows the class label and can still be blocked",
       ctx do
    %{conn: conn, scope: scope, teacher: t, lessons: [p1 | _]} = ctx
    {:ok, cg} = Enrollment.create_class_group(scope, ctx.year, %{label: "4e B", level: "4ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, t, %{subject: "Maths"})

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable/availability?teacher=#{t.id}")
    assert has_element?(view, "#avail-monday-#{p1.id}", "4e B")
    view |> element("#avail-monday-#{p1.id}") |> render_click()
    assert blocked(scope, t) == MapSet.new([{:monday, p1.id}])
  end

  test "a crafted teacher id from another school falls back, and a crafted toggle writes nothing",
       ctx do
    %{conn: conn, scope: scope, lessons: [p1 | _]} = ctx
    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()
    stranger = TeacherFixtures.member_scope_fixture(other).current_user

    {:ok, view, _} = live(conn, ~p"/school/timetable/availability?teacher=#{stranger.id}")
    refute has_element?(view, "#teacher-#{stranger.id}")

    render_click(view, "toggle", %{"teacher" => stranger.id, "day" => "monday", "period" => p1.id})

    assert Timetabling.unavailability(scope) == MapSet.new()
  end
end
