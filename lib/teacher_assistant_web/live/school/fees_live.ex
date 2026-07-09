defmodule TeacherAssistantWeb.School.FeesLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Fees
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistantWeb.Money

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- authorized?(scope, cg) do
      {:ok,
       socket
       |> assign(cg: cg, can_edit?: Permissions.fees_manager?(scope))
       |> load_tranches()}
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
          {:noreply,
           socket |> put_flash(:info, gettext("Tranche added.")) |> load_tranches()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not add the tranche."))}
      end
    else
      _ -> {:noreply, socket}
    end
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
           socket |> put_flash(:info, gettext("Tranche updated.")) |> load_tranches()}

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
          {:noreply,
           socket |> put_flash(:info, gettext("Tranche removed.")) |> load_tranches()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the tranche."))}
      end
    else
      _ -> {:noreply, socket}
    end
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
        <.page_header eyebrow={gettext("École")} title={"#{@cg.label} — #{gettext("Frais scolaires")}"} />

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
              <tr :for={tranche <- @tranches} id={"tranche-row-#{tranche.id}"}>
                <td>{tranche.label}</td>
                <td>{Money.format_fcfa(tranche.amount)}</td>
                <td>{Date.to_string(tranche.due_date)}</td>
                <td :if={@can_edit?}>
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
      </section>
    </Layouts.app>
    """
  end
end
