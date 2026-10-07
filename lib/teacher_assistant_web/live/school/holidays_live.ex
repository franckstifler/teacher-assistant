defmodule TeacherAssistantWeb.School.HolidaysLive do
  @moduledoc """
  Settings → Congés & jours fériés (spec J1, S02): the active year's holidays, add /
  edit / delete, and « Préremplir » for the national holidays. Admin axis.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Organization}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         %{} = year <- scope.current_academic_year,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok, socket |> assign(year: year, error: nil, editing: nil) |> load()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket),
    do:
      assign(socket,
        holidays: Organization.list_holidays(socket.assigns.current_scope, socket.assigns.year)
      )

  def handle_event("add", %{"holiday" => params}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, s} <- Date.from_iso8601(params["start_date"] || ""),
         {:ok, e} <- Date.from_iso8601(end_param(params)),
         {:ok, _} <-
           save_holiday(scope, socket.assigns, %{
             label: params["label"],
             start_date: s,
             end_date: e
           }) do
      {:noreply,
       socket
       |> assign(error: nil, editing: nil)
       |> load()
       |> put_flash(:info, gettext("Jour enregistré."))}
    else
      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        {:noreply,
         assign(socket,
           error: Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
         )}

      _ ->
        {:noreply, assign(socket, error: gettext("Indiquez des dates valides."))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, editing: Enum.find(socket.assigns.holidays, &(&1.id == id)), error: nil)}

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, editing: nil, error: nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.holidays, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      h ->
        case Organization.delete_holiday(socket.assigns.current_scope, h) do
          :ok -> {:noreply, load(socket)}
          {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
          {:error, _} -> {:noreply, socket}
        end
    end
  end

  def handle_event("prefill", _params, socket) do
    case Organization.prefill_holidays(socket.assigns.current_scope, socket.assigns.year) do
      {:ok, n} ->
        {:noreply, socket |> load() |> put_flash(:info, gettext("%{n} jour(s) ajouté(s).", n: n))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Spec J1: the form adds a holiday, or updates the one being edited.
  defp save_holiday(scope, %{editing: nil, year: year}, attrs),
    do: Organization.create_holiday(scope, year, attrs)

  defp save_holiday(scope, %{editing: holiday}, attrs),
    do: Organization.update_holiday(scope, holiday, attrs)

  defp field(nil, _key), do: ""
  defp field(holiday, :label), do: holiday.label
  defp field(holiday, key), do: Date.to_iso8601(Map.fetch!(holiday, key))

  # An empty « Au » means a single day.
  defp end_param(%{"end_date" => e}) when is_binary(e) and e != "", do: e
  defp end_param(params), do: params["start_date"] || ""

  defp days(h), do: Date.diff(h.end_date, h.start_date) + 1
  defp d(date), do: Calendar.strftime(date, "%d/%m/%Y")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="holidays" class="space-y-6">
        <.page_header
          eyebrow={gettext("Paramètres")}
          title={gettext("Congés & jours fériés")}
          subtitle={@year.name}
        />

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table :if={@holidays != []} id="holidays-table" class="table">
            <thead>
              <tr>
                <th>{gettext("Libellé")}</th><th>{gettext("Du")}</th><th>{gettext("Au")}</th>
                <th class="text-right">{gettext("Jours")}</th><th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={h <- @holidays} id={"holiday-row-#{h.id}"}>
                <td>{h.label}</td>
                <td class="ta-num">{d(h.start_date)}</td>
                <td class="ta-num">{d(h.end_date)}</td>
                <td class="ta-num text-right">{days(h)}</td>
                <td class="text-right">
                  <button
                    id={"edit-holiday-#{h.id}"}
                    type="button"
                    phx-click="edit"
                    phx-value-id={h.id}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Modifier")}
                  </button>
                  <button
                    id={"delete-holiday-#{h.id}"}
                    type="button"
                    phx-click="delete"
                    phx-value-id={h.id}
                    class="btn btn-ghost btn-xs"
                    data-confirm={gettext("Supprimer ce jour ?")}
                  >
                    {gettext("Supprimer")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@holidays == []} id="holidays-empty" class="p-4 text-sm text-base-content/60">
            {gettext("Aucun congé ni jour férié pour cette année.")}
          </p>
        </div>

        <.form
          for={%{}}
          as={:holiday}
          id="holiday-form"
          phx-submit="add"
          class="grid items-end gap-2 rounded-box border border-base-300 bg-base-100 p-4 sm:grid-cols-4"
        >
          <.input name="holiday[label]" value={field(@editing, :label)} label={gettext("Libellé")} />
          <.input
            name="holiday[start_date]"
            type="date"
            value={field(@editing, :start_date)}
            label={gettext("Du")}
          />
          <.input
            name="holiday[end_date]"
            type="date"
            value={field(@editing, :end_date)}
            label={gettext("Au (facultatif)")}
          />
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm">
              {if @editing, do: gettext("Enregistrer"), else: gettext("Ajouter")}
            </button>
            <button
              :if={@editing}
              id="cancel-edit"
              type="button"
              phx-click="cancel_edit"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Annuler")}
            </button>
          </div>
          <p :if={@error} id="holiday-error" class="text-sm text-error sm:col-span-4">{@error}</p>
        </.form>

        <button id="prefill-holidays" type="button" phx-click="prefill" class="btn btn-ghost btn-sm">
          {gettext("Préremplir les jours fériés nationaux")}
        </button>
      </section>
    </Layouts.app>
    """
  end
end
