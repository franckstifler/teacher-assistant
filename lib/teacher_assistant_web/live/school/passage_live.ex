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
      <section id="passage" class="mx-auto max-w-3xl space-y-6">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Passage & redoublement")}
          subtitle={
            gettext(
              "Seuils sur la moyenne annuelle (sur 20), utilisés pour proposer une décision au conseil de fin d'année. Laisser vide pour ne pas appliquer une règle."
            )
          }
        />

        <.form
          for={%{}}
          as={:passage}
          id="passage-form"
          phx-submit="save"
          phx-hook="DirtyForm"
          class="space-y-5"
        >
          <.settings_section title={gettext("Moyennes")}>
            <.settings_row label={gettext("Moyenne annuelle de passage")} for="passage-min">
              <.unit_input
                id="passage-min"
                name="passage[passage_min]"
                value={shown(@rules.passage_min)}
                unit="/ 20"
              />
            </.settings_row>
            <.settings_row
              label={gettext("Moyenne de rachat")}
              for="rachat-min"
              help={gettext("Le conseil peut accorder le passage à partir de cette moyenne.")}
            >
              <.unit_input
                id="rachat-min"
                name="passage[rachat_min]"
                value={shown(@rules.rachat_min)}
                unit="/ 20"
              />
            </.settings_row>
            <.settings_row
              label={gettext("Exclusion si moyenne annuelle inférieure à")}
              for="exclusion-below"
            >
              <.unit_input
                id="exclusion-below"
                name="passage[exclusion_below]"
                value={shown(@rules.exclusion_below)}
                unit="/ 20"
              />
            </.settings_row>
          </.settings_section>

          <.settings_section title={gettext("Exclusion")}>
            <.settings_row
              label={gettext("Absences non justifiées entraînant l'exclusion")}
              for="exclusion-absence-hours"
              help={gettext("Sur l'année.")}
            >
              <.unit_input
                id="exclusion-absence-hours"
                name="passage[exclusion_absence_hours]"
                value={shown(@rules.exclusion_absence_hours)}
                inputmode="numeric"
                unit={gettext("h")}
              />
            </.settings_row>
            <.toggle_row
              name="passage[one_repeat_per_cycle?]"
              checked={@rules.one_repeat_per_cycle?}
              label={gettext("Un seul redoublement par cycle")}
              help={gettext("Un redoublant qui échoue est exclu.")}
            />
            <.toggle_row
              name="passage[exclusion_on_conduct?]"
              checked={@rules.exclusion_on_conduct?}
              label={gettext("Conduite inférieure à 10 : exclusion proposée")}
            />
          </.settings_section>

          <p :if={@error} id="passage-error" class="text-sm text-error">{@error}</p>
          <.save_bar />
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
