defmodule TeacherAssistantWeb.School.FeeSettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, Fees, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    {:ok, q} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, r} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})
    %{scope: scope, year: year, q: q, r: r}
  end

  defp types(ctx),
    do: ctx.scope |> Fees.list_fee_types(ctx.year) |> Enum.map(&{&1.name, &1.active?})

  test "a teacher is redirected", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/settings/fees")
  end

  test "create the default types, add a type, move it up, deactivate an unused one",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/fees")
    view |> element("#create-default-types") |> render_click()
    assert types(ctx) == [{"Frais exigibles", true}, {"PTA", true}]

    view |> form("#new-fee-type-form", fee_type: %{name: "Frais informatique"}) |> render_submit()

    info =
      ctx.scope |> Fees.list_fee_types(ctx.year) |> Enum.find(&(&1.name == "Frais informatique"))

    view |> element("#move-up-#{info.id}") |> render_click()
    assert Enum.map(types(ctx), &elem(&1, 0)) == ["Frais exigibles", "Frais informatique", "PTA"]

    view |> element("#deactivate-type-#{info.id}") |> render_click()
    assert {"Frais informatique", false} in types(ctx)
  end

  test "a type in use cannot be deactivated", %{conn: conn} = ctx do
    {:ok, _} = Fees.create_default_fee_types(ctx.scope, ctx.year)
    [fe, _] = Fees.list_fee_types(ctx.scope, ctx.year)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, fe, 50_000)
    {:ok, view, _} = live(conn, ~p"/school/settings/fees")
    view |> element("#deactivate-type-#{fe.id}") |> render_click()
    assert render(view) =~ "utilisé"
    assert {"Frais exigibles", true} in types(ctx)
  end

  test "set an amount in the grid and apply it to the whole level", %{conn: conn} = ctx do
    {:ok, _} = Fees.create_default_fee_types(ctx.scope, ctx.year)
    [fe, _] = Fees.list_fee_types(ctx.scope, ctx.year)
    {:ok, view, _} = live(conn, ~p"/school/settings/fees")

    view |> form("#fee-#{ctx.q.id}-#{fe.id}", %{amount: "45000"}) |> render_change()
    assert Fees.class_fee_grid(ctx.scope, ctx.year)[{ctx.q.id, fe.id}] == 45_000

    view |> element("#level-#{ctx.q.id}-#{fe.id}") |> render_click()
    assert Fees.class_fee_grid(ctx.scope, ctx.year)[{ctx.r.id, fe.id}] == 45_000
  end

  test "add a tranche; the last-percent warning shows until a 100 % tranche exists",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/fees")

    view
    |> form("#tranche-form",
      tranche: %{label: "1re tranche", due_date: "2025-10-15", percent: "50"}
    )
    |> render_submit()

    assert [%{percent: 50}] = Fees.list_tranches(ctx.scope, ctx.year)
    assert has_element?(view, "#percent-warning")
    refute has_element?(view, "#tranche-form input[name='tranche[label]'][value='1re tranche']")

    view
    |> form("#tranche-form",
      tranche: %{label: "2e tranche", due_date: "2026-01-15", percent: "100"}
    )
    |> render_submit()

    refute has_element?(view, "#percent-warning")
  end

  test "copy the previous year and see the classes to complete", %{conn: conn} = ctx do
    {:ok, _} = Fees.create_default_fee_types(ctx.scope, ctx.year)
    [fe, _] = Fees.list_fee_types(ctx.scope, ctx.year)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, fe, 50_000)
    %{next: next} = TeacherFixtures.close_year!(ctx.scope, ctx.year)
    scope = %{ctx.scope | current_academic_year: next}

    {:ok, _} =
      Enrollment.create_class_group(scope, next, %{label: "1ère TI", level: "1ère", serie: "TI"})

    {:ok, view, _} = live(conn, ~p"/school/settings/fees")
    view |> element("#copy-previous") |> render_click()
    assert has_element?(view, "#copy-unmatched", "1ère TI")
    assert Enum.map(Fees.list_fee_types(scope, next), & &1.name) == ["Frais exigibles", "PTA"]
  end

  test "carry arrears for the ticked students only", %{conn: conn} = ctx do
    {:ok, _} = Fees.create_default_fee_types(ctx.scope, ctx.year)
    [fe, _] = Fees.list_fee_types(ctx.scope, ctx.year)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, fe, 50_000)
    {:ok, %{student: a}} = Enrollment.enroll_new(ctx.scope, ctx.q, %{full_name: "Awa A", sex: :f})
    {:ok, %{student: b}} = Enrollment.enroll_new(ctx.scope, ctx.q, %{full_name: "Bel B", sex: :m})
    {:ok, _} = Enrollment.enroll_new(ctx.scope, ctx.q, %{full_name: "Cam C", sex: :m})
    %{next: next} = TeacherFixtures.close_year!(ctx.scope, ctx.year)
    scope = %{ctx.scope | current_academic_year: next}
    [z] = scope |> Enrollment.list_class_groups(next) |> Enum.filter(&(&1.label == "6ème Z"))
    {:ok, ea} = Enrollment.enroll_existing(scope, z, a)
    {:ok, _eb} = Enrollment.enroll_existing(scope, z, b)

    {:ok, view, _} = live(conn, ~p"/school/settings/fees")
    assert has_element?(view, "#arrears", "non réinscrit")

    view |> form("#arrears-form", %{enrollment_ids: [ea.id]}) |> render_submit()

    assert Fees.arrears_candidates(scope, next) |> Enum.map(& &1.student.full_name) == [
             "Bel B",
             "Cam C"
           ]
  end

  test "the settings hub links to the page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#fee-settings-link")
  end
end
