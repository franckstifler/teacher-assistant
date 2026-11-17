defmodule TeacherAssistantWeb.School.MemberProfileLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{
    Accounts,
    Attendance,
    Curriculum,
    Enrollment,
    Organization,
    TeacherFixtures,
    Timetabling
  }

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Teacher profile"
      })

    scope = school_scope(head, school)
    TeacherFixtures.complete_school_setup!(scope)
    scope = school_scope(head, school)
    class = hd(Enrollment.list_class_groups(scope, scope.current_academic_year))

    {:ok, %{user: teacher}} =
      Accounts.add_member_by_phone(scope, %{
        name: "Awa Profile",
        phone: "677123456",
        roles: [:teacher]
      })

    {:ok, membership} = Accounts.fetch_school_membership(scope, teacher)

    {:ok, tc} =
      Curriculum.assign_teacher(scope, class, teacher, %{
        subject: "Sciences du profil",
        weekly_hours: 4
      })

    :ok = Attendance.build_default_periods(scope)
    p = Enum.find(Attendance.list_periods(scope), &(&1.kind == :lesson))
    {:ok, room} = Organization.create_room(scope, %{name: "Salle du profil"})
    {:ok, _} = Enrollment.set_home_room(scope, class, room.id)

    {:ok, _} =
      Timetabling.place_slot(scope, class, %{
        day: :monday,
        period_id: p.id,
        teaching_context_id: tc.id
      })

    conn = post(conn, ~p"/workspaces/select/#{school.id}")

    %{
      conn: conn,
      scope: scope,
      school: school,
      member: membership,
      teacher: teacher,
      class: class
    }
  end

  defp open(conn, member) do
    {:ok, view, _} = live(conn, ~p"/school/members")
    view |> element("#member-open-#{member.id}") |> render_click()
    view
  end

  test "overview includes assignments, hours and contact shortcuts", c do
    view = open(c.conn, c.member)
    assert has_element?(view, "#member-tab-overview[aria-selected=true]")
    refute has_element?(view, "#member-panel-overview[hidden]")
    assert has_element?(view, "#member-panel-settings[hidden]")
    assert has_element?(view, "#member-assignments", "Sciences du profil")
    assert has_element?(view, "#member-assignments a[href='/school/classes/#{c.class.id}']")
    assert has_element?(view, "#member-assigned-hours", "4 h/sem.")
    assert has_element?(view, "#member-scheduled-hours", "1 h/sem.")
    assert has_element?(view, "#member-missing-hours", "3 h restent")
    assert has_element?(view, "#member-call[href='tel:+237677123456']")
    assert has_element?(view, "#member-copy-phone")
    refute has_element?(view, "#member-drawer button[form=member-form]")
  end

  test "timetable shows lessons, room and individual print link", c do
    view = open(c.conn, c.member)
    view |> element("#member-tab-timetable") |> render_click()
    assert has_element?(view, "#member-tab-timetable[aria-selected=true]")
    refute has_element?(view, "#member-panel-timetable[hidden]")
    assert has_element?(view, "#member-day-lessons", "Sciences du profil")
    assert has_element?(view, "#member-day-lessons", "Salle du profil")
    assert has_element?(view, "#member-week-grid", c.class.label)

    assert has_element?(
             view,
             "#member-print-timetable[href='/school/members/#{c.member.id}/timetable/print']"
           )

    view |> element("#member-day-tuesday") |> render_click()
    assert has_element?(view, "#member-day-lessons", "Aucun cours ce jour")
    render_click(view, "member_day", %{"day" => "invalid"})
    assert has_element?(view, "#member-day-tuesday[aria-pressed=true]")
  end

  test "settings remain mounted and only show save on the settings tab", c do
    view = open(c.conn, c.member)
    view |> element("#member-tab-settings") |> render_click()
    assert has_element?(view, "#member-drawer button[form=member-form]")
    refute has_element?(view, "#member-panel-settings[hidden]")
    assert has_element?(view, "#member-name[value='Awa Profile']")
    view |> element("#member-tab-overview") |> render_click()
    assert has_element?(view, "#member-panel-settings[hidden] #member-form")
    render_click(view, "member_tab", %{"tab" => "unknown"})
    assert has_element?(view, "#member-tab-overview[aria-selected=true]")
  end

  test "changing member resets the tab and does not keep prior assignments", c do
    view = open(c.conn, c.member)
    view |> element("#member-tab-timetable") |> render_click()
    colleague = TeacherFixtures.member_scope_fixture(c.scope, %{roles: [:teacher]})
    # Reopen the page to include the new member in the authorized list.
    {:ok, view, _} = live(c.conn, ~p"/school/members")
    view |> element("#member-open-#{c.member.id}") |> render_click()
    view |> element("#member-tab-settings") |> render_click()
    {:ok, other} = Accounts.fetch_school_membership(c.scope, colleague.current_user)
    render_click(view, "edit_member", %{"id" => other.id})
    assert has_element?(view, "#member-tab-overview[aria-selected=true]")
    assert has_element?(view, "#member-assignments", "Aucune matière affectée")
    refute has_element?(view, "#member-assignments", "Sciences du profil")
    assert has_element?(view, "#member-timetable-empty")
  end

  test "censeur can view teaching data without password or role management", c do
    vp = TeacherFixtures.member_scope_fixture(c.scope, %{roles: [:vice_principal]})

    conn =
      c.conn
      |> recycle()
      |> log_in_user(vp.current_user)
      |> post(~p"/workspaces/select/#{c.school.id}")

    view = open(conn, c.member)
    assert has_element?(view, "#member-assignments", "Sciences du profil")
    view |> element("#member-tab-settings") |> render_click()
    assert has_element?(view, "#member-service")
    refute has_element?(view, "#member-account")
    refute has_element?(view, "#reset-password-#{c.member.id}")
  end

  test "ordinary teacher cannot open another member by crafted event", c do
    ordinary = TeacherFixtures.member_scope_fixture(c.scope, %{roles: [:teacher]})

    conn =
      c.conn
      |> recycle()
      |> log_in_user(ordinary.current_user)
      |> post(~p"/workspaces/select/#{c.school.id}")

    {:ok, view, _} = live(conn, ~p"/school/members")
    render_click(view, "edit_member", %{"id" => c.member.id})
    refute has_element?(view, "#member-drawer")
    render_click(view, "retry_member_profile")
    refute has_element?(view, "#member-drawer")
  end

  test "unknown member ID cannot open a drawer", c do
    {:ok, view, _} = live(c.conn, ~p"/school/members")
    render_click(view, "edit_member", %{"id" => Ash.UUID.generate()})
    refute has_element?(view, "#member-drawer")
  end

  test "profile error leaves settings available and offers retry" do
    html =
      render_component(&TeacherAssistantWeb.School.MemberProfileComponents.academic_panels/1,
        profile: {:error, :unavailable},
        member: %{status: nil},
        tab: "overview",
        day: nil
      )

    assert html =~ "Les informations pédagogiques ne sont pas disponibles"
    assert html =~ "retry_member_profile"
  end
end
