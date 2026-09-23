defmodule TeacherAssistantWeb.Onboarding.SetupWizardLiveTest do
  use TeacherAssistantWeb.ConnCase
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Enrollment

  setup %{conn: conn} do
    %{workspace: ws, head_user: head} = school_fixture()
    conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
    %{conn: conn, ws: ws, head: head}
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
      |> form("#invite-form", %{"invite" => %{"email" => "prof@example.com", "roles" => ["teacher"]}})
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

  test "creating the academic year seeds classes and advances to the classes step", %{
    conn: conn,
    ws: ws
  } do
    {:ok, view, _} = live(conn, ~p"/school/setup")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2026-2027", "start_date" => "2026-09-01", "end_date" => "2027-07-05"}
    })
    |> render_submit()

    assert TeacherAssistant.Organization.current_academic_year(ws) != nil
    assert Enrollment.list_class_groups(ws, TeacherAssistant.Organization.current_academic_year(ws)) != []

    html = render(view)
    assert html =~ "wizard-panel-classes"
  end

  describe "classes step" do
    setup %{conn: conn, ws: ws} do
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

      year = TeacherAssistant.Organization.current_academic_year(ws)
      %{view: view, year: year}
    end

    test "continue is disabled with zero classes and enabled after adding one", %{
      conn: conn,
      ws: ws,
      year: year
    } do
      # Seeding always leaves at least one starter class — delete them all to
      # exercise the empty branch.
      ws |> Enrollment.list_class_groups(year) |> Enum.each(&Enrollment.delete_class_group/1)

      {:ok, view, html} = live(conn, ~p"/school/setup")
      assert html =~ ~s(id="wizard-panel-classes")

      continue_button = element(view, ~s(button[phx-click="continue_classes"]))
      assert render(continue_button) =~ "disabled"

      view
      |> form("#class-form", %{
        "class_group" => %{"label" => "6e A", "level" => "6e"}
      })
      |> render_submit()

      assert Enrollment.list_class_groups(ws, year) != []

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
      ws: ws,
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
      [class_group | rest] = Enrollment.list_class_groups(ws, year)
      Enum.each(rest, &Enrollment.delete_class_group/1)

      view
      |> element(~s(button[phx-click="delete_class"][phx-value-id="#{class_group.id}"]))
      |> render_click()

      assert Enrollment.list_class_groups(ws, year) == []

      continue_button = element(view, ~s(button[phx-click="continue_classes"]))
      assert render(continue_button) =~ "disabled"
    end

    test "deleting a class with roster data shows a flash and does not crash", %{
      ws: ws,
      view: view,
      year: year
    } do
      [class_group | _] = Enrollment.list_class_groups(ws, year)

      {:ok, _student} = Enrollment.add_student(class_group, %{full_name: "Awa", sex: :f})

      view
      |> element(~s(button[phx-click="delete_class"][phx-value-id="#{class_group.id}"]))
      |> render_click()

      assert Enum.any?(Enrollment.list_class_groups(ws, year), &(&1.id == class_group.id))

      html = render(view)
      # `d'abord` renders HTML-escaped (`d&#39;abord`), so match a
      # substring on either side of the apostrophe.
      assert html =~ "des élèves ou des enseignants"
    end
  end
end
