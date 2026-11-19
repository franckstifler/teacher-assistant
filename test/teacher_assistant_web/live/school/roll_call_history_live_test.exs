defmodule TeacherAssistantWeb.School.RollCallHistoryLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{
    Assessment,
    Attendance,
    Curriculum,
    Enrollment,
    Organization,
    TeacherFixtures
  }

  alias TeacherAssistant.Academics.{AttendanceEntry, RollCallHistory}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, actor: head} do
    context =
      TeacherFixtures.assigned_context_fixture(scope, year, %{subject: "Maths", teacher: head})

    {:ok, class} = Enrollment.fetch_owned_class_group(scope, context.class_group_id)
    [first, second | _] = Organization.list_sequences(scope, year)
    :ok = Attendance.build_default_periods(scope)
    [period, next | _] = Enum.filter(Attendance.list_periods(scope), &(&1.kind == :lesson))
    %{context: context, class: class, first: first, second: second, period: period, next: next}
  end

  defp student(scope, class, name, joined) do
    {:ok, student} = Enrollment.add_student(scope, class, %{full_name: name, sex: :f})

    %{enrollment: enrollment} =
      Enum.find(Enrollment.list_roster(scope, class), &(&1.student.id == student.id))

    # Test sequences use a frozen school clock, while insertion uses the real clock.
    Ecto.Adapters.SQL.query!(
      TeacherAssistant.Repo,
      "UPDATE enrollments SET inserted_at = $1 WHERE id = $2",
      [NaiveDateTime.new!(joined, ~T[00:00:00]), Ecto.UUID.dump!(enrollment.id)]
    )

    enrollment
  end

  defp record(scope, context, enrollment, period, date, status, overrides \\ %{}) do
    attrs = %{
      teaching_context_id: context && context.id,
      enrollment_id: enrollment.id,
      period_id: period.id,
      date: date,
      status: status
    }

    AttendanceEntry
    |> Ash.Changeset.for_create(:record, Map.merge(attrs, overrides), scope: scope)
    |> Ash.create!()
  end

  test "shows a sequence ratio based on saved periods for each student", c do
    a = student(c.scope, c.class, "Awa", c.first.start_date)
    b = student(c.scope, c.class, "Bella", c.first.start_date)
    newcomer = student(c.scope, c.class, "Chantal", Date.add(c.first.start_date, 1))
    d = c.first.start_date
    record(c.scope, c.context, a, c.period, d, :present)
    record(c.scope, c.context, a, c.next, d, :late)
    record(c.scope, c.context, b, c.period, d, :absent, %{justified: true})
    record(c.scope, c.context, a, c.period, c.first.end_date, :absent, %{source: :paper})
    record(c.scope, c.context, a, c.next, c.first.end_date, :sent_home)
    record(c.scope, nil, a, c.next, Date.add(d, 2), :present, %{source: :paper})
    record(c.scope, c.context, a, c.period, c.second.start_date, :present)

    {:ok, history} = RollCallHistory.load(c.scope, c.context.id, %{"seq" => c.first.id})
    assert length(history.sessions) == 4
    [awa, bella, chantal] = history.students
    assert %{present: 2, total: 3, late: 1, absent: 1, sent_home: 1} = awa
    assert %{present: 0, total: 1, justified: 1, unmarked: 3} = bella
    assert %{total: 0, unmarked: 2} = chantal
    assert Enum.all?(chantal.history, &(&1.date == c.first.end_date))

    {:ok, courses, _} = live(c.conn, ~p"/school/courses")
    assert has_element?(courses, "#course-roll-calls-#{c.context.id}")

    {:ok, view, _} =
      live(c.conn, ~p"/school/courses/#{c.context.id}/roll-calls?seq=#{c.first.id}")

    assert has_element?(view, "#history-session-#{d}-#{c.period.id}", "Absence justifiée")
    view |> element("#history-view-students") |> render_click()
    assert has_element?(view, "#history-student-#{c.context.id}-#{a.id}", "2/3 présents")
    assert has_element?(view, "#history-student-#{c.context.id}-#{newcomer.id}", "Aucun pointage")
    view |> form("#history-sequence-form", %{"seq" => c.second.id}) |> render_change()
    assert has_element?(view, "#history-student-#{c.context.id}-#{a.id}", "1/1 présents")
  end

  test "repeated absences use saved absent marks in the selected sequence", c do
    date = c.first.start_date
    a = student(c.scope, c.class, "Awa", date)
    b = student(c.scope, c.class, "Bella", date)
    record(c.scope, c.context, a, c.period, date, :absent)
    record(c.scope, c.context, a, c.next, date, :absent, %{justified: true})
    record(c.scope, c.context, a, c.period, Date.add(date, 1), :absent)
    record(c.scope, c.context, a, c.next, Date.add(date, 1), :late)
    record(c.scope, c.context, b, c.period, date, :absent)
    record(c.scope, c.context, b, c.next, date, :absent)
    record(c.scope, c.context, b, c.period, Date.add(date, 1), :sent_home)
    record(c.scope, c.context, b, c.period, c.second.start_date, :absent)

    {:ok, view, _} =
      live(c.conn, ~p"/school/courses/#{c.context.id}/roll-calls?seq=#{c.first.id}&view=students")

    a_row = "#history-student-#{c.context.id}-#{a.id}"
    b_row = "#history-student-#{c.context.id}-#{b.id}"
    assert has_element?(view, b_row)
    view |> element("#history-repeated-absences") |> render_click()
    assert has_element?(view, "#history-repeated-absences[aria-pressed=true]")
    assert has_element?(view, a_row, "1/4 présents")
    assert has_element?(view, a_row, "3 absences (1 justifiées)")
    assert has_element?(view, a_row <> " li", "Absence justifiée")
    refute has_element?(view, b_row)

    view |> form("#history-absence-filter", %{"minimum" => "2"}) |> render_change()
    assert has_element?(view, b_row)
    view |> form("#history-sequence-form", %{"seq" => c.second.id}) |> render_change()
    assert has_element?(view, "#history-absence-empty")
    view |> element("#history-repeated-absences") |> render_click()
    assert has_element?(view, b_row, "0/1 présents")
  end

  test "a dated assessment filters the saved periods and handles a day with no roll call", c do
    a = student(c.scope, c.class, "Awa", c.first.start_date)
    date = Date.add(c.first.start_date, 1)
    empty_date = Date.add(date, 1)
    record(c.scope, c.context, a, c.period, date, :present)
    record(c.scope, c.context, a, c.next, date, :late)

    {:ok, _} =
      Assessment.create_assessment(c.scope, c.context, c.first, %{
        label: "Devoir 1",
        given_on: date
      })

    {:ok, _} =
      Assessment.create_assessment(c.scope, c.context, c.first, %{
        label: "Devoir 2",
        given_on: empty_date
      })

    {:ok, view, _} =
      live(c.conn, ~p"/school/courses/#{c.context.id}/roll-calls?seq=#{c.first.id}")

    view |> element("#history-assessments a", "Devoir 1") |> render_click()
    assert has_element?(view, "#history-session-#{date}-#{c.period.id}")
    assert has_element?(view, "#history-session-#{date}-#{c.next.id}")
    refute has_element?(view, "#history-view-students")
    view |> element("a", "Voir toute la séquence") |> render_click()
    view |> element("#history-assessments a", "Devoir 2") |> render_click()
    assert has_element?(view, "#history-sessions", "Aucun appel enregistré")
  end

  test "combined courses show one period with separate class rosters", c do
    other =
      TeacherFixtures.assigned_context_fixture(c.scope, c.year, %{
        subject: "Maths",
        teacher: c.actor
      })

    {:ok, class} = Enrollment.fetch_owned_class_group(c.scope, other.class_group_id)
    {:ok, _} = Curriculum.combine_course(c.scope, [c.context, other])
    date = c.first.start_date
    a = student(c.scope, c.class, "Awa", date)
    b = student(c.scope, class, "Bella", date)
    record(c.scope, c.context, a, c.period, date, :present)
    record(c.scope, other, b, c.period, date, :late)
    {:ok, history} = RollCallHistory.load(c.scope, c.context.id, %{"seq" => c.first.id})
    assert [%{groups: groups}] = history.sessions
    assert map_size(groups) == 2
    assert [%{present: 1, total: 1}, %{present: 1, total: 1}] = history.students
  end

  test "a colleague in the same school cannot open the history", c do
    teacher = TeacherFixtures.member_scope_fixture(c.scope, %{roles: [:teacher]})
    assert {:error, :not_found} = RollCallHistory.load(teacher, c.context.id, %{})

    conn =
      build_conn()
      |> log_in_user(teacher.current_user)
      |> put_session(:workspace_id, c.workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/courses"}}} =
             live(conn, ~p"/school/courses/#{c.context.id}/roll-calls")
  end

  test "the same account in a different school cannot open the original course", c do
    %{scope: other_scope} = TeacherFixtures.setup_complete_school_fixture(%{head_user: c.actor})
    assert {:error, :not_found} = RollCallHistory.load(other_scope, c.context.id, %{})
  end
end
