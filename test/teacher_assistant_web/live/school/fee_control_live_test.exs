defmodule TeacherAssistantWeb.School.FeeControlLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.{Enrollment, FeeControl, Fees, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  # Awa owes 24 000 today; Ben has a note; Chloé paid.
  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    ctx = fees_setup(%{scope | current_academic_year: year}, year)

    {:ok, _} =
      Fees.add_tranche(ctx.scope, year, %{
        label: "Inscription",
        due_date: ~D[2025-09-01],
        percent: 40
      })

    {:ok, %{enrollment: ben}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Ben B", sex: :m})

    {:ok, _} =
      FeeControl.issue_note(ctx.scope, ben, %{reason: :promise, valid_until: ~D[2025-09-30]})

    {:ok, %{enrollment: chloe}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Chloé C", sex: :f})

    {:ok, _} = Fees.record_payment(ctx.scope, chloe, cash(24_000))
    Map.merge(ctx, %{ben: ben, chloe: chloe})
  end

  defp path(ctx), do: ~p"/school/classes/#{ctx.cg.id}/fees/control"

  test "control list groups students and ticking records a send-out", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    assert has_element?(view, "#control-title", "Contrôle des frais — 6e Q")
    assert has_element?(view, "#must-leave", "Doivent sortir — 1")
    assert has_element?(view, "#must-leave", "Awa A")
    assert has_element?(view, "#must-leave", "24 000")
    assert has_element?(view, "#allowed", "Autorisés malgré un retard — 1")
    assert has_element?(view, "#allowed", "Ben B")
    assert has_element?(view, "#allowed", "promesse jusqu'au 30/09/2025")
    assert has_element?(view, "#up-to-date", "L'autre élève est à jour.")

    view |> element("#sorti-#{ctx.e.id}") |> render_click()

    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id], ~D[2025-09-15]) ==
             MapSet.new([ctx.e.id])

    view |> element("#sorti-#{ctx.e.id}") |> render_click()
    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id], ~D[2025-09-15]) == MapSet.new()
  end

  test "the print page lists the same groups", %{conn: conn} = ctx do
    html = conn |> get(~p"/school/classes/#{ctx.cg.id}/fees/control/print") |> html_response(200)
    assert html =~ "Contrôle des frais — 6e Q"
    assert html =~ "Doivent sortir — 1" and html =~ "Awa A"
    assert html =~ "Autorisés malgré un retard — 1" and html =~ "Ben B"
  end

  test "Tout cocher records all must-leave students", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))
    view |> element("#tick-all") |> render_click()

    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id, ctx.ben.id], ~D[2025-09-15]) ==
             MapSet.new([ctx.e.id])
  end

  test "the class's form master sees notes, read-only", ctx do
    fm = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)

    conn =
      build_conn()
      |> log_in_user(fm.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.scope.current_workspace.id)

    {:ok, view, _} = live(conn, path(ctx))
    assert has_element?(view, "#allowed", "Ben B")
    refute has_element?(view, "#must-leave", "Ben B")
    refute has_element?(view, "#sorti-#{ctx.e.id}")

    {:ok, fees, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/fees?student=#{ctx.ben.id}")
    assert has_element?(fees, "#return-notes [id^='note-']")
    refute has_element?(fees, "#note-form")
  end

  test "a teacher is redirected", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})

    conn =
      build_conn()
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.scope.current_workspace.id)

    assert {:error, {_, %{to: to}}} = live(conn, path(ctx))
    assert to =~ "/school"
  end

  test "without the frais module the page is gone", %{conn: conn} = ctx do
    operator = TeacherFixtures.admin_user_fixture()

    {:ok, _} =
      Organization.set_modules(
        %TeacherAssistant.Scope{current_user: operator},
        ctx.scope.current_workspace,
        [:notes]
      )

    assert {:error, {_, %{to: to}}} = live(conn, path(ctx))
    assert to =~ "/school"
  end
end
