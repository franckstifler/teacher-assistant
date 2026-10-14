defmodule TeacherAssistantWeb.School.EvaluationsLive do
  @moduledoc """
  Paramètres → Évaluations et moyennes (specs D2b-1, D2b-2, D3b): the assessment
  types and their default weights (one form, one save bar; a type is added in a
  drawer), the grade-entry settings (one form, one save bar), then the average
  rules — radio cards that save as soon as they are chosen.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment, Curriculum}

  alias TeacherAssistant.Academics.{
    AbsenceRule,
    AnnualAverageRule,
    AverageRounding,
    TrimesterAverageRule
  }

  alias TeacherAssistantWeb.Numbers

  import TeacherAssistantWeb.Drawer

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
         page_title: gettext("Évaluations et moyennes"),
         grading: Assessment.grading_rules(scope),
         rule_rows: @rules,
         types: Assessment.list_assessment_types(scope),
         type_errors: %{},
         types_error: nil,
         adding_type?: false,
         new_type_error: nil,
         default_max: profile.default_max_score,
         grace_days: profile.entry_grace_days,
         entry_errors: []
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="evaluations" class="mx-auto max-w-3xl space-y-6">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Évaluations et moyennes")}
        />

        <.form
          for={%{}}
          as={:types}
          id="types-form"
          phx-submit="save_types"
          phx-hook="DirtyForm"
        >
          <.settings_section
            id="assessment-types"
            title={gettext("Types d'évaluation")}
            subtitle={
              gettext(
                "Le poids par défaut est repris à chaque nouvelle évaluation. Exemple : 12 (×0,5) et 14 (×1) → moyenne 13,33."
              )
            }
          >
            <:actions>
              <button
                id="new-type-button"
                type="button"
                class="btn btn-outline min-h-11"
                phx-click="new_type"
              >
                <.icon name="hero-plus" class="size-4" />{gettext("Ajouter un type")}
              </button>
            </:actions>
            <div
              :for={t <- @types}
              id={"type-#{t.id}"}
              class="border-t border-base-300/60 px-4 py-2.5 first:border-t-0 sm:px-5"
            >
              <div class="flex items-center gap-2">
                <input
                  type="text"
                  id={"type-name-#{t.id}"}
                  name={"types[#{t.id}][name]"}
                  value={t.name}
                  aria-label={gettext("Nom du type")}
                  class={[
                    "input min-w-0 flex-1",
                    :name in error_fields(@type_errors, t) && "input-error"
                  ]}
                />
                <label class={[
                  "input w-24 shrink-0 sm:w-28",
                  :default_weight in error_fields(@type_errors, t) && "input-error"
                ]}>
                  <span class="text-sm text-base-content/60" aria-hidden="true">×</span>
                  <input
                    type="text"
                    id={"type-weight-#{t.id}"}
                    name={"types[#{t.id}][default_weight]"}
                    value={Numbers.decimal(t.default_weight, places: 10, trim: true)}
                    inputmode="decimal"
                    aria-label={gettext("Poids par défaut")}
                    class="ta-num min-w-0 grow text-right"
                  />
                </label>
                <button
                  :if={t.usage_count == 0}
                  id={"delete-type-#{t.id}"}
                  type="button"
                  phx-click="delete_type"
                  phx-value-id={t.id}
                  data-confirm={gettext("Supprimer le type « %{name} » ?", name: t.name)}
                  class="btn btn-ghost btn-square size-11 shrink-0 text-error"
                  aria-label={gettext("Supprimer le type %{name}", name: t.name)}
                >
                  <.icon name="hero-trash" class="size-5" />
                </button>
                <span
                  :if={t.usage_count > 0}
                  class="grid size-11 shrink-0 place-items-center text-base-content/40"
                  title={
                    ngettext(
                      "Utilisé par 1 évaluation : il ne peut pas être supprimé.",
                      "Utilisé par %{count} évaluations : il ne peut pas être supprimé.",
                      t.usage_count
                    )
                  }
                >
                  <.icon name="hero-lock-closed" class="size-4" />
                </span>
              </div>
            </div>
            <p :if={@types == []} class="px-4 pb-4 text-sm text-base-content/70 sm:px-5">
              {gettext("Aucun type d'évaluation pour l'instant.")}
            </p>
            <%!-- `input-error` tells the DirtyForm hook the save failed: the bar stays. --%>
            <p
              :if={@types_error}
              id="types-error"
              role="alert"
              data-save-error
              class="border-t border-base-300/60 px-4 py-3 text-sm text-error sm:px-5"
            >
              {@types_error}
            </p>
          </.settings_section>
          <.save_bar />
        </.form>

        <.form
          for={%{}}
          as={:entry}
          id="entry-form"
          phx-submit="save_entry"
          phx-hook="DirtyForm"
        >
          <.settings_section id="entry-settings" title={gettext("Saisie")}>
            <.settings_row
              label={gettext("Note maximale")}
              for="default-max"
              help={gettext("Proposée pour chaque nouvelle évaluation.")}
            >
              <.unit_input
                id="default-max"
                name="entry[default_max_score]"
                value={Numbers.decimal(@default_max, places: 10, trim: true)}
                unit={gettext("pts")}
              />
              <p
                :if={:default_max_score in @entry_errors}
                id="default-max-error"
                data-save-error
                class="mt-1.5 text-sm text-error sm:text-right"
              >
                {gettext("Un nombre positif, par exemple 20.")}
              </p>
            </.settings_row>
            <.settings_row
              label={gettext("Délai de saisie (jours)")}
              for="entry-grace-days"
              help={gettext("Après la fin de la séquence, quand aucune date limite n'est fixée.")}
            >
              <.unit_input
                id="entry-grace-days"
                name="entry[entry_grace_days]"
                value={@grace_days}
                inputmode="numeric"
                unit={gettext("jours")}
              />
              <p
                :if={:entry_grace_days in @entry_errors}
                id="entry-grace-days-error"
                data-save-error
                class="mt-1.5 text-sm text-error sm:text-right"
              >
                {gettext("Un nombre de jours entre 0 et 30.")}
              </p>
            </.settings_row>
          </.settings_section>
          <.save_bar />
        </.form>

        <.settings_section
          id="average-rules"
          title={gettext("Calcul des moyennes")}
          subtitle={gettext("Chaque choix est enregistré dès que vous le touchez.")}
        >
          <div
            :for={{field, key, enum, official} <- @rule_rows}
            id={"rule-#{field}"}
            role="radiogroup"
            aria-labelledby={"rule-#{field}-label"}
            class="ta-setting !block space-y-2.5"
          >
            <p id={"rule-#{field}-label"} class="text-[0.95rem] font-medium">{rule_title(field)}</p>
            <div class={[
              "grid gap-2",
              if(length(enum.values()) > 2, do: "sm:grid-cols-3", else: "sm:grid-cols-2")
            ]}>
              <label
                :for={value <- enum.values()}
                for={"rule-#{field}-#{value}"}
                class={[
                  "flex min-h-11 cursor-pointer items-start gap-3 rounded-box border border-base-300 p-3 transition-colors",
                  "hover:border-base-content/30 has-[:checked]:border-primary has-[:checked]:bg-primary/15",
                  "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-primary"
                ]}
              >
                <input
                  type="radio"
                  id={"rule-#{field}-#{value}"}
                  name={"rules[#{field}]"}
                  value={value}
                  checked={Map.fetch!(@grading, key) == value}
                  phx-click="set_rule"
                  phx-value-field={field}
                  phx-value-value={value}
                  class="radio radio-primary radio-sm mt-0.5 shrink-0"
                />
                <span class="min-w-0">
                  <span class="block text-sm font-medium">{enum.label(value)}</span>
                  <span :if={value == official} class="block text-xs text-base-content/60">
                    {if field == "absence_rule",
                      do: gettext("pratique courante"),
                      else: gettext("règle officielle")}
                  </span>
                </span>
              </label>
            </div>
          </div>

          <label for="toggle-shared-ranks" class="ta-setting cursor-pointer">
            <span class="min-w-0">
              <span class="text-[0.95rem] font-medium">{gettext("Rang ex æquo")}</span>
              <span class="mt-0.5 block text-sm text-base-content/65">
                {gettext("Désactivé : départage par la moyenne non arrondie, puis par le nom.")}
              </span>
            </span>
            <span class="ta-setting__control flex justify-end">
              <input
                id="toggle-shared-ranks"
                type="checkbox"
                class="toggle toggle-primary"
                checked={@grading.shared_ranks?}
                phx-click="toggle_shared_ranks"
              />
            </span>
          </label>
        </.settings_section>

        <.drawer
          :if={@adding_type?}
          id="type-drawer"
          eyebrow={gettext("Types d'évaluation")}
          title={gettext("Nouveau type")}
          on_close={JS.push("close_type")}
        >
          <.form for={%{}} as={:type} id="new-type-form" phx-submit="create_type" class="space-y-1">
            <.input
              id="new-type-name"
              name="type[name]"
              value=""
              label={gettext("Nom")}
              placeholder={gettext("Interrogation orale, TP noté…")}
            />
            <.input
              id="new-type-weight"
              name="type[default_weight]"
              value="1"
              inputmode="decimal"
              label={gettext("Poids par défaut")}
              class="input w-full ta-num"
            />
            <p :if={@new_type_error} id="new-type-error" role="alert" class="text-sm text-error">
              {@new_type_error}
            </p>
          </.form>
          <:footer>
            <button type="button" class="btn btn-ghost" phx-click="close_type">
              {gettext("Annuler")}
            </button>
            <button type="submit" form="new-type-form" class="btn btn-primary">
              {gettext("Ajouter le type")}
            </button>
          </:footer>
        </.drawer>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("set_rule", %{"field" => field, "value" => value}, socket),
    do: save(socket, %{field => value})

  def handle_event("toggle_shared_ranks", _params, socket),
    do: save(socket, %{"shared_ranks?" => to_string(!socket.assigns.grading.shared_ranks?)})

  def handle_event("new_type", _params, socket),
    do: {:noreply, assign(socket, adding_type?: true, new_type_error: nil)}

  def handle_event("close_type", _params, socket),
    do: {:noreply, assign(socket, adding_type?: false, new_type_error: nil)}

  def handle_event("create_type", %{"type" => params}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, weight} <- Curriculum.parse_coefficient(params["default_weight"] || ""),
         {:ok, _} <-
           Assessment.create_assessment_type(scope, %{
             name: params["name"],
             default_weight: weight
           }) do
      {:noreply,
       socket
       |> assign(types: Assessment.list_assessment_types(scope), adding_type?: false)
       |> put_flash(:info, gettext("Type enregistré."))}
    else
      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply, assign(socket, new_type_error: gettext("Type non enregistré."))}
    end
  end

  def handle_event("save_types", params, socket) do
    scope = socket.assigns.current_scope
    rows = Map.get(params, "types", %{})

    parsed =
      for t <- socket.assigns.types, %{} = row <- [rows[t.id]] do
        {t, String.trim(row["name"] || ""),
         Curriculum.parse_coefficient(row["default_weight"] || "")}
      end

    errors =
      for {t, name, weight} <- parsed,
          fields = invalid_type_fields(name, weight),
          fields != [],
          into: %{},
          do: {t.id, fields}

    changes =
      for {t, name, {:ok, weight}} <- parsed,
          name != t.name or not Decimal.equal?(weight, t.default_weight),
          do: {t, %{name: name, default_weight: weight}}

    if errors != %{} do
      {:noreply,
       assign(socket,
         type_errors: errors,
         types_error: gettext("Un nom et un poids positif (0,5, 1, 2…) pour chaque type.")
       )}
    else
      case Assessment.update_assessment_types(scope, changes) do
        :ok ->
          {:noreply,
           socket
           |> assign(
             types: Assessment.list_assessment_types(scope),
             type_errors: %{},
             types_error: nil
           )
           |> put_flash(:info, gettext("Types enregistrés."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply,
           assign(socket,
             type_errors: %{},
             types_error:
               gettext("Types non enregistrés : deux types ne peuvent pas porter le même nom.")
           )}
      end
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
          {:noreply,
           assign(socket,
             types: Assessment.list_assessment_types(scope),
             type_errors: Map.delete(socket.assigns.type_errors, id)
           )}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_entry", %{"entry" => params}, socket) do
    case Assessment.update_entry_settings(socket.assigns.current_scope, params) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(
           default_max: profile.default_max_score,
           grace_days: profile.entry_grace_days,
           entry_errors: []
         )
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(entry_errors: entry_error_fields(error))
         |> put_flash(:error, gettext("Réglage non enregistré."))}
    end
  end

  defp invalid_type_fields(name, weight) do
    [name == "" && :name, weight == :error && :default_weight] |> Enum.filter(& &1)
  end

  defp error_fields(errors, type), do: Map.get(errors, type.id, [])

  @entry_fields [:default_max_score, :entry_grace_days]

  # The fields to flag: those that did not parse, else those the profile refused.
  defp entry_error_fields({:invalid, fields}), do: fields

  defp entry_error_fields(%Ash.Error.Invalid{errors: errors}) do
    case errors |> Enum.map(&Map.get(&1, :field)) |> Enum.filter(&(&1 in @entry_fields)) do
      [] -> @entry_fields
      fields -> Enum.uniq(fields)
    end
  end

  defp entry_error_fields(_), do: @entry_fields

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
