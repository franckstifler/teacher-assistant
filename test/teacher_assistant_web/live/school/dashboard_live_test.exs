defmodule TeacherAssistantWeb.School.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  test "a member sees the school shell after selecting the school", %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Central"
      })

    TeacherAssistant.TeacherFixtures.complete_school_setup!(school_scope(user, school))
    conn = post(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#dashboard")
    assert render(view) =~ "Lycée Central"
    assert has_element?(view, "#school-nav")
  end

  test "teacher pages redirect to /school while in a school scope without a teaching assignment",
       %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "École Guard"
      })

    conn = post(conn, ~p"/workspaces/select/#{school.id}")

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end

  # These two tests used to exercise DashboardLive's own inline "no active
  # year" empty state. The `:require_school_setup` on_mount gate now
  # intercepts a school with no active year + class before this LiveView
  # even mounts, redirecting to the wizard instead — so they now assert on
  # the gate's redirect, which is the current form of "prompts to create
  # one" for an incomplete school (regardless of member role).
  test "dashboard without a year redirects to the setup wizard", %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "École SansAnnée"
      })

    conn = post(conn, ~p"/workspaces/select/#{school.id}")

    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school")
  end

  test "a plain teacher member without an active year is also redirected to the setup wizard", %{
    conn: _conn,
    actor: head
  } do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "École SansAnnéeVP"
      })

    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(other)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school")
  end

  describe "Mes classes section" do
    alias TeacherAssistant.Enrollment

    setup %{conn: conn, actor: head} do
      {:ok, school} =
        Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
          name: "Lycée Dash"
        })

      scope = school_scope(head, school)

      {:ok, year} =
        Organization.create_academic_year(scope, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
      conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
      %{conn: conn, school: school, year: year, cg: cg, head: head, scope: scope}
    end

    test "shows Mes classes when the user is a form master", %{
      conn: conn,
      cg: cg,
      head: head,
      scope: scope
    } do
      {:ok, _} = Enrollment.set_form_master(scope, cg, head.id)
      {:ok, _view, html} = live(conn, ~p"/school")
      assert html =~ "Mes classes"
      assert html =~ "6e A"
    end

    test "no Mes classes section when the user is not a form master", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/school")
      refute html =~ "Mes classes"
    end
  end

  describe "verification banner" do
    setup %{conn: conn, actor: head} do
      {:ok, school} =
        Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
          name: "Lycée Vérif"
        })

      TeacherAssistant.TeacherFixtures.complete_school_setup!(school_scope(head, school))
      conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
      %{conn: conn, school: school, head: head}
    end

    test "shows a pending-verification banner while unverified", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school")
      assert has_element?(view, "#pending-verification")
      assert has_element?(view, "#setup-checklist")
    end

    test "hides the banner once verified", %{conn: conn, school: school, head: head} do
      scope = school_scope(head, school)
      :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)
      {:ok, view, _html} = live(conn, ~p"/school")
      refute has_element?(view, "#pending-verification")
    end
  end

  test "a member with a stale session workspace is sent to their first school", %{
    conn: conn,
    workspace: home_school
  } do
    # the session workspace_id points at a school the user does not belong to
    # (a stale/foreign reference), so the resolved scope is non-school even
    # though the user has a real school of their own.
    other_head = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, other_school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: other_head}, %{
        name: "École Étrangère"
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, other_school.id)

    # the page posts to the school switch itself (a LiveView can't write the session)
    {:ok, view, _html} = live(conn, ~p"/school")
    form = form(view, "#open-school-form")
    assert render(form) =~ ~s(action="/workspaces/select/#{home_school.id}")

    conn = follow_trigger_action(form, conn)
    assert get_session(conn, :workspace_id) == home_school.id
    assert redirected_to(conn) == ~p"/school"
  end

  test "a user with no workspace in session and no school is sent to /schools/new" do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user)
    assert {:error, {:live_redirect, %{to: "/schools/new"}}} = live(conn, ~p"/school")
  end

  test "a logged-out visitor on /school is sent to /sign-in" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/school")
  end

  test "the shell shows no personal navigation", %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée Nav"})

    TeacherAssistant.TeacherFixtures.complete_school_setup!(school_scope(user, school))
    conn = post(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-nav")
    refute has_element?(view, "#main-nav")
    refute has_element?(view, "a[href='/teacher/setup']")
    refute has_element?(view, "a[href='/teacher']")
  end

  describe "landing by role space" do
    setup %{actor: head} do
      {:ok, school} =
        Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée L"})

      scope = school_scope(head, school)
      TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
      %{school: school, lscope: scope}
    end

    defp conn_with_roles(school, scope, roles) do
      member = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{roles: roles})

      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(member.current_user)
      |> Plug.Conn.put_session(:workspace_id, school.id)
    end

    test "a surveillant général lands on today's school life", %{school: school, lscope: scope} do
      conn = conn_with_roles(school, scope, [:discipline_master])
      assert {:error, {:live_redirect, %{to: "/school/day"}}} = live(conn, ~p"/school")
    end

    test "a member with no space of their own lands on the classes (École)", %{
      school: school,
      lscope: scope
    } do
      conn = conn_with_roles(school, scope, [:librarian])
      assert {:error, {:live_redirect, %{to: "/school/classes"}}} = live(conn, ~p"/school")
    end

    test "a censeur lands on sequence tracking", %{school: school, lscope: scope} do
      conn = conn_with_roles(school, scope, [:vice_principal])
      assert {:error, {:live_redirect, %{to: "/school/sequences"}}} = live(conn, ~p"/school")
    end

    test "a proviseur stays on the dashboard with the tracking item", %{
      school: school,
      lscope: scope
    } do
      conn = conn_with_roles(school, scope, [:head])
      assert {:ok, view, _html} = live(conn, ~p"/school")
      assert has_element?(view, "#dashboard")
      assert has_element?(view, "#nav-school-sequences")
    end
  end

  describe "Pilotage (complete, verified school)" do
    setup do
      %{head_user: head, workspace: ws, scope: scope} =
        TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

      conn =
        Phoenix.ConnTest.build_conn()
        |> log_in_user(head)
        |> Plug.Conn.put_session(:workspace_id, ws.id)

      %{conn: conn, scope: scope}
    end

    test "KPI cards link to their screens", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school")
      assert has_element?(view, "#dashboard h1", "Tableau de bord")

      for {id, href} <- [
            {"kpi-entry", "/school/sequences"},
            {"kpi-calls", "/school/day"},
            {"kpi-absences", "/school/absences"},
            {"kpi-corrections", "/school/corrections/review"}
          ],
          do: assert(has_element?(view, "##{id}[href='#{href}']"))
    end

    test "to-do rows appear only when their condition holds", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school")
      # no pending correction, nothing on paper, not an APC school
      refute has_element?(view, "#todo-corrections")
      refute has_element?(view, "#todo-paper")
      refute has_element?(view, "#todo-competences")
    end

    test "setup gaps are one « Mise en place » block of cards, one action each", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school")
      # the fixture's classes have no form master and subjects without a teacher
      assert has_element?(view, "#setup-steps h2", "Mise en place de l'année")
      assert has_element?(view, "#setup-step-pp[href='/school/classes']", "Désigner les PP")
      assert has_element?(view, "#setup-step-pp", "Classes sans professeur principal")

      assert has_element?(
               view,
               "#setup-step-unassigned[href='/school/settings/assignments']",
               "Affecter"
             )

      # no account awaiting its first sign-in: no card
      refute has_element?(view, "#setup-step-accounts")
      refute has_element?(view, "#todo-no-pp")
      refute has_element?(view, "#todo-unassigned")
    end

    test "courses without a competence are a to-do row in an APC school", ctx do
      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(ctx.scope, %{
          "language" => "by_class",
          "elements" => ["apc", "rank"]
        })

      %{class_group: cg} = TeacherAssistant.TeacherFixtures.school_teacher_fixture(ctx.scope)

      {:ok, _} =
        TeacherAssistant.Enrollment.add_student(ctx.scope, cg, %{full_name: "Awa", sex: :f})

      {:ok, view, _} = live(ctx.conn, ~p"/school")

      assert has_element?(
               view,
               "#todo-competences a[href='/school/sequences']",
               "sans compétence"
             )
    end

    test "the setup checklist is hidden once setup is complete", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school")
      refute has_element?(view, "#setup-checklist")
      refute has_element?(view, "#pending-verification")
    end

    test "entry bars per level", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school")
      assert has_element?(view, "#entry-bars h2", "par niveau")
      refute has_element?(view, "#entry-bars [data-class]")
      assert has_element?(view, "#entry-bars [data-level]")
      assert has_element?(view, "#entry-bars a[href='/school/sequences']")
    end

    test "the three count stats are gone", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school")
      refute has_element?(view, "#dashboard-stats")
    end
  end

  describe "query budget (A3)" do
    alias TeacherAssistant.{Assessment, Attendance, Curriculum, Enrollment, Timetabling}

    # Measured 2026-11-11 on this fixture: 146 (dead render + connected mount; A8 halves it).
    @budget 155

    setup %{conn: conn, actor: head} do
      {:ok, school} =
        Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
          name: "Lycée Budget"
        })

      scope = school_scope(head, school)
      :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

      {:ok, year} =
        Organization.create_academic_year(scope, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      :ok = Organization.build_default_calendar(scope, year)
      :ok = Attendance.build_default_periods(scope)
      seq = scope |> Organization.list_sequences(year) |> hd()
      period = scope |> Attendance.list_periods() |> Enum.find(&(&1.kind == :lesson))

      for n <- 1..3 do
        {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e #{n}", level: "6ème"})
        {:ok, cg} = Enrollment.set_paper_roll_call(scope, cg, false)
        {:ok, s1} = Enrollment.add_student(scope, cg, %{full_name: "A#{n}", sex: :f})
        {:ok, _s2} = Enrollment.add_student(scope, cg, %{full_name: "B#{n}", sex: :m})
        {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
        {:ok, a} = Assessment.create_assessment(scope, tc, seq, %{label: "Devoir 1"})
        :ok = Assessment.upsert_marks(scope, a, [%{student_id: s1.id, score: Decimal.new(12)}])

        {:ok, _} =
          Timetabling.place_slot(scope, cg, %{
            day: :monday,
            period_id: period.id,
            teaching_context_id: tc.id
          })

        [%{enrollment: e} | _] = Enrollment.list_roster(scope, cg)

        {:ok, _} =
          Attendance.record_period(scope, cg, period, tc, ~D[2025-09-15], [{e.id, :absent}])
      end

      %{conn: Plug.Conn.put_session(conn, :workspace_id, school.id)}
    end

    # Queries run by this test or the LiveView it mounts (the view's `$callers` names us).
    defp count_queries(fun) do
      parent = self()
      counter = :counters.new(3, [])
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:teacher_assistant, :repo, :query],
        fn _e, _m, %{query: q}, _ ->
          if self() == parent or parent in List.wrap(Process.get(:"$callers")) do
            :counters.add(counter, 1, 1)
            if q =~ ~s(FROM "marks"), do: :counters.add(counter, 2, 1)

            if q =~ ~s(FROM "students") or q =~ ~s(FROM "guardians"),
              do: :counters.add(counter, 3, 1)
          end
        end,
        nil
      )

      result = fun.()
      :telemetry.detach(handler)
      {result, :counters.get(counter, 1), :counters.get(counter, 2), :counters.get(counter, 3)}
    end

    test "the head's dashboard mounts within budget and reads no mark, student or guardian rows",
         %{conn: conn} do
      {{:ok, _view, html}, total, marks, people} =
        count_queries(fn -> live(conn, ~p"/school") end)

      assert html =~ "Absences"
      assert marks == 0, "#{marks} mark-row queries"
      assert people == 0, "#{people} student/guardian queries"
      assert total <= @budget, "#{total} queries (budget #{@budget})"
    end
  end
end
