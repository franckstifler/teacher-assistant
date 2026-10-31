defmodule TeacherAssistantWeb.School.TimetableEditorLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Enrollment,
    Organization,
    Timetabling,
    TeacherFixtures
  }

  setup :register_and_log_in_user

  setup %{scope: scope, actor: head} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    _ = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})
    {:ok, ma} = Curriculum.assign_teacher(scope, a, head, %{subject: "Maths"})
    {:ok, mb} = Curriculum.assign_teacher(scope, b, head, %{subject: "Maths"})
    %{scope: scope, a: a, b: b, ma: ma, mb: mb, p1: p1, p2: p2}
  end

  test "tabs, a chip places a lesson, the hours update", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#class-tab-#{ctx.b.id}")
    assert has_element?(view, "#conflict-count", "Aucun conflit")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#chip-#{ctx.ma.id}") |> render_click()
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
    assert has_element?(view, "#hours-#{ctx.ma.id}", "1/")
  end

  test "a clash is saved, shown in red, counted, and fixed by a move", %{conn: conn} = ctx do
    {:ok, _} =
      Timetabling.place_slot(ctx.scope, ctx.b, %{
        day: :monday,
        period_id: ctx.p1.id,
        teaching_context_id: ctx.mb.id
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#chip-#{ctx.ma.id}") |> render_click()

    assert has_element?(view, "#cell-monday-#{ctx.p1.id}.clash-cell")
    assert has_element?(view, "#conflict-count", "1 conflit")
    assert has_element?(view, "#conflict-text", "6e R")

    view |> element("#fix-0") |> render_click()
    assert has_element?(view, "#conflict-count", "Aucun conflit")
  end

  test "a clash names the day and time and can be given to a free teacher",
       %{conn: conn} = ctx do
    free = TeacherFixtures.member_scope_fixture(ctx.scope).current_user

    for {cg, tc} <- [{ctx.b, ctx.mb}, {ctx.a, ctx.ma}],
        do:
          {:ok, _} =
            Timetabling.place_slot(ctx.scope, cg, %{
              day: :monday,
              period_id: ctx.p1.id,
              teaching_context_id: tc.id
            })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()

    assert view |> element("#conflict-text") |> render() =~ "le lundi à #{hm(ctx.p1.start_time)}"

    name = TeacherAssistant.Accounts.User.display_name(free)
    fix = element(view, "#cell-panel button[id^='fix-']", "Confier à #{name}")
    assert render(fix) =~ "0 h / 18 h"
    render_click(fix)

    assert has_element?(view, "#conflict-count", "Aucun conflit")

    assert {:ok, %{teacher_user_id: id}} =
             Ash.get(TeacherAssistant.Academics.TeachingContext, ctx.ma.id, scope: ctx.scope)

    assert id == free.id
  end

  defp hm(t), do: Calendar.strftime(t, "%H:%M")

  test "clearing a cell", %{conn: conn} = ctx do
    {:ok, _} =
      Timetabling.place_slot(ctx.scope, ctx.a, %{
        day: :monday,
        period_id: ctx.p1.id,
        teaching_context_id: ctx.ma.id
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#clear-cell") |> render_click()
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
  end

  test "crafted events on a closed cell or another school's class write nothing",
       %{conn: conn} = ctx do
    {:ok, _} =
      Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(monday tuesday wednesday thursday friday),
        "default_lesson_minutes" => "50"
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    render_hook(view, "select", %{"day" => "saturday", "period" => ctx.p1.id})
    render_hook(view, "place", %{"tc" => ctx.ma.id})
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:saturday, ctx.p1.id}]

    render_hook(view, "select", %{"day" => "monday", "period" => "not-a-uuid"})
    render_hook(view, "place", %{"tc" => ctx.ma.id})
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots == %{}

    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()

    {:ok, foreign} =
      Enrollment.create_class_group(other, Organization.current_academic_year(other), %{
        label: "X",
        level: "6ème"
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{foreign.id}")
    refute has_element?(view, "#class-tab-#{foreign.id}")
  end

  test "a plain teacher is redirected", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/timetable")
  end

  test "the old class page sends an editor to the editor", %{conn: conn} = ctx do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/school/classes/#{ctx.a.id}/timetable")

    assert to == "/school/timetable?class=#{ctx.a.id}"
  end

  test "the grid shows lesson days only and greys Wednesday afternoon (spec J1)",
       %{conn: conn} = ctx do
    {:ok, _} =
      Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(monday tuesday wednesday thursday friday),
        "wednesday_afternoon_off?" => "true",
        "default_lesson_minutes" => "50"
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    refute has_element?(view, "th", "Samedi")

    late =
      Enum.find(
        Attendance.list_periods(ctx.scope),
        &(&1.kind == :lesson and Time.compare(&1.start_time, ~T[13:00:00]) != :lt)
      )

    assert has_element?(view, "#cell-wednesday-#{late.id}.closed-cell", "Fermé")
  end

  test "the editor links to the class timetable print", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, ~s(a[href="/school/classes/#{ctx.a.id}/timetable/print"]))
  end

  test "a combined course is placed and cleared in every member class", %{conn: conn} = ctx do
    {:ok, _course} = Curriculum.combine_course(ctx.scope, [ctx.ma, ctx.mb])
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    assert has_element?(view, "#chip-#{ctx.ma.id}", "regroupé")
    view |> element("#chip-#{ctx.ma.id}") |> render_click()

    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}].teaching_context_id ==
             ctx.ma.id

    assert Timetabling.class_timetable(ctx.scope, ctx.b).slots[{:monday, ctx.p1.id}].teaching_context_id ==
             ctx.mb.id

    assert has_element?(view, "#conflict-count", "Aucun conflit")

    view |> element("#clear-cell") |> render_click()
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
    refute Timetabling.class_timetable(ctx.scope, ctx.b).slots[{:monday, ctx.p1.id}]
  end

  # --- J3: rooms and availability ---------------------------------------------------

  defp place!(ctx, cg, tc, period \\ nil) do
    {:ok, _} =
      Timetabling.place_slot(ctx.scope, cg, %{
        day: :monday,
        period_id: (period || ctx.p1).id,
        teaching_context_id: tc.id
      })
  end

  defp room!(scope, attrs) do
    {:ok, room} = Organization.create_room(scope, attrs)
    room
  end

  defp slot_room(ctx, cg) do
    [slot] = Timetabling.list_for_cell!(cg.id, :monday, ctx.p1.id, scope: ctx.scope)
    slot.room_id
  end

  test "two classes in the computer room at the same time: red, counted, the panel names the other class",
       %{conn: conn} = ctx do
    info = room!(ctx.scope, %{name: "Salle info", kind: :computer_room})
    t1 = TeacherFixtures.member_scope_fixture(ctx.scope).current_user
    t2 = TeacherFixtures.member_scope_fixture(ctx.scope).current_user
    {:ok, ia} = Curriculum.assign_teacher(ctx.scope, ctx.a, t1, %{subject: "Informatique"})
    {:ok, ib} = Curriculum.assign_teacher(ctx.scope, ctx.b, t2, %{subject: "Informatique"})
    subject = Ash.get!(TeacherAssistant.Academics.Subject, ia.subject_id, scope: ctx.scope)
    {:ok, _} = Curriculum.update_subject(ctx.scope, subject, %{default_room_id: info.id})
    place!(ctx, ctx.a, ia)
    place!(ctx, ctx.b, ib)

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#cell-monday-#{ctx.p1.id}.clash-cell", "Salle info")
    assert has_element?(view, "#conflict-count", "1 conflit")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    assert has_element?(view, "#room-conflict-text", "Salle info est déjà occupée par 6e R.")
  end

  test "a lesson placed at the teacher's unavailable time: red, counted, named",
       %{conn: conn} = ctx do
    :ok = Timetabling.set_unavailable(ctx.scope, ctx.actor.id, [{:monday, ctx.p1.id}], true)
    place!(ctx, ctx.a, ctx.ma)

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#cell-monday-#{ctx.p1.id}.clash-cell")
    assert has_element?(view, "#conflict-count", "1 conflit")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()

    assert view |> element("#unavailable-text") |> render() =~
             "n&#39;est pas disponible le lundi à #{hm(ctx.p1.start_time)}."
  end

  test "a class larger than a shared room: amber capacity line, count unchanged",
       %{conn: conn} = ctx do
    labo = room!(ctx.scope, %{name: "Labo", kind: :laboratory, capacity: 1})
    {:ok, _} = Enrollment.enroll_new(ctx.scope, ctx.a, %{full_name: "Awa A", sex: :f})
    {:ok, _} = Enrollment.enroll_new(ctx.scope, ctx.a, %{full_name: "Bel B", sex: :m})
    place!(ctx, ctx.a, ctx.ma)
    :ok = Timetabling.set_slot_room(ctx.scope, ctx.a, {:monday, ctx.p1.id}, labo.id)

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#cell-monday-#{ctx.p1.id}.capacity-cell")
    assert has_element?(view, "#conflict-count", "Aucun conflit")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    assert has_element?(view, "#capacity-text", "2 élèves pour 1 places en Labo.")
  end

  test "the room select moves the lesson to a shared room and back to the home room",
       %{conn: conn} = ctx do
    labo = room!(ctx.scope, %{name: "Labo", kind: :laboratory})
    b12 = room!(ctx.scope, %{name: "B12"})
    {:ok, _} = Enrollment.set_home_room(ctx.scope, ctx.a, b12.id)
    place!(ctx, ctx.a, ctx.ma)

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    assert has_element?(view, "#room-select option", "Salle de la classe (B12)")

    view |> form("#room-select", %{room_id: labo.id}) |> render_change()
    assert slot_room(ctx, ctx.a) == labo.id
    assert has_element?(view, "#cell-monday-#{ctx.p1.id}", "Labo")

    view |> form("#room-select", %{room_id: ""}) |> render_change()
    assert slot_room(ctx, ctx.a) == nil
  end

  test "a move fix for an unavailable lesson lands on an available time", %{conn: conn} = ctx do
    :ok = Timetabling.set_unavailable(ctx.scope, ctx.actor.id, [{:monday, ctx.p1.id}], true)
    place!(ctx, ctx.a, ctx.ma)

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#fix-0") |> render_click()

    assert has_element?(view, "#conflict-count", "Aucun conflit")
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
  end

  test "a crafted set_room with another school's room id changes nothing", %{conn: conn} = ctx do
    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, foreign} = Organization.create_room(other, %{name: "Ailleurs"})
    place!(ctx, ctx.a, ctx.ma)

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    render_change(view, "set_room", %{"room_id" => foreign.id})
    assert slot_room(ctx, ctx.a) == nil
  end

  test "the header links to the availability page", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#availability-link[href='/school/timetable/availability']")
  end

  test "the room select shows a lesson's room even after the room was deactivated",
       %{conn: conn} = ctx do
    labo = room!(ctx.scope, %{name: "Labo", kind: :laboratory})
    place!(ctx, ctx.a, ctx.ma)
    :ok = Timetabling.set_slot_room(ctx.scope, ctx.a, {:monday, ctx.p1.id}, labo.id)
    {:ok, _} = Organization.update_room(ctx.scope, labo, %{active?: false})

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    assert has_element?(view, "#room-select option[selected]", "Labo")
  end

  test "offers every teacher's timetable to print", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#print-teachers[href='/school/timetable/teachers/print']")
  end

  test "offers the school-wide timetable to print", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#print-general[href='/school/timetable/general/print']")
  end
end
