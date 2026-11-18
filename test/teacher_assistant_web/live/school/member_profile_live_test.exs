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
      class: class,
      tc: tc,
      period: p
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

  test "a refusal says so without a retry that cannot succeed" do
    html = render_panels(profile: {:error, :forbidden}, member: %{status: nil, roles: [:teacher]})
    assert html =~ "Vous n&#39;avez pas accès aux informations pédagogiques"
    refute html =~ "retry_member_profile"
  end

  test "the missing-year box is only for teachers" do
    teacher =
      render_panels(profile: {:error, :no_year}, member: %{status: nil, roles: [:teacher]})

    assert teacher =~ "Sélectionnez une année scolaire"

    bursar = render_panels(profile: {:error, :no_year}, member: %{status: nil, roles: [:bursar]})
    refute bursar =~ "Sélectionnez une année scolaire"
    refute bursar =~ "member-panel-timetable"
  end

  defp render_panels(assigns),
    do:
      render_component(
        &TeacherAssistantWeb.School.MemberProfileComponents.academic_panels/1,
        Keyword.merge([tab: "overview", day: nil], assigns)
      )

  test "a member who does not teach has no timetable or assignments, settings still work", c do
    {:ok, %{user: bursar}} =
      Accounts.add_member_by_phone(c.scope, %{
        name: "Paul Intendant",
        phone: "677555444",
        roles: [:bursar]
      })

    {:ok, membership} = Accounts.fetch_school_membership(c.scope, bursar)
    view = open(c.conn, membership)

    refute has_element?(view, "#member-tab-timetable")
    refute has_element?(view, "#member-panel-timetable")
    refute has_element?(view, "#member-assignments")
    refute has_element?(view, "#member-manage-assignments")
    refute has_element?(view, "[data-profile-message]")

    view |> element("#member-tab-settings") |> render_click()

    view
    |> form("#member-form", %{"member" => %{"status" => "titulaire"}})
    |> render_submit()

    refute has_element?(view, "#member-drawer")
    assert has_element?(view, "#member-row-#{membership.id}", "Titulaire")
  end

  test "subjects are grouped once, with each class's placed hours and over-placement flagged",
       c do
    other = Enum.at(Enrollment.list_class_groups(c.scope, c.scope.current_academic_year), 1)

    {:ok, tc2} =
      Curriculum.assign_teacher(c.scope, other, c.teacher, %{
        subject: "Sciences du profil",
        weekly_hours: 1
      })

    for day <- [:tuesday, :wednesday] do
      {:ok, _} =
        Timetabling.place_slot(c.scope, other, %{
          day: day,
          period_id: c.period.id,
          teaching_context_id: tc2.id
        })
    end

    view = open(c.conn, c.member)
    assignments = view |> element("#member-assignments") |> render()
    assert length(String.split(assignments, "Sciences du profil")) == 2
    assert has_element?(view, "#member-assignments [data-subject]", "5 h/sem.")
    assert has_element?(view, "#member-course-#{tc2.id}[data-placement=over]", "2 / 1 h placées")

    assert has_element?(
             view,
             "#member-course-#{c.tc.id}[data-placement=under]",
             "1 / 4 h placées"
           )

    assert has_element?(view, "#member-course-#{tc2.id} a[href='/school/classes/#{other.id}']")
  end

  test "two lessons in the same slot are marked as a clash", c do
    other = Enum.at(Enrollment.list_class_groups(c.scope, c.scope.current_academic_year), 1)

    {:ok, tc2} =
      Curriculum.assign_teacher(c.scope, other, c.teacher, %{subject: "Chimie", weekly_hours: 2})

    {:ok, _} =
      Timetabling.place_slot(c.scope, other, %{
        day: :monday,
        period_id: c.period.id,
        teaching_context_id: tc2.id
      })

    view = open(c.conn, c.member)
    view |> element("#member-tab-timetable") |> render_click()
    assert has_element?(view, "#member-clash-monday-#{c.period.id}", "Conflit d'horaire")
    assert has_element?(view, "#member-day-lessons [data-clash]")
    refute has_element?(view, "#member-clash-tuesday-#{c.period.id}")
  end

  test "the day strip uses short labels and opens on today, a school day", c do
    # The test clock (`Reference.today/0`) is Monday 2025-09-15.
    view = open(c.conn, c.member)
    view |> element("#member-tab-timetable") |> render_click()
    assert has_element?(view, "#member-day-strip[role=group]")
    assert has_element?(view, "#member-day-monday[aria-pressed=true][aria-current=date]", "Lun")
    refute has_element?(view, "#member-day-tuesday[aria-current]")
  end

  test "a phone-only account shows its number once and copies into its own status", c do
    view = open(c.conn, c.member)
    assert has_element?(view, "#member-call", "Appeler")
    refute has_element?(view, "#member-call", "677")
    assert has_element?(view, "#member-copy-status-#{c.member.id}[phx-update=ignore]")

    assert has_element?(
             view,
             "#member-copy-phone[phx-click*='member-copy-status-#{c.member.id}']"
           )

    colleague = TeacherFixtures.member_scope_fixture(c.scope, %{roles: [:teacher]})
    {:ok, other} = Accounts.fetch_school_membership(c.scope, colleague.current_user)
    {:ok, view, _} = live(c.conn, ~p"/school/members")
    view |> element("#member-open-#{c.member.id}") |> render_click()
    render_click(view, "edit_member", %{"id" => other.id})
    assert has_element?(view, "#member-copy-status-#{other.id}")
    refute has_element?(view, "#member-copy-status-#{c.member.id}")
  end
end
