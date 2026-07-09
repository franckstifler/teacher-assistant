defmodule TeacherAssistantWeb.School.FeesLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Fees
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistantWeb.Money

  @payment_methods [:cash, :mobile_money, :bank_transfer, :other]
  @method_strings Map.new(@payment_methods, &{Atom.to_string(&1), &1})

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- authorized?(scope, cg) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         can_edit?: Permissions.fees_manager?(scope),
         editing_id: nil,
         roster: Academics.list_roster(cg),
         payment_methods: @payment_methods,
         viewing_history_id: nil,
         history_payments: []
       )
       |> load_tranches()
       |> load_balances()}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp authorized?(scope, cg) do
    Permissions.fees_manager?(scope) or Permissions.admin_or_form_master?(scope, cg)
  end

  defp load_tranches(socket) do
    tranches = Fees.list_tranches(socket.assigns.cg)
    total = Enum.reduce(tranches, 0, &(&1.amount + &2))
    assign(socket, tranches: tranches, total: total)
  end

  defp load_balances(socket) do
    balances = Fees.class_balances(socket.assigns.cg, Date.utc_today())
    assign(socket, balances: balances)
  end

  defp load_history(socket, enrollment_id) do
    case Enum.find(socket.assigns.roster, &(&1.enrollment.id == enrollment_id)) do
      %{} = row -> assign(socket, history_payments: Fees.list_payments(row.enrollment))
      nil -> assign(socket, history_payments: [])
    end
  end

  defp refresh_history_if_open(socket, enrollment_id) do
    if socket.assigns.viewing_history_id == enrollment_id do
      load_history(socket, enrollment_id)
    else
      socket
    end
  end

  def handle_event("add_tranche", params, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.fees_manager?(scope),
         {:ok, amount} <- parse_amount(params["amount"]),
         {:ok, date} <- Date.from_iso8601(params["due_date"] || "") do
      attrs = %{
        label: presence(params["label"]),
        amount: amount,
        due_date: date
      }

      case Fees.add_tranche(socket.assigns.cg, attrs) do
        {:ok, _tranche} ->
          {:noreply, socket |> put_flash(:info, gettext("Tranche added.")) |> load_tranches()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not add the tranche."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_tranche", %{"tranche_id" => tranche_id}, socket) do
    if socket.assigns.can_edit? do
      {:noreply, assign(socket, editing_id: tranche_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_tranche", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("update_tranche", %{"tranche_id" => tranche_id} = params, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.fees_manager?(scope),
         %{} = tranche <- Enum.find(socket.assigns.tranches, &(&1.id == tranche_id)),
         {:ok, amount} <- parse_amount(params["amount"]),
         {:ok, date} <- Date.from_iso8601(params["due_date"] || "") do
      attrs = %{
        label: presence(params["label"]),
        amount: amount,
        due_date: date
      }

      case Fees.update_tranche(tranche, attrs) do
        {:ok, _tranche} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Tranche updated."))
           |> assign(editing_id: nil)
           |> load_tranches()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update the tranche."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_tranche", %{"tranche_id" => tranche_id}, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.fees_manager?(scope),
         %{} = tranche <- Enum.find(socket.assigns.tranches, &(&1.id == tranche_id)) do
      case Fees.delete_tranche(tranche) do
        :ok ->
          {:noreply, socket |> put_flash(:info, gettext("Tranche removed.")) |> load_tranches()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the tranche."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_history", %{"enrollment_id" => enrollment_id}, socket) do
    current = socket.assigns.viewing_history_id

    if current == enrollment_id do
      {:noreply, assign(socket, viewing_history_id: nil, history_payments: [])}
    else
      {:noreply,
       socket
       |> assign(viewing_history_id: enrollment_id)
       |> load_history(enrollment_id)}
    end
  end

  def handle_event("record_payment", params, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.fees_manager?(scope),
         %{} = row <-
           Enum.find(socket.assigns.roster, &(&1.enrollment.id == params["enrollment_id"])),
         {:ok, amount} <- parse_positive_amount(params["amount"]),
         {:ok, method} <- fetch_method(params["method"]),
         {:ok, date} <- Date.from_iso8601(params["paid_on"] || "") do
      attrs = %{
        amount: amount,
        paid_on: date,
        method: method,
        reference: presence(params["reference"]),
        note: presence(params["note"])
      }

      case Fees.record_payment(row.enrollment, attrs, scope.current_user.id) do
        {:ok, _payment} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Payment recorded."))
           |> load_balances()
           |> refresh_history_if_open(row.enrollment.id)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not record the payment."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "delete_payment",
        %{"payment_id" => payment_id, "enrollment_id" => enrollment_id},
        socket
      ) do
    scope = socket.assigns.current_scope

    with true <- Permissions.fees_manager?(scope),
         %{} = row <-
           Enum.find(socket.assigns.roster, &(&1.enrollment.id == enrollment_id)),
         %{} = payment <-
           Enum.find(Fees.list_payments(row.enrollment), &(&1.id == payment_id)) do
      case Fees.delete_payment(payment) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Payment removed."))
           |> load_balances()
           |> refresh_history_if_open(enrollment_id)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the payment."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_adjustment", params, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.fees_manager?(scope),
         %{} = row <-
           Enum.find(socket.assigns.roster, &(&1.enrollment.id == params["enrollment_id"])),
         {:ok, amount} <- parse_amount(params["amount"]) do
      attrs = %{amount: amount, reason: presence(params["reason"])}

      case Fees.set_adjustment(row.enrollment, attrs, scope.current_user.id) do
        {:ok, _adjustment} ->
          {:noreply, socket |> put_flash(:info, gettext("Adjustment saved.")) |> load_balances()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not save the adjustment."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_adjustment", %{"enrollment_id" => enrollment_id}, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.fees_manager?(scope),
         %{} = row <-
           Enum.find(socket.assigns.roster, &(&1.enrollment.id == enrollment_id)) do
      case Fees.clear_adjustment(row.enrollment) do
        {:ok, _count} ->
          {:noreply,
           socket |> put_flash(:info, gettext("Adjustment cleared.")) |> load_balances()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not clear the adjustment."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp fetch_method(str) when is_binary(str) do
    case Map.fetch(@method_strings, str) do
      {:ok, method} -> {:ok, method}
      :error -> {:error, :invalid_method}
    end
  end

  defp fetch_method(_), do: {:error, :invalid_method}

  defp parse_positive_amount(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_positive_amount(_), do: {:error, :invalid_amount}

  defp method_label(:cash), do: gettext("Espèces")
  defp method_label(:mobile_money), do: gettext("Mobile money")
  defp method_label(:bank_transfer), do: gettext("Virement bancaire")
  defp method_label(:other), do: gettext("Autre")

  defp status_chip(%{status: :paid_up}), do: gettext("Soldé")
  defp status_chip(%{status: :on_track}), do: gettext("À jour")

  defp status_chip(%{status: :behind} = balance) do
    shortfall = balance.due_to_date - balance.total_paid
    gettext("En retard (−%{amount})", amount: Money.format_fcfa(shortfall))
  end

  defp parse_amount(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_amount(_), do: {:error, :invalid_amount}

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-fees" class="space-y-6">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{gettext("Frais scolaires")}"}
        />

        <div class="overflow-x-auto">
          <table id="fee-schedule" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Libellé")}</th>
                <th>{gettext("Montant")}</th>
                <th>{gettext("Échéance")}</th>
                <th :if={@can_edit?}><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={tranche <- @tranches}
                :if={@editing_id != tranche.id}
                id={"tranche-row-#{tranche.id}"}
              >
                <td>{tranche.label}</td>
                <td>{Money.format_fcfa(tranche.amount)}</td>
                <td>{Date.to_string(tranche.due_date)}</td>
                <td :if={@can_edit?} class="flex gap-2">
                  <button
                    id={"edit-tranche-#{tranche.id}"}
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="edit_tranche"
                    phx-value-tranche_id={tranche.id}
                  >
                    {gettext("Éditer")}
                  </button>
                  <button
                    id={"delete-tranche-#{tranche.id}"}
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="delete_tranche"
                    phx-value-tranche_id={tranche.id}
                    data-confirm={gettext("Supprimer cette tranche ?")}
                  >
                    {gettext("Supprimer")}
                  </button>
                </td>
              </tr>
              <tr
                :for={tranche <- @tranches}
                :if={@can_edit? and @editing_id == tranche.id}
                id={"tranche-row-#{tranche.id}"}
              >
                <td colspan="4">
                  <form
                    id={"tranche-edit-form-#{tranche.id}"}
                    phx-submit="update_tranche"
                    class="grid gap-2 sm:grid-cols-4 items-center"
                  >
                    <input type="hidden" name="tranche_id" value={tranche.id} />
                    <input
                      type="text"
                      name="label"
                      value={tranche.label}
                      placeholder={gettext("Libellé")}
                      class="input input-bordered input-sm"
                    />
                    <input
                      type="number"
                      name="amount"
                      min="0"
                      value={tranche.amount}
                      placeholder={gettext("Montant (FCFA)")}
                      class="input input-bordered input-sm"
                    />
                    <input
                      type="date"
                      name="due_date"
                      value={Date.to_string(tranche.due_date)}
                      class="input input-bordered input-sm"
                    />
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary btn-xs">
                        {gettext("Enregistrer")}
                      </button>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="cancel_edit_tranche"
                      >
                        {gettext("Annuler")}
                      </button>
                    </div>
                  </form>
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <th>{gettext("Total")}</th>
                <th>{Money.format_fcfa(@total)}</th>
                <th></th>
                <th :if={@can_edit?}></th>
              </tr>
            </tfoot>
          </table>

          <.empty_state
            :if={@tranches == []}
            icon="hero-banknotes"
            title={gettext("Aucune tranche définie")}
          />
        </div>

        <div :if={@can_edit?} class="ta-leaf space-y-3">
          <h2 class="text-sm font-semibold">{gettext("Ajouter une tranche")}</h2>
          <form id="fees-add-form" phx-submit="add_tranche" class="space-y-2">
            <div class="grid gap-2 sm:grid-cols-3">
              <input
                type="text"
                name="label"
                placeholder={gettext("Libellé")}
                class="input input-bordered input-sm"
              />
              <input
                type="number"
                name="amount"
                min="0"
                placeholder={gettext("Montant (FCFA)")}
                class="input input-bordered input-sm"
              />
              <input type="date" name="due_date" class="input input-bordered input-sm" />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
          </form>
        </div>

        <div class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Paiements & soldes")}</h2>

          <div class="overflow-x-auto">
            <table id="balances-table" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Élève")}</th>
                  <th>{gettext("Total dû")}</th>
                  <th>{gettext("Total payé")}</th>
                  <th>{gettext("Solde")}</th>
                  <th>{gettext("Statut")}</th>
                  <th :if={@can_edit?}><span class="sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @roster} id={"balance-row-#{row.enrollment.id}"}>
                  <% balance = Map.get(@balances, row.enrollment.id) %>
                  <td>{row.student.full_name}</td>
                  <td>{Money.format_fcfa(balance.total_due)}</td>
                  <td>{Money.format_fcfa(balance.total_paid)}</td>
                  <td>{Money.format_fcfa(balance.balance)}</td>
                  <td>
                    <span id={"status-chip-#{row.enrollment.id}"} class="badge badge-sm">
                      {status_chip(balance)}
                    </span>
                  </td>
                  <td :if={@can_edit?}>
                    <button
                      id={"toggle-history-#{row.enrollment.id}"}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="toggle_history"
                      phx-value-enrollment_id={row.enrollment.id}
                    >
                      {gettext("Historique")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="space-y-6">
            <div :for={row <- @roster} class="ta-leaf space-y-3">
              <h3 class="text-sm font-semibold">{row.student.full_name}</h3>

              <form
                id={"record-payment-form-#{row.enrollment.id}"}
                phx-submit="record_payment"
                class="grid gap-2 sm:grid-cols-6 items-center"
              >
                <input type="hidden" name="enrollment_id" value={row.enrollment.id} />
                <input
                  type="number"
                  name="amount"
                  min="1"
                  placeholder={gettext("Montant (FCFA)")}
                  class="input input-bordered input-sm"
                />
                <input
                  type="date"
                  name="paid_on"
                  value={Date.to_iso8601(Date.utc_today())}
                  class="input input-bordered input-sm"
                />
                <select name="method" class="select select-bordered select-sm">
                  <option :for={m <- @payment_methods} value={m}>{method_label(m)}</option>
                </select>
                <input
                  type="text"
                  name="reference"
                  placeholder={gettext("Référence (optionnel)")}
                  class="input input-bordered input-sm"
                />
                <input
                  type="text"
                  name="note"
                  placeholder={gettext("Note (optionnel)")}
                  class="input input-bordered input-sm"
                />
                <button type="submit" class="btn btn-primary btn-xs">
                  {gettext("Enregistrer le paiement")}
                </button>
              </form>

              <form
                id={"adjustment-form-#{row.enrollment.id}"}
                phx-submit="set_adjustment"
                class="grid gap-2 sm:grid-cols-4 items-center"
              >
                <input type="hidden" name="enrollment_id" value={row.enrollment.id} />
                <input
                  type="number"
                  name="amount"
                  min="0"
                  placeholder={gettext("Ajustement (FCFA)")}
                  class="input input-bordered input-sm"
                />
                <input
                  type="text"
                  name="reason"
                  placeholder={gettext("Motif")}
                  class="input input-bordered input-sm"
                />
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-secondary btn-xs">
                    {gettext("Appliquer l'ajustement")}
                  </button>
                  <button
                    id={"clear-adjustment-#{row.enrollment.id}"}
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="clear_adjustment"
                    phx-value-enrollment_id={row.enrollment.id}
                    data-confirm={gettext("Effacer l'ajustement ?")}
                  >
                    {gettext("Effacer")}
                  </button>
                </div>
              </form>

              <div :if={@viewing_history_id == row.enrollment.id} class="overflow-x-auto">
                <table id={"payment-history-#{row.enrollment.id}"} class="table table-zebra table-sm">
                  <thead>
                    <tr>
                      <th>{gettext("Date")}</th>
                      <th>{gettext("Montant")}</th>
                      <th>{gettext("Méthode")}</th>
                      <th>{gettext("Référence")}</th>
                      <th><span class="sr-only">{gettext("Actions")}</span></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={payment <- @history_payments}
                      id={"payment-row-#{payment.id}"}
                    >
                      <td>{Date.to_string(payment.paid_on)}</td>
                      <td>{Money.format_fcfa(payment.amount)}</td>
                      <td>{method_label(payment.method)}</td>
                      <td>{payment.reference || "—"}</td>
                      <td>
                        <button
                          id={"delete-payment-#{payment.id}"}
                          type="button"
                          class="btn btn-ghost btn-xs"
                          phx-click="delete_payment"
                          phx-value-payment_id={payment.id}
                          phx-value-enrollment_id={row.enrollment.id}
                          data-confirm={gettext("Supprimer ce paiement ?")}
                        >
                          {gettext("Supprimer")}
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
