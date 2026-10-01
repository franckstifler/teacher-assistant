defmodule TeacherAssistantWeb.School.PassageLive do
  @moduledoc """
  Settings → Passage & redoublement (spec I4, mockup `Paramètres école`): the passing,
  rachat and exclusion averages, the one-repeat-per-cycle and conduct rules, and the
  unjustified-absence limit the annual council's proposals use. One form; an empty
  rachat, exclusion or hours value switches that rule off.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok, assign(socket, rules: Assessment.passage_rules(scope), error: nil)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def handle_event("save", %{"passage" => params}, socket) do
    scope = socket.assigns.current_scope

    case Assessment.update_passage_rules(scope, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(rules: Assessment.passage_rules(scope), error: nil)
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_number} ->
        {:noreply, assign(socket, error: gettext("Utilisez des nombres, par exemple 9,5."))}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        message = Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
        {:noreply, assign(socket, error: message)}

      {:error, _} ->
        {:noreply, assign(socket, error: gettext("Réglage non enregistré."))}
    end
  end

  defp shown(nil), do: ""
  defp shown(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp shown(n) when is_integer(n), do: Integer.to_string(n)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="passage" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Passage & redoublement")} />

        <.form
          for={%{}}
          as={:passage}
          id="passage-form"
          phx-submit="save"
          class="space-y-4 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <p class="text-xs text-base-content/60">
            {gettext(
              "Seuils sur la moyenne annuelle (sur 20), utilisés pour proposer une décision au conseil de fin d'année. Laisser vide pour ne pas appliquer une règle."
            )}
          </p>
          <div class="grid gap-3 sm:grid-cols-3">
            <.input
              name="passage[passage_min]"
              value={shown(@rules.passage_min)}
              label={gettext("Moyenne annuelle de passage")}
              inputmode="decimal"
              class="input input-sm w-24 text-right"
            />
            <.input
              name="passage[rachat_min]"
              value={shown(@rules.rachat_min)}
              label={gettext("Moyenne de rachat (décision du conseil)")}
              inputmode="decimal"
              class="input input-sm w-24 text-right"
            />
            <.input
              name="passage[exclusion_below]"
              value={shown(@rules.exclusion_below)}
              label={gettext("Exclusion si moyenne annuelle inférieure à")}
              inputmode="decimal"
              class="input input-sm w-24 text-right"
            />
          </div>
          <.input
            name="passage[exclusion_absence_hours]"
            value={shown(@rules.exclusion_absence_hours)}
            label={gettext("Absences non justifiées entraînant l'exclusion (heures / an)")}
            inputmode="numeric"
            class="input input-sm w-24 text-right"
          />
          <.input
            type="checkbox"
            name="passage[one_repeat_per_cycle?]"
            checked={@rules.one_repeat_per_cycle?}
            label={gettext("Un seul redoublement par cycle (un redoublant qui échoue est exclu)")}
          />
          <.input
            type="checkbox"
            name="passage[exclusion_on_conduct?]"
            checked={@rules.exclusion_on_conduct?}
            label={gettext("Conduite inférieure à 10 : exclusion proposée")}
          />
          <p :if={@error} id="passage-error" class="text-sm text-error">{@error}</p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
