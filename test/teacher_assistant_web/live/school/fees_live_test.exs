defmodule TeacherAssistantWeb.School.FeesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Fees
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée F"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{conn: conn, school: school, year: year, cg: cg, head: head}
  end

  defp conn_for(school, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "a fees manager adds a tranche, sees it, and deletes it", %{
    school: school,
    cg: cg,
    head: head
  } do
    bursar = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(bursar.email), roles: [:bursar]})

    {:ok, _} = Schools.accept_invitation(inv.token, bursar)

    conn = conn_for(school, bursar)

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/fees")

    assert has_element?(view, "#fees-add-form")

    view
    |> form("#fees-add-form", %{
      "label" => "1ère tranche",
      "amount" => "25000",
      "due_date" => "2025-10-01"
    })
    |> render_submit()

    assert [tranche] = Fees.list_tranches(cg)
    assert tranche.label == "1ère tranche"
    assert tranche.amount == 25_000

    view
    |> element("#delete-tranche-#{tranche.id}")
    |> render_click()

    assert Fees.list_tranches(cg) == []
  end

  test "a negative or non-numeric amount is rejected without persisting", %{cg: cg, school: school, head: head} do
    conn = conn_for(school, head)
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/fees")

    view
    |> form("#fees-add-form", %{
      "label" => "Bad",
      "amount" => "-500",
      "due_date" => "2025-10-01"
    })
    |> render_submit()

    assert Fees.list_tranches(cg) == []

    view
    |> form("#fees-add-form", %{
      "label" => "Bad",
      "amount" => "not-a-number",
      "due_date" => "2025-10-01"
    })
    |> render_submit()

    assert Fees.list_tranches(cg) == []
  end

  test "a fees manager edits a tranche's label and amount", %{
    school: school,
    cg: cg,
    head: head
  } do
    {:ok, tranche} =
      Fees.add_tranche(cg, %{label: "Tranche 1", amount: 10_000, due_date: ~D[2025-10-01]})

    conn = conn_for(school, head)
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/fees")

    assert has_element?(view, "#edit-tranche-#{tranche.id}")

    view
    |> element("#edit-tranche-#{tranche.id}")
    |> render_click()

    assert has_element?(view, "#tranche-edit-form-#{tranche.id}")

    view
    |> form("#tranche-edit-form-#{tranche.id}", %{
      "tranche_id" => tranche.id,
      "label" => "Tranche 1 modifiée",
      "amount" => "15000",
      "due_date" => "2025-11-01"
    })
    |> render_submit()

    assert [updated] = Fees.list_tranches(cg)
    assert updated.label == "Tranche 1 modifiée"
    assert updated.amount == 15_000
    assert updated.due_date == ~D[2025-11-01]
  end

  test "an invalid amount on edit is rejected without persisting", %{
    school: school,
    cg: cg,
    head: head
  } do
    {:ok, tranche} =
      Fees.add_tranche(cg, %{label: "Tranche 1", amount: 10_000, due_date: ~D[2025-10-01]})

    conn = conn_for(school, head)
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/fees")

    view
    |> element("#edit-tranche-#{tranche.id}")
    |> render_click()

    view
    |> form("#tranche-edit-form-#{tranche.id}", %{
      "tranche_id" => tranche.id,
      "label" => "Tranche 1",
      "amount" => "-500",
      "due_date" => "2025-10-01"
    })
    |> render_submit()

    assert [unchanged] = Fees.list_tranches(cg)
    assert unchanged.amount == 10_000
  end

  test "a form master sees read-only rows and forged events are rejected", %{
    school: school,
    cg: cg,
    head: head
  } do
    {:ok, _tranche} =
      Fees.add_tranche(cg, %{label: "Tranche 1", amount: 10_000, due_date: ~D[2025-10-01]})

    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, fm)
    {:ok, _} = Academics.set_form_master(cg, fm.id)

    conn = conn_for(school, fm)

    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}/fees")

    assert html =~ "Tranche 1"
    refute has_element?(view, "#fees-add-form")

    [tranche] = Fees.list_tranches(cg)
    refute has_element?(view, "#delete-tranche-#{tranche.id}")
    refute has_element?(view, "#edit-tranche-#{tranche.id}")

    view
    |> render_hook("add_tranche", %{
      "label" => "forged",
      "amount" => "5000",
      "due_date" => "2025-10-01"
    })

    view
    |> render_hook("delete_tranche", %{"tranche_id" => tranche.id})

    view
    |> render_hook("update_tranche", %{
      "tranche_id" => tranche.id,
      "label" => "forged edit",
      "amount" => "1",
      "due_date" => "2025-10-01"
    })

    assert Fees.list_tranches(cg) == [tranche]
  end

  test "a plain teacher who is not the form master is redirected to /school", %{
    school: school,
    cg: cg,
    head: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn = conn_for(school, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/fees")
  end

  test "cross-school class id redirects to /school/classes", %{conn: conn} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, os} = Schools.create_school(other, %{name: "Autre"})

    {:ok, oy} =
      Academics.create_academic_year(os, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Academics.create_class_group(os, oy, %{label: "6e Z", level: "6ème"})

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/fees")
  end
end
