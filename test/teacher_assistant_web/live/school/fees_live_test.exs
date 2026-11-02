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

  describe "Fees 2: notes and warnings" do
    # Awa and Bel each owe 40 % today.
    setup ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.scope, ctx.year, %{label: "I", due_date: ~D[2025-09-01], percent: 40})

      :ok
    end

    test "issue a promise note from the drawer and print it", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))

      view
      |> form("#note-form", note: %{reason: "promise", valid_until: "2025-09-30"})
      |> render_submit()

      [note] = TeacherAssistant.FeeControl.list_notes(ctx.scope, ctx.e)
      assert note.reason == :promise and note.valid_until == ~D[2025-09-30]
      assert has_element?(view, "#last-note a[href='/school/fees/notes/#{note.id}/print']")
      assert has_element?(view, "#note-#{note.id}", note.number)
    end

    test "an expired note is marked Expirée on the card", %{conn: conn} = ctx do
      note =
        TeacherAssistant.Academics.ReturnNote
        |> paper_changeset(
          :create,
          %{
            enrollment_id: ctx.e.id,
            academic_year_id: ctx.year.id,
            seq: 1,
            number: "A2025-000001",
            reason: :promise,
            issued_on: ~D[2025-09-01],
            valid_until: ~D[2025-09-10],
            student_name: "Awa A",
            class_label: "6e Q"
          },
          scope: ctx.scope
        )
        |> Ash.create!()

      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))
      assert has_element?(view, "#note-#{note.id} .badge", "Expirée")
    end

    test "the special permission reason is not called an exemption", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))
      assert has_element?(view, "#note-form option[value='exemption']", "Autorisation spéciale")
    end

    test "the warn form says who already got a warning and cancelling asks first",
         %{conn: conn} = ctx do
      {:ok, [w]} =
        TeacherAssistant.FeeControl.issue_warnings(ctx.scope, [ctx.e], ~D[2025-09-22])

      {:ok, view, _} = live(conn, page(ctx))
      view |> element("#warn-class") |> render_click()
      assert has_element?(view, "#warn-form", "avis du 15/09/2025")
      assert has_element?(view, "#warn-form button[type='submit']", "Émettre les avis")

      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))
      assert has_element?(view, "#cancel-warning-#{w.id} button[data-confirm]")
    end

    test "a promise without a date shows an error", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))
      view |> form("#note-form", note: %{reason: "promise", valid_until: ""}) |> render_submit()
      assert has_element?(view, "#note-error")
      assert TeacherAssistant.FeeControl.list_notes(ctx.scope, ctx.e) == []
    end

    test "after a payment, offer a payment note when still behind", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))

      view
      |> form("#payment-form", payment: %{amount: "5000", paid_on: "2025-09-15", method: "cash"})
      |> render_submit()

      view |> element("#note-after-payment") |> render_click()
      assert [%{reason: :payment}] = TeacherAssistant.FeeControl.list_notes(ctx.scope, ctx.e)
    end

    test "cancel a note with a reason", %{conn: conn} = ctx do
      {:ok, note} =
        TeacherAssistant.FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :exemption})

      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))

      view
      |> form("#cancel-note-#{note.id}", reason: "Erreur")
      |> render_submit()

      assert [%{status: :cancelled}] = TeacherAssistant.FeeControl.list_notes(ctx.scope, ctx.e)
    end

    test "warn one student from the drawer", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, page(ctx, "?student=#{ctx.e.id}"))
      view |> element("#warn-student") |> render_click()
      assert [w] = TeacherAssistant.FeeControl.list_warnings(ctx.scope, ctx.e)
      assert has_element?(view, "#warning-#{w.id}", w.number)
      assert has_element?(view, "#last-warnings a[href*='/school/fees/warnings/print']")
    end

    test "warn the class: issues warnings for behind students and links to print",
         %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, page(ctx))
      assert has_element?(view, "#control-link[href='/school/classes/#{ctx.cg.id}/fees/control']")

      assert has_element?(
               view,
               ~s(#fee-settings-link[href="/school/settings/fees"][aria-label="Paramètres des frais"])
             )

      view |> element("#warn-class") |> render_click()
      assert has_element?(view, "#warn-form input[value='#{ctx.e2.id}'][checked]")

      view
      |> form("#warn-form", warn: %{pay_by: "2025-09-22", ids: [ctx.e.id, ctx.e2.id]})
      |> render_submit()

      assert [_] = TeacherAssistant.FeeControl.list_warnings(ctx.scope, ctx.e)
      assert [_] = TeacherAssistant.FeeControl.list_warnings(ctx.scope, ctx.e2)
      assert has_element?(view, "#last-warnings a[href*='/school/fees/warnings/print']")
    end
  end
end
