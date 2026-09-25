defmodule TeacherAssistantWeb.Onboarding.SetupWizardLiveTest do
  use TeacherAssistantWeb.ConnCase
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Enrollment

  setup %{conn: conn} do
    %{workspace: ws, head_user: head, scope: scope} = school_fixture()
    conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
    %{conn: conn, ws: ws, head: head, scope: scope}
  end

  describe "invite step" do
    setup %{conn: conn} do
      %{workspace: ws, head_user: head} = setup_complete_school_fixture()
      conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
      %{conn: conn, ws: ws, head: head}
    end

    test "inviting a teammate sends an email and lists them as pending", %{conn: conn} do
      import Swoosh.TestAssertions

      {:ok, view, _} = live(conn, ~p"/school/setup")

      view
      |> form("#invite-form", %{
        "invite" => %{"email" => "prof@example.com", "roles" => ["teacher"]}
      })
      |> render_submit()

      assert_email_sent(fn e -> assert {_, "prof@example.com"} = hd(e.to) end)
      assert render(view) =~ "prof@example.com"
    end

    test "finish redirects to the dashboard", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/school/setup")

      assert {:error, {:live_redirect, %{to: "/school"}}} =
               render_click(element(view, "#finish-setup"))
    end
  end

  test "renders the wizard on the academic-year step for a fresh school", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/school/setup")
    assert html =~ "setup-wizard"
    # year step is first for a fresh school
    assert html =~ "Académique" or html =~ "Année"
  end

  describe "recap aside" do
    test "fresh school: Identité done, Année/Classes/Équipe/Vérification todo", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/school/setup")

      assert html =~ ~s(id="recap-identity" data-state="done")
      assert html =~ ~s(id="recap-year" data-state="todo")
      assert html =~ ~s(id="recap-classes" data-state="todo")
      assert html =~ ~s(id="recap-team" data-state="todo")
      assert html =~ ~s(id="recap-verification" data-state="todo")
    end

    test "setup-complete school: Année and Classes are done", %{conn: conn} do
      %{workspace: ws, head_user: head} = setup_complete_school_fixture()
      conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)

      {:ok, _view, html} = live(conn, ~p"/school/setup")

      assert html =~ ~s(id="recap-year" data-state="done")
      assert html =~ ~s(id="recap-classes" data-state="done")
    end
  end

  test "creating the academic year seeds classes and advances to the classes step", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/school/setup")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2026-2027", "start_date" => "2026-09-01", "end_date" => "2027-07-05"}
    })
    |> render_submit()

    assert TeacherAssistant.Organization.current_academic_year(scope) != nil

    assert Enrollment.list_class_groups(
             scope,
             TeacherAssistant.Organization.current_academic_year(scope)
           ) != []

    html = render(view)
    assert html =~ "wizard-panel-classes"
  end

  test "creating the academic year builds its calendar and the default periods", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/school/setup")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2026-2027", "start_date" => "2026-09-01", "end_date" => "2027-07-05"}
    })
    |> render_submit()

    year = TeacherAssistant.Organization.current_academic_year(scope)
    seqs = TeacherAssistant.Organization.list_sequences(scope, year)
    assert length(seqs) == 6
    assert List.first(seqs).start_date == ~D[2026-09-01]
    assert List.last(seqs).end_date == ~D[2027-07-05]
    assert TeacherAssistant.Attendance.list_periods(scope) != []
  end

  test "a year whose end precedes its start is refused and the wizard stays on the year step", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/school/setup")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "Bad", "start_date" => "2026-09-01", "end_date" => "2025-07-05"}
    })
    |> render_submit()

    assert TeacherAssistant.Organization.current_academic_year(scope) == nil
    assert has_element?(view, "#year-form")
  end

  describe "classes step" do
    setup %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/school/setup")

      view
      |> form("#year-form", %{
        "year" => %{
          "name" => "2026-2027",
          "start_date" => "2026-09-01",
          "end_date" => "2027-07-05"
        }
      })
      |> render_submit()

      year = TeacherAssistant.Organization.current_academic_year(scope)
      %{view: view, year: year}
    end

    test "continue is disabled with zero classes and enabled after adding one", %{
      conn: conn,
      scope: scope,
      year: year
    } do
      # Seeding always leaves at least one starter class — delete them all to
      # exercise the empty branch.
      scope
      |> Enrollment.list_class_groups(year)
      |> Enum.each(&Enrollment.delete_class_group(scope, &1))

      {:ok, view, html} = live(conn, ~p"/school/setup")
      assert html =~ ~s(id="wizard-panel-classes")

      continue_button = element(view, ~s(button[phx-click="continue_classes"]))
      assert render(continue_button) =~ "disabled"

      view
      |> form("#class-form", %{
        "class_group" => %{"label" => "6e A", "level" => "6e"}
      })
      |> render_submit()

      assert Enrollment.list_class_groups(scope, year) != []

      html = render(view)
      refute html =~ ~s(button[phx-click="continue_classes"] disabled)
      continue_button = element(view, ~s(button[phx-click="continue_classes"]))
      refute render(continue_button) =~ "disabled"
    end

    test "continue advances to the invite step once a class exists", %{view: view} do
      html = render(view)
      assert html =~ ~s(id="wizard-panel-classes")

      view
      |> element(~s(button[phx-click="continue_classes"]))
      |> render_click()

      html = render(view)
      assert html =~ ~s(id="wizard-panel-invite")
    end

    test "deleting the last class blocks continue again", %{
      scope: scope,
      view: view,
      year: year
    } do
      # `view` is already mounted on the `:classes` step (landed there by the
      # `create_year` handler). Prune all-but-one class directly through the
      # domain — this doesn't touch the live view's assigns, so the page
      # still renders every class group, including the one we keep — then
      # delete that last one through the UI so the view's own handler (not a
      # fresh mount, which would re-derive the step past `:classes` once a
      # class exists) drives it to zero.
      [class_group | rest] = Enrollment.list_class_groups(scope, year)
      Enum.each(rest, &Enrollment.delete_class_group(scope, &1))

      view
      |> element(~s(button[phx-click="delete_class"][phx-value-id="#{class_group.id}"]))
      |> render_click()

      assert Enrollment.list_class_groups(scope, year) == []

      continue_button = element(view, ~s(button[phx-click="continue_classes"]))
      assert render(continue_button) =~ "disabled"
    end

    test "deleting a class with roster data shows a flash and does not crash", %{
      scope: scope,
      view: view,
      year: year
    } do
      [class_group | _] = Enrollment.list_class_groups(scope, year)

      {:ok, _student} = Enrollment.add_student(scope, class_group, %{full_name: "Awa", sex: :f})

      view
      |> element(~s(button[phx-click="delete_class"][phx-value-id="#{class_group.id}"]))
      |> render_click()

      assert Enum.any?(Enrollment.list_class_groups(scope, year), &(&1.id == class_group.id))

      html = render(view)
      # `d'abord` renders HTML-escaped (`d&#39;abord`), so match a
      # substring on either side of the apostrophe.
      assert html =~ "des élèves ou des enseignants"
    end
  end

  describe "classes step authorization (non-head member)" do
    setup do
      %{workspace: ws, head_user: head, year: year, scope: scope} =
        setup_complete_school_fixture()

      other = user_fixture(%{})

      TeacherAssistant.TeacherFixtures.membership_fixture(scope, %{user: other, roles: [:teacher]})

      conn =
        Phoenix.ConnTest.build_conn()
        |> log_in_user(other)
        |> put_session(:workspace_id, ws.id)

      %{conn: conn, ws: ws, head: head, other: other, year: year, scope: scope}
    end

    test "a non-head member cannot add a class via a forged event", %{
      conn: conn,
      scope: scope,
      year: year
    } do
      {:ok, view, _html} = live(conn, ~p"/school/setup")

      before_labels = scope |> Enrollment.list_class_groups(year) |> Enum.map(& &1.label)

      render_hook(view, "add_class", %{
        "class_group" => %{"label" => "Forged", "level" => "6e"}
      })

      after_labels = scope |> Enrollment.list_class_groups(year) |> Enum.map(& &1.label)
      assert after_labels == before_labels
      refute "Forged" in after_labels
    end

    test "a non-head member cannot delete a class via a forged event", %{
      conn: conn,
      scope: scope,
      year: year
    } do
      {:ok, view, _html} = live(conn, ~p"/school/setup")

      [class_group | _] = Enrollment.list_class_groups(scope, year)

      render_hook(view, "delete_class", %{"id" => class_group.id})

      assert Enum.any?(Enrollment.list_class_groups(scope, year), &(&1.id == class_group.id))
    end
  end
end
