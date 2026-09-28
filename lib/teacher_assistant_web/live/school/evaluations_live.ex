defmodule TeacherAssistantWeb.School.EvaluationsLive do
  @moduledoc """
  Settings → Évaluations & moyennes (spec D2b-1): the school's trimester and annual
  average rules, rounding and tied-rank behaviour. Each choice saves on click. The
  assessment-type and absence rows of the mockup arrive with D2b-2.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.{AnnualAverageRule, AverageRounding, TrimesterAverageRule}

  @rules [
    {"trimester_average_rule", :trimester, TrimesterAverageRule, :mean_of_sequences},
    {"annual_average_rule", :annual, AnnualAverageRule, :mean_of_sequences},
    {"average_rounding", :rounding, AverageRounding, nil}
  ]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok, assign(socket, grading: Assessment.grading_rules(scope), rule_rows: @rules)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="evaluations" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Évaluations & moyennes")} />

        <div class="rounded-box border border-base-300 bg-base-100 divide-y divide-base-300">
          <div
            :for={{field, key, enum, official} <- @rule_rows}
            class="flex flex-wrap items-center justify-between gap-3 p-4"
          >
            <p class="font-medium">{rule_title(field)}</p>
            <div class="flex flex-wrap items-center gap-2">
              <button
                :for={value <- enum.values()}
                id={"rule-#{field}-#{value}"}
                type="button"
                phx-click="set_rule"
                phx-value-field={field}
                phx-value-value={value}
                class={[
                  "btn btn-sm rounded-full transition-colors",
                  if(Map.fetch!(@grading, key) == value,
                    do: "btn-primary",
                    else: "btn-ghost border-base-300"
                  )
                ]}
              >
                {enum.label(value)}
                <span :if={value == official} class="text-xs opacity-70">· {gettext(
                  "règle officielle"
                )}</span>
              </button>
            </div>
          </div>

          <div class="flex items-center justify-between gap-4 p-4">
            <div>
              <p class="font-medium">{gettext("Rang ex æquo")}</p>
              <p class="text-xs text-base-content/60">
                {gettext("Désactivé : départage par la moyenne non arrondie, puis par le nom.")}
              </p>
            </div>
            <input
              id="toggle-shared-ranks"
              type="checkbox"
              class="toggle toggle-primary"
              checked={@grading.shared_ranks?}
              phx-click="toggle_shared_ranks"
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("set_rule", %{"field" => field, "value" => value}, socket),
    do: save(socket, %{field => value})

  def handle_event("toggle_shared_ranks", _params, socket),
    do: save(socket, %{"shared_ranks?" => to_string(!socket.assigns.grading.shared_ranks?)})

  defp save(socket, params) do
    scope = socket.assigns.current_scope

    case Assessment.update_grading_rules(scope, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(grading: Assessment.grading_rules(scope))
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  defp rule_title("trimester_average_rule"), do: gettext("Moyenne trimestrielle")
  defp rule_title("annual_average_rule"), do: gettext("Moyenne annuelle")
  defp rule_title("average_rounding"), do: gettext("Arrondi")
end
