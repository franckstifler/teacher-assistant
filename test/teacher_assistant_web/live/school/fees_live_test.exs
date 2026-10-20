defmodule TeacherAssistantWeb.School.FeesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.{Enrollment, Fees, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    ctx = fees_setup(%{scope | current_academic_year: year}, year)

    {:ok, _} =
      Enrollment.add_guardian(ctx.scope, ctx.student, %{
        full_name: "Mère A",
        relationship: :mere,
        phone: "677123456"
      })

    {:ok, %{enrollment: e2}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Bel B", sex: :m})

    Map.put(ctx, :e2, e2)
  end

  defp conn_for(scope, user),
    do:
      build_conn()
      |> log_in_user(user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

  defp page(ctx, query \\ ""), do: "/school/classes/#{ctx.cg.id}/fees" <> query

  test "the roster shows due, paid, left and status per student", %{conn: conn} = ctx do
    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    {:ok, view, _} = live(conn, page(ctx))
    assert has_element?(view, "#fee-row-#{ctx.e.id}", "60 000")
    assert has_element?(view, "#fee-row-#{ctx.e.id}", "20 000")
    assert has_element?(view, "#fee-row-#{ctx.e.id}", "40 000")
    assert has_element?(view, "#fees-summary", "Frais exigibles")
  end

  test "Encaisser records a payment and shows the receipt number with print and WhatsApp links",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))

    view
    |> form("#payment-form", payment: %{amount: "15000", paid_on: "2025-10-02", method: "cash"})
    |> render_submit()

    [p] = Fees.list_payments(ctx.scope, ctx.e)
    assert has_element?(view, "#last-receipt", p.number)
    assert has_element?(view, "#print-receipt[href='/school/fees/receipts/#{p.id}/print']")
    assert has_element?(view, "#last-receipt a[href^='https://wa.me/237677123456?text=']")
    refute has_element?(view, "#payment-form input[name='payment[amount]'][value='15000']")
  end

  test "mobile money without a reference shows an error and writes nothing",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))

    view
    |> form("#payment-form",
      payment: %{amount: "15000", paid_on: "2025-10-02", method: "mobile_money"}
    )
    |> render_submit()

    assert has_element?(view, "#payment-error")
    assert Fees.list_payments(ctx.scope, ctx.e) == []
  end

  test "Annuler with a reason cancels; without a reason it is refused", %{conn: conn} = ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))

    view |> form("#cancel-form-#{p.id}", %{reason: " "}) |> render_submit()
    assert {:ok, %{status: :valid}} = Fees.get_payment(ctx.scope, p.id)

    view |> form("#cancel-form-#{p.id}", %{reason: "Erreur de montant"}) |> render_submit()
    assert {:ok, %{status: :cancelled}} = Fees.get_payment(ctx.scope, p.id)
    assert has_element?(view, "#payment-#{p.id}", "Annulé")
  end

  test "an adjustment on PTA lowers the student's due", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))

    view
    |> form("#adjustment-form",
      adjustment: %{fee_type_id: ctx.pta.id, amount: "10000", reason: "Enfant du personnel"}
    )
    |> render_submit()

    assert Fees.student_fees(ctx.scope, ctx.e).total_due == 50_000
    assert has_element?(view, "#fee-row-#{ctx.e.id}", "50 000")
  end

  test "the late filter shows only students behind", %{conn: conn} = ctx do
    # The test clock is frozen before the fixture's first tranche: add one already due.
    {:ok, _} =
      Fees.add_tranche(ctx.scope, ctx.year, %{
        label: "Inscription",
        due_date: ~D[2025-09-10],
        percent: 10
      })

    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, cash(60_000))
    {:ok, view, _} = live(conn, page(ctx, "?late=1"))
    refute has_element?(view, "#fee-row-#{ctx.e.id}")
    assert has_element?(view, "#fee-row-#{ctx.e2.id}")
  end

  test "a form master sees the page read-only", ctx do
    fm = TeacherFixtures.member_scope_fixture(ctx.scope)
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)
    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))

    {:ok, view, _} = live(conn_for(ctx.scope, fm.current_user), page(ctx, "?student=#{ctx.e.id}"))
    assert has_element?(view, "#fee-row-#{ctx.e.id}", "20 000")
    refute has_element?(view, "#payment-form")
    refute has_element?(view, "[id^='cancel-form-']")
    refute has_element?(view, "#adjustment-form")
  end

  test "a teacher is redirected; crafted events from a form master write nothing", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(ctx.scope, teacher.current_user), page(ctx))

    fm = TeacherFixtures.member_scope_fixture(ctx.scope)
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    {:ok, view, _} = live(conn_for(ctx.scope, fm.current_user), page(ctx, "?student=#{ctx.e.id}"))

    render_submit(view, "record_payment", %{
      "payment" => %{"amount" => "1000", "method" => "cash"}
    })

    render_submit(view, "cancel_payment", %{"payment_id" => p.id, "reason" => "x"})
    assert [%{status: :valid}] = Fees.list_payments(ctx.scope, ctx.e)
  end
end
