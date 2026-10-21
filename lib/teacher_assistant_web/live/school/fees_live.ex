defmodule TeacherAssistantWeb.School.FeesLive do
  @moduledoc """
  A class's fees (Fees 1, rules 22–23): what each fee costs the class, then every
  student's due, paid, left and status; `?student=` opens the student's fee card
  (split per fee type, reductions, receipts, « Encaisser ») and `?late=1` keeps only the
  students behind. The fees axis manages; the class's form master reads.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Drawer
  import TeacherAssistantWeb.School.FeeControlComponents

  alias TeacherAssistant.{Enrollment, FeeControl, Fees}
  alias TeacherAssistant.Academics.{PaymentMethod, Reference, ReturnNoteReason}
  alias TeacherAssistantWeb.{Money, ReceiptPrintHTML, ReceiptVerification}

  @methods [:cash, :mobile_money, :bank_transfer, :other]
  @method_strings Map.new(@methods, &{Atom.to_string(&1), &1})

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Fees.can_manage_fees?(scope) or Enrollment.class_manager?(scope, cg),
         {:ok, year} <-
           Ash.get(TeacherAssistant.Academics.AcademicYear, cg.academic_year_id, scope: scope) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         year: year,
         can_edit?: Fees.can_manage_fees?(scope),
         student: nil,
         last_receipt: nil,
         payment_error: nil,
         adjustment_error: nil,
         last_note: nil,
         note_error: nil,
         last_warnings: nil,
         warn_open?: false,
         warn_error: nil
       )
       |> reset_forms()
       |> load()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    socket = assign(socket, late?: params["late"] == "1")

    socket =
      case Enum.find(socket.assigns.roster, &(&1.enrollment.id == params["student"])) do
        nil ->
          assign(socket, student: nil, last_receipt: nil, last_note: nil, note_error: nil)

        %{enrollment: %{id: id}} = row ->
          if socket.assigns.student && socket.assigns.student.enrollment.id == id,
            do: socket |> assign(student: row) |> load_student(),
            else:
              socket
              |> assign(student: row, last_note: nil, note_error: nil, last_warnings: nil)
              |> load_student()
      end

    {:noreply, socket}
  end

  defp scope(socket), do: socket.assigns.current_scope

  defp load(socket) do
    %{cg: cg, year: year} = socket.assigns
    types = Fees.list_fee_types(scope(socket), year)
    grid = Fees.class_fee_grid(scope(socket), year)

    assign(socket,
      types: types,
      class_amounts:
        for(
          t <- types,
          t.kind == :regular and t.active?,
          amount = Map.get(grid, {cg.id, t.id}, 0),
          amount > 0,
          do: {t.name, amount}
        ),
      roster: Enrollment.list_roster(scope(socket), cg),
      balances: Fees.class_balances(scope(socket), cg, Reference.today())
    )
  end

  defp load_student(%{assigns: %{student: nil}} = socket), do: socket

  defp load_student(%{assigns: %{student: row}} = socket),
    do:
      assign(socket,
        student_fees: Fees.student_fees(scope(socket), row.enrollment),
        payments: Fees.list_payments(scope(socket), row.enrollment),
        adjustments: Fees.list_adjustments(scope(socket), row.enrollment),
        notes: FeeControl.list_notes(scope(socket), row.enrollment),
        warnings: FeeControl.list_warnings(scope(socket), row.enrollment)
      )

  # Forms come from the server so they empty after a save.
  defp reset_forms(socket),
    do:
      assign(socket,
        payment_form:
          to_form(
            %{
              "amount" => "",
              "paid_on" => Date.to_iso8601(Reference.today()),
              "method" => "cash",
              "reference" => ""
            },
            as: :payment
          ),
        adjustment_form:
          to_form(%{"fee_type_id" => "", "amount" => "", "reason" => ""}, as: :adjustment),
        note_form:
          to_form(%{"reason" => "promise", "valid_until" => "", "internal_note" => ""}, as: :note)
      )

  # --- events --------------------------------------------------------------------------

  def handle_event("toggle_late", _params, socket) do
    query =
      Enum.reject(
        [
          late: if(!socket.assigns.late?, do: "1"),
          student: socket.assigns.student && socket.assigns.student.enrollment.id
        ],
        fn {_k, v} -> is_nil(v) end
      )

    {:noreply, push_patch(socket, to: ~p"/school/classes/#{socket.assigns.cg.id}/fees?#{query}")}
  end

  def handle_event("change_payment", %{"payment" => params}, socket),
    do: {:noreply, assign(socket, payment_form: to_form(params, as: :payment))}

  def handle_event("record_payment", %{"payment" => params}, socket) do
    with true <- socket.assigns.can_edit?,
         %{enrollment: e} <- socket.assigns.student do
      attrs = %{
        amount: parse_int(params["amount"]),
        paid_on: parse_date(params["paid_on"]),
        method: Map.get(@method_strings, params["method"]),
        reference: params["reference"]
      }

      case Fees.record_payment(scope(socket), e, attrs) do
        {:ok, payment} ->
          {:noreply,
           socket
           |> assign(payment_error: nil, last_receipt: receipt_view(socket, payment))
           |> reset_forms()
           |> load()
           |> load_student()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             payment_form: to_form(params, as: :payment),
             payment_error: payment_error(reason)
           )}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_payment", %{"payment_id" => id, "reason" => reason}, socket) do
    with true <- socket.assigns.can_edit?,
         %{} <- socket.assigns.student,
         %{} = payment <- Enum.find(socket.assigns.payments, &(&1.id == id)) do
      case Fees.cancel_payment(scope(socket), payment, reason) do
        {:ok, _} ->
          {:noreply,
           socket
           |> clear_flash(:error)
           |> put_flash(:info, gettext("Reçu annulé."))
           |> load()
           |> load_student()}

        {:error, :reason_required} ->
          {:noreply, put_flash(socket, :error, gettext("Indiquez la raison de l'annulation."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Modification non enregistrée."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("change_adjustment", %{"adjustment" => params}, socket),
    do: {:noreply, assign(socket, adjustment_form: to_form(params, as: :adjustment))}

  def handle_event("set_adjustment", %{"adjustment" => params}, socket) do
    with true <- socket.assigns.can_edit?,
         %{enrollment: e} <- socket.assigns.student,
         %{} = type <- Enum.find(socket.assigns.types, &(&1.id == params["fee_type_id"])) do
      case Fees.set_adjustment(scope(socket), e, type, %{
             amount: parse_int(params["amount"]),
             reason: params["reason"]
           }) do
        {:ok, _} ->
          {:noreply,
           socket |> assign(adjustment_error: nil) |> reset_forms() |> load() |> load_student()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, :too_large} ->
          {:noreply,
           assign(socket,
             adjustment_form: to_form(params, as: :adjustment),
             adjustment_error: gettext("La réduction dépasse ce que l'élève doit pour ce frais.")
           )}

        {:error, _} ->
          {:noreply,
           assign(socket,
             adjustment_form: to_form(params, as: :adjustment),
             adjustment_error: gettext("Indiquez un montant positif et une raison.")
           )}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_adjustment", %{"type" => type_id}, socket) do
    with true <- socket.assigns.can_edit?,
         %{enrollment: e} <- socket.assigns.student,
         %{} = type <- Enum.find(socket.assigns.types, &(&1.id == type_id)) do
      case Fees.clear_adjustment(scope(socket), e, type) do
        :ok ->
          {:noreply, socket |> load() |> load_student()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Modification non enregistrée."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # --- Fees 2: return notes and warnings ---------------------------------------------------

  def handle_event("change_note", %{"note" => params}, socket),
    do: {:noreply, assign(socket, note_form: to_form(params, as: :note))}

  def handle_event("issue_note", %{"note" => params}, socket) do
    attrs = %{
      reason: Enum.find(ReturnNoteReason.values(), &(Atom.to_string(&1) == params["reason"])),
      valid_until: parse_date(params["valid_until"]),
      internal_note: params["internal_note"]
    }

    issue_note(socket, attrs, params)
  end

  def handle_event("note_after_payment", _params, socket),
    do: issue_note(socket, %{reason: :payment}, nil)

  def handle_event("cancel_note", %{"note_id" => id, "reason" => reason}, socket),
    do: cancel_paper(socket, :notes, id, reason, &FeeControl.cancel_note/3)

  def handle_event("cancel_warning", %{"warning_id" => id, "reason" => reason}, socket),
    do: cancel_paper(socket, :warnings, id, reason, &FeeControl.cancel_warning/3)

  def handle_event("warn_student", _params, socket) do
    with true <- socket.assigns.can_edit?,
         %{enrollment: e} <- socket.assigns.student do
      send_warnings(socket, [e], FeeControl.default_pay_by())
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("warn_class", _params, socket),
    do: {:noreply, assign(socket, warn_open?: !socket.assigns.warn_open?, warn_error: nil)}

  def handle_event("send_warnings", %{"warn" => params}, socket) do
    ids = MapSet.new(params["ids"] || [])
    chosen = for row <- socket.assigns.roster, row.enrollment.id in ids, do: row.enrollment

    case parse_date(params["pay_by"]) do
      nil -> {:noreply, assign(socket, warn_error: gettext("Indiquez une date."))}
      pay_by -> send_warnings(socket, chosen, pay_by)
    end
  end

  defp issue_note(socket, attrs, params) do
    with true <- socket.assigns.can_edit?,
         %{enrollment: e} <- socket.assigns.student do
      case FeeControl.issue_note(scope(socket), e, attrs) do
        {:ok, note} ->
          {:noreply,
           socket
           |> assign(last_note: note, note_error: nil)
           |> reset_forms()
           |> load()
           |> load_student()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, reason} ->
          socket = assign(socket, note_error: note_error(reason))

          {:noreply,
           if(params, do: assign(socket, note_form: to_form(params, as: :note)), else: socket)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp note_error(:invalid_valid_until),
    do: gettext("Indiquez jusqu'à quand l'élève est autorisé (aujourd'hui ou plus tard).")

  defp note_error(_reason), do: gettext("Autorisation non délivrée.")

  defp send_warnings(socket, enrollments, pay_by) do
    if socket.assigns.can_edit? do
      case FeeControl.issue_warnings(scope(socket), enrollments, pay_by) do
        {:ok, warnings} ->
          {:noreply,
           socket
           |> assign(last_warnings: warnings, warn_open?: false, warn_error: nil)
           |> load_student()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, :nothing_to_warn} ->
          {:noreply, assign(socket, warn_error: gettext("Aucun élève en retard."))}

        {:error, :invalid_pay_by} ->
          {:noreply,
           assign(socket, warn_error: gettext("La date doit être aujourd'hui ou plus tard."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Avis non émis."))}
      end
    else
      {:noreply, socket}
    end
  end

  defp cancel_paper(socket, list, id, reason, cancel) do
    with true <- socket.assigns.can_edit?,
         %{} <- socket.assigns.student,
         %{} = paper <- Enum.find(Map.get(socket.assigns, list, []), &(&1.id == id)) do
      case cancel.(scope(socket), paper, reason) do
        {:ok, _} ->
          {:noreply, socket |> clear_flash(:error) |> load() |> load_student()}

        {:error, :reason_required} ->
          {:noreply, put_flash(socket, :error, gettext("Indiquez la raison de l'annulation."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Modification non enregistrée."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # --- helpers ---------------------------------------------------------------------------

  defp receipt_view(socket, payment) do
    {:ok, receipt} = Fees.receipt(scope(socket), payment.id)
    check_url = url(~p"/verify/receipt/#{ReceiptVerification.token(payment)}")
    message = ReceiptPrintHTML.whatsapp_message(receipt, check_url)

    %{
      payment: payment,
      whatsapp:
        receipt.guardians
        |> Enum.map(&%{name: &1.name, url: ReceiptPrintHTML.whatsapp_url(&1.phone, message)})
        |> Enum.filter(& &1.url)
    }
  end

  defp payment_error(:invalid_amount), do: gettext("Indiquez un montant positif.")
  defp payment_error(:invalid_method), do: gettext("Choisissez un mode de paiement.")

  defp payment_error(:reference_required),
    do: gettext("La référence est obligatoire pour le mobile money et le virement.")

  defp payment_error(:no_fee_types),
    do: gettext("Aucun frais n'est défini pour cette année : voir Paramètres des frais.")

  defp payment_error(_reason), do: gettext("Paiement non enregistré.")

  defp parse_int(value) when is_binary(value) do
    case value |> String.replace(~r/\s/u, "") |> Integer.parse() do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp visible_roster(roster, balances, true),
    do: Enum.filter(roster, &(balances[&1.enrollment.id].status == :behind))

  defp visible_roster(roster, _balances, false), do: roster

  defp type_name(types, id), do: Enum.find_value(types, "?", &(&1.id == id && &1.name))

  defp status_badge(:paid_up), do: {gettext("À jour"), "badge-success"}
  defp status_badge(:on_track), do: {gettext("Dans les temps"), "badge-ghost"}
  defp status_badge(:behind), do: {gettext("En retard"), "badge-warning"}

  defp student_path(cg, row, late?),
    do:
      ~p"/school/classes/#{cg.id}/fees?#{Enum.reject([late: late? && "1", student: row.enrollment.id], fn {_, v} -> !v end)}"

  defp close_path(cg, late?),
    do: ~p"/school/classes/#{cg.id}/fees?#{if late?, do: [late: "1"], else: []}"

  defp adjustment_types(types, fees) do
    with_due = MapSet.new(for t <- fees.by_type, t.due > 0 or t.left != 0, do: t.type_id)
    Enum.filter(types, &(&1.active? and (MapSet.member?(with_due, &1.id) or &1.kind == :regular)))
  end

  # The drawer's per-fee table says FCFA once; an overpayment keeps its words.
  defp left_amount(left) when left < 0, do: ReceiptPrintHTML.left(left)
  defp left_amount(left), do: Money.format_amount(left)

  def render(assigns) do
    assigns = assign(assigns, :methods, @methods)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="class-fees" class="space-y-6">
        <.page_header
          eyebrow={gettext("Frais")}
          title={"#{@cg.label} — #{gettext("Frais scolaires")}"}
        >
          <:actions>
            <.link
              id="control-link"
              navigate={~p"/school/classes/#{@cg.id}/fees/control"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-clipboard-document-check" class="size-4" /> {gettext(
                "Contrôle des frais"
              )}
            </.link>
            <button
              :if={@can_edit?}
              id="warn-class"
              type="button"
              phx-click="warn_class"
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-envelope" class="size-4" /> {gettext("Avis de retard")}
            </button>
            <.link :if={@can_edit?} navigate={~p"/school/settings/fees"} class="btn btn-ghost btn-sm">
              <.icon name="hero-cog-6-tooth" class="size-4" /> {gettext("Paramètres des frais")}
            </.link>
          </:actions>
        </.page_header>

        <div id="fees-summary" class="flex flex-wrap gap-2">
          <span :for={{name, amount} <- @class_amounts} class="badge badge-outline py-3">
            {name} · {Money.format_fcfa(amount)}
          </span>
          <span :if={@class_amounts == []} class="text-sm text-base-content/70">
            {gettext("Aucun montant pour cette classe.")}
          </span>
        </div>

        <.warn_class_form
          :if={@warn_open?}
          rows={Enum.filter(@roster, &(@balances[&1.enrollment.id].status == :behind))}
          balances={@balances}
          pay_by={FeeControl.default_pay_by()}
          error={@warn_error}
        />
        <.last_warnings :if={@last_warnings && !@student} warnings={@last_warnings} />

        <div class="flex items-center gap-2">
          <button
            id="late-filter"
            type="button"
            phx-click="toggle_late"
            class={["btn btn-sm", if(@late?, do: "btn-warning", else: "btn-ghost")]}
          >
            <.icon name="hero-funnel" class="size-4" /> {gettext("En retard seulement")}
          </button>
        </div>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table id="fees-roster" class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th class="hidden text-right sm:table-cell">{gettext("Dû")}</th>
                <th class="text-right">{gettext("Payé")}</th>
                <th class="text-right">{gettext("Reste")}</th>
                <th class="hidden sm:table-cell">{gettext("Situation")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- visible_roster(@roster, @balances, @late?)}
                id={"fee-row-#{row.enrollment.id}"}
              >
                <% b = @balances[row.enrollment.id] %>
                <% {label, tone} = status_badge(b.status) %>
                <td class="font-semibold">{row.student.full_name}</td>
                <td class="ta-num hidden whitespace-nowrap text-right sm:table-cell">
                  {Money.format_fcfa(b.total_due)}
                </td>
                <td class="ta-num whitespace-nowrap text-right">{Money.format_fcfa(b.total_paid)}</td>
                <td class="ta-num whitespace-nowrap text-right">{ReceiptPrintHTML.left(b.left)}</td>
                <td class="hidden sm:table-cell">
                  <span class={["badge badge-sm", tone]}>{label}</span>
                </td>
                <td class="text-right">
                  <.link patch={student_path(@cg, row, @late?)} class="btn btn-ghost btn-xs">
                    {if @can_edit?, do: gettext("Encaisser"), else: gettext("Voir")}
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.drawer
          :if={@student}
          id="student-fees"
          eyebrow={@cg.label}
          title={@student.student.full_name}
          on_close={JS.patch(close_path(@cg, @late?))}
        >
          <div class="space-y-5">
            <div
              :if={@last_receipt}
              id="last-receipt"
              class="space-y-2 rounded-box bg-success/12 p-3 text-sm"
            >
              <p class="font-semibold">
                {gettext("Reçu n° %{number} enregistré.", number: @last_receipt.payment.number)}
              </p>
              <div class="flex flex-wrap gap-2">
                <a
                  id="print-receipt"
                  href={~p"/school/fees/receipts/#{@last_receipt.payment.id}/print"}
                  target="_blank"
                  class="btn btn-primary btn-xs"
                >
                  <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer le reçu")}
                </a>
                <a
                  :for={w <- @last_receipt.whatsapp}
                  href={w.url}
                  target="_blank"
                  rel="noopener"
                  class="btn btn-outline btn-xs"
                >
                  {gettext("Envoyer par WhatsApp à %{name}", name: w.name)}
                </a>
                <button
                  :if={@student_fees.status == :behind}
                  id="note-after-payment"
                  type="button"
                  phx-click="note_after_payment"
                  class="btn btn-outline btn-xs"
                >
                  {gettext("Imprimer une autorisation (paiement reçu)")}
                </button>
              </div>
            </div>

            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Frais")}</th>
                  <th class="text-right">{gettext("Dû")}</th>
                  <th class="text-right">{gettext("Payé")}</th>
                  <th class="text-right">{gettext("Reste")}</th>
                </tr>
              </thead>
              <caption class="caption-bottom pt-1 text-left text-xs text-base-content/60">
                {gettext("Montants en FCFA")}
              </caption>
              <tbody>
                <tr :for={t <- @student_fees.by_type}>
                  <td>{t.name}</td>
                  <td class="ta-num whitespace-nowrap text-right">{Money.format_amount(t.due)}</td>
                  <td class="ta-num whitespace-nowrap text-right">{Money.format_amount(t.paid)}</td>
                  <td class="ta-num whitespace-nowrap text-right">{left_amount(t.left)}</td>
                </tr>
                <tr class="font-semibold">
                  <td>{gettext("Total")}</td>
                  <td class="ta-num whitespace-nowrap text-right">
                    {Money.format_amount(@student_fees.total_due)}
                  </td>
                  <td class="ta-num whitespace-nowrap text-right">
                    {Money.format_amount(@student_fees.total_paid)}
                  </td>
                  <td class="ta-num whitespace-nowrap text-right">
                    {left_amount(@student_fees.left)}
                  </td>
                </tr>
              </tbody>
            </table>

            <.form
              :if={@can_edit?}
              for={@payment_form}
              id="payment-form"
              phx-change="change_payment"
              phx-submit="record_payment"
              class="space-y-1 rounded-box border border-base-300 p-3"
            >
              <h3 class="font-semibold">{gettext("Encaisser")}</h3>
              <.input
                field={@payment_form[:amount]}
                label={gettext("Montant (FCFA)")}
                inputmode="numeric"
              />
              <.input field={@payment_form[:paid_on]} type="date" label={gettext("Date")} />
              <.input
                field={@payment_form[:method]}
                type="select"
                options={Enum.map(@methods, &{PaymentMethod.label(&1), &1})}
                label={gettext("Mode")}
              />
              <.input
                :if={@payment_form[:method].value in ["mobile_money", "bank_transfer"]}
                field={@payment_form[:reference]}
                label={gettext("Référence de la transaction")}
              />
              <p :if={@payment_error} id="payment-error" class="text-sm text-error">
                {@payment_error}
              </p>
              <button type="submit" class="btn btn-primary btn-sm w-full">{gettext(
                "Enregistrer et émettre le reçu"
              )}</button>
            </.form>

            <section class="space-y-2">
              <h3 class="font-semibold">{gettext("Reçus")}</h3>
              <p :if={@payments == []} class="text-sm text-base-content/70">
                {gettext("Aucun paiement.")}
              </p>
              <div
                :for={p <- @payments}
                id={"payment-#{p.id}"}
                class="space-y-1 rounded-box border border-base-300 p-2 text-sm"
              >
                <div class="flex items-center justify-between gap-2">
                  <a
                    href={~p"/school/fees/receipts/#{p.id}/print"}
                    target="_blank"
                    class="link font-semibold"
                  >{p.number}</a>
                  <span class="ta-num">{Money.format_fcfa(p.amount)}</span>
                </div>
                <div class="flex items-center justify-between gap-2 text-base-content/70">
                  <span>{ReceiptPrintHTML.date(p.paid_on)} · {PaymentMethod.label(p.method)}</span>
                  <span :if={p.status == :cancelled} class="badge badge-error badge-sm">{gettext(
                    "Annulé"
                  )}</span>
                </div>
                <p :if={p.status == :cancelled and p.cancel_reason} class="text-base-content/70">
                  {gettext("Raison : %{reason}", reason: p.cancel_reason)}
                </p>
                <form
                  :if={@can_edit? and p.status == :valid}
                  id={"cancel-form-#{p.id}"}
                  phx-submit="cancel_payment"
                  class="flex gap-1"
                >
                  <input type="hidden" name="payment_id" value={p.id} />
                  <input
                    name="reason"
                    placeholder={gettext("Raison de l'annulation")}
                    class="input input-xs flex-1"
                    aria-label={gettext("Raison de l'annulation")}
                  />
                  <button
                    type="submit"
                    class="btn btn-ghost btn-xs text-error"
                    data-confirm={gettext("Annuler ce reçu ? Le paiement ne comptera plus.")}
                  >
                    {gettext("Annuler le reçu")}
                  </button>
                </form>
              </div>
            </section>

            <.student_papers
              form={@note_form}
              error={@note_error}
              notes={@notes}
              last_note={@last_note}
              warnings={@warnings}
              last_warnings={@last_warnings}
              can_edit?={@can_edit?}
            />

            <.form
              :if={@can_edit?}
              for={@adjustment_form}
              id="adjustment-form"
              phx-change="change_adjustment"
              phx-submit="set_adjustment"
              class="space-y-1 rounded-box border border-base-300 p-3"
            >
              <h3 class="font-semibold">{gettext("Réduction ou exonération")}</h3>
              <ul :if={@adjustments != []} class="space-y-1 text-sm">
                <li :for={a <- @adjustments} class="flex items-center justify-between gap-2">
                  <span>{type_name(@types, a.fee_type_id)} · −{Money.format_fcfa(a.amount)} · {a.reason}</span>
                  <button
                    id={"remove-adjustment-#{a.fee_type_id}"}
                    type="button"
                    phx-click="remove_adjustment"
                    phx-value-type={a.fee_type_id}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Retirer")}
                  </button>
                </li>
              </ul>
              <.input
                field={@adjustment_form[:fee_type_id]}
                type="select"
                prompt={gettext("Choisir un frais")}
                options={Enum.map(adjustment_types(@types, @student_fees), &{&1.name, &1.id})}
                label={gettext("Frais")}
              />
              <.input
                field={@adjustment_form[:amount]}
                label={gettext("Montant de la réduction")}
                inputmode="numeric"
              />
              <.input field={@adjustment_form[:reason]} label={gettext("Raison")} />
              <p :if={@adjustment_error} class="text-sm text-error">{@adjustment_error}</p>
              <button type="submit" class="btn btn-ghost btn-sm">{gettext("Appliquer")}</button>
            </.form>
          </div>
        </.drawer>
      </section>
    </Layouts.app>
    """
  end
end
