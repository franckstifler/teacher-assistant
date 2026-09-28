defmodule TeacherAssistantWeb.School.EvaluationsLive do
  @moduledoc """
  Settings → Évaluations & moyennes (spec D2b-1): the school's trimester and annual
  average rules, rounding and tied-rank behaviour. Each choice saves on click. The
  assessment-type and absence rows of the mockup arrive with D2b-2.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}

  alias TeacherAssistant.Academics.{
    AbsenceRule,
    AnnualAverageRule,
    AverageRounding,
    TrimesterAverageRule
  }

  @rules [
    {"trimester_average_rule", :trimester, TrimesterAverageRule, :mean_of_sequences},
    {"annual_average_rule", :annual, AnnualAverageRule, :mean_of_sequences},
    {"average_rounding", :rounding, AverageRounding, nil},
    {"absence_rule", :absence, AbsenceRule, :zero}
  ]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok,
       assign(socket,
         grading: Assessment.grading_rules(scope),
         rule_rows: @rules,
         types: Assessment.list_assessment_types(scope),
         default_max: profile.default_max_score
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="evaluations" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Évaluations & moyennes")} />

        <div
          id="assessment-types"
          class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3"
        >
          <h2 class="ta-eyebrow">{gettext("Types d'évaluation et poids par défaut")}</h2>
          <.form
            :for={t <- @types}
            for={%{}}
            as={:type}
            id={"type-#{t.id}"}
            phx-submit="update_type"
            class="flex flex-wrap items-end gap-2"
          >
            <input type="hidden" name="type_id" value={t.id} />
            <.input name="type[name]" value={t.name} class="input input-sm flex-1" />
            <span class="text-xs text-base-content/60">{gettext("poids")}</span>
            <.input
              name="type[default_weight]"
              value={Decimal.to_string(Decimal.normalize(t.default_weight), :normal)}
              inputmode="decimal"
              class="input input-sm w-20 text-right"
            />
            <button type="submit" class="btn btn-ghost btn-sm">{gettext("Enregistrer")}</button>
            <button
              :if={t.usage_count == 0}
              id={"delete-type-#{t.id}"}
              type="button"
              phx-click="delete_type"
              phx-value-id={t.id}
              class="btn btn-ghost btn-sm"
              aria-label={gettext("Supprimer")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </.form>
          <.form
            for={%{}}
            as={:type}
            id="new-type-form"
            phx-submit="create_type"
            class="flex flex-wrap items-end gap-2"
          >
            <.input
              name="type[name]"
              value=""
              placeholder={gettext("Nouveau type")}
              class="input input-sm flex-1"
            />
            <.input
              name="type[default_weight]"
              value="1"
              inputmode="decimal"
              class="input input-sm w-20 text-right"
            />
            <button type="submit" class="btn btn-outline btn-sm">{gettext("+ Type d'évaluation")}</button>
          </.form>
          <p class="ta-num text-right text-xs text-warning">
            {gettext("Exemple : 12 (×0,5) et 14 (×1) → moyenne 13,33")}
          </p>
        </div>

        <.form
          for={%{}}
          id="default-max-form"
          phx-submit="save_default_max"
          class="flex items-end gap-2"
        >
          <.input
            name="default_max_score"
            value={Decimal.to_string(Decimal.normalize(@default_max), :normal)}
            label={gettext("Note maximale")}
            inputmode="decimal"
            class="input input-sm w-24 text-right"
          />
          <button type="submit" class="btn btn-ghost btn-sm">{gettext("Enregistrer")}</button>
        </.form>

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
                <span :if={value == official} class="text-xs opacity-70">
                  · {if field == "absence_rule",
                    do: gettext("pratique courante"),
                    else: gettext("règle officielle")}
                </span>
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

  def handle_event("create_type", %{"type" => p}, socket), do: save_type(socket, nil, p)

  def handle_event("update_type", %{"type_id" => id, "type" => p}, socket) do
    case Enum.find(socket.assigns.types, &(&1.id == id)) do
      nil -> {:noreply, socket}
      type -> save_type(socket, type, p)
    end
  end

  def handle_event("delete_type", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = type <- Enum.find(socket.assigns.types, &(&1.id == id)) do
      case Assessment.delete_assessment_type(scope, type) do
        {:error, :in_use} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Type utilisé par des évaluations : il est conservé.")
           )}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        _ ->
          {:noreply, assign(socket, types: Assessment.list_assessment_types(scope))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_default_max", %{"default_max_score" => value}, socket) do
    scope = socket.assigns.current_scope

    case Assessment.update_default_max_score(scope, value) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(default_max: profile.default_max_score)
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  defp save_type(socket, type, params) do
    scope = socket.assigns.current_scope

    with {:ok, weight} <-
           TeacherAssistant.Curriculum.parse_coefficient(params["default_weight"] || ""),
         attrs = %{name: params["name"], default_weight: weight},
         {:ok, _} <-
           if(type,
             do: Assessment.update_assessment_type(scope, type, attrs),
             else: Assessment.create_assessment_type(scope, attrs)
           ) do
      {:noreply,
       socket
       |> assign(types: Assessment.list_assessment_types(scope))
       |> put_flash(:info, gettext("Type enregistré."))}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Type non enregistré."))}
    end
  end

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
  defp rule_title("absence_rule"), do: gettext("Élève absent à une évaluation")
end
