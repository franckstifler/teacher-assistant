defmodule TeacherAssistantWeb.School.SchoolLifeSettingsLive do
  @moduledoc """
  Settings → Assiduité & discipline (spec KLM2, mockup `Paramètres école` → Vie
  scolaire): when a late counts as an absence, the justification deadline, the
  absence alert, the conduct scale with a live worked example, and the sanction
  types in use. Admins and the SG.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Academics.{SanctionType, SchoolLifeRules}
  alias TeacherAssistantWeb.Authz

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Attendance.can_edit_school_life?(scope) do
      rules = Attendance.school_life_rules(scope)

      {:ok,
       assign(socket, rules: rules, example: SchoolLifeRules.example_mark(rules), error: nil)}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def handle_event("preview", %{"school_life" => params}, socket) do
    {:noreply, assign(socket, example: preview(socket.assigns.rules, params))}
  end

  def handle_event("save", %{"school_life" => params}, socket) do
    scope = socket.assigns.current_scope

    case Attendance.update_school_life_rules(scope, params) do
      {:ok, _} ->
        rules = Attendance.school_life_rules(scope)

        {:noreply,
         socket
         |> assign(rules: rules, example: SchoolLifeRules.example_mark(rules), error: nil)
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_number} ->
        {:noreply, assign(socket, error: gettext("Utilisez des nombres, par exemple 0,5."))}

      {:error, :no_sanction_type} ->
        {:noreply, assign(socket, error: gettext("Gardez au moins un type de sanction."))}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        message = Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
        {:noreply, assign(socket, error: message)}

      {:error, _} ->
        {:noreply, assign(socket, error: gettext("Réglage non enregistré."))}
    end
  end

  # The example recomputed from what is typed; unreadable values keep the saved ones.
  defp preview(rules, params) do
    number = fn key, saved ->
      case params
           |> Map.get(key, "")
           |> to_string()
           |> String.replace(",", ".")
           |> Decimal.parse() do
        {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> d
        _ -> saved
      end
    end

    points = Map.get(params, "sanction_points", %{})

    SchoolLifeRules.example_mark(%{
      rules
      | points_per_absence_hour:
          number.("conduct_points_per_absence_hour", rules.points_per_absence_hour),
        points_per_late: number.("conduct_points_per_late", rules.points_per_late),
        sanction_points:
          Map.update!(rules.sanction_points, :avertissement, fn saved ->
            case points
                 |> Map.get("avertissement", "")
                 |> to_string()
                 |> String.replace(",", ".")
                 |> Decimal.parse() do
              {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> d
              _ -> saved
            end
          end)
    })
  end

  defp shown(nil), do: ""

  defp shown(%Decimal{} = d),
    do: d |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp shown(n) when is_integer(n), do: Integer.to_string(n)

  def render(assigns) do
    assigns = assign(assigns, types: SanctionType.values())

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-life-settings" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Assiduité & discipline")} />

        <.form
          for={%{}}
          as={:school_life}
          id="school-life-form"
          phx-change="preview"
          phx-submit="save"
          class="space-y-6"
        >
          <fieldset class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4">
            <legend class="ta-eyebrow px-1">{gettext("Retards et absences")}</legend>
            <.input
              name="school_life[late_as_absence_minutes]"
              value={shown(@rules.late_as_absence_minutes)}
              label={gettext("Un retard compte comme une absence au-delà de (minutes)")}
              placeholder={gettext("jamais")}
              inputmode="numeric"
              class="input input-sm w-24 text-right"
            />
            <.input
              name="school_life[justification_deadline_days]"
              value={shown(@rules.justification_deadline_days)}
              label={gettext("Délai de justification (jours de cours)")}
              placeholder={gettext("à tout moment")}
              inputmode="numeric"
              class="input input-sm w-24 text-right"
            />
            <.input
              name="school_life[absence_alert_hours]"
              value={shown(@rules.absence_alert_hours)}
              label={gettext("Alerte après (heures d'absence non justifiée dans la séquence)")}
              inputmode="numeric"
              class="input input-sm w-24 text-right"
            />
          </fieldset>

          <fieldset class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4">
            <legend class="ta-eyebrow px-1">{gettext("Barème de conduite")}</legend>
            <p class="text-xs text-base-content/60">
              {gettext("Chaque élève part de 20/20 par séquence ; chaque fait retire des points.")}
            </p>
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                name="school_life[conduct_points_per_absence_hour]"
                value={shown(@rules.points_per_absence_hour)}
                label={gettext("Par heure d'absence non justifiée")}
                inputmode="decimal"
                class="input input-sm w-24 text-right"
              />
              <.input
                name="school_life[conduct_points_per_late]"
                value={shown(@rules.points_per_late)}
                label={gettext("Par retard")}
                inputmode="decimal"
                class="input input-sm w-24 text-right"
              />
              <.input
                :for={t <- @types}
                name={"school_life[sanction_points][#{t}]"}
                value={shown(@rules.sanction_points[t])}
                label={SanctionType.label(t)}
                inputmode="decimal"
                class="input input-sm w-24 text-right"
              />
            </div>
            <p id="conduct-example" class="rounded-box bg-base-200 px-3 py-2 text-sm">
              {gettext("Exemple : 6 h non justifiées, 2 retards, 1 avertissement → %{mark}/20",
                mark: shown(@example)
              )}
            </p>
          </fieldset>

          <fieldset class="space-y-2 rounded-box border border-base-300 bg-base-100 p-4">
            <legend class="ta-eyebrow px-1">{gettext("Sanctions utilisées")}</legend>
            <input type="hidden" name="school_life[sanction_types_in_use][]" value="" />
            <label :for={t <- @types} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                name="school_life[sanction_types_in_use][]"
                value={t}
                checked={t in @rules.sanction_types_in_use}
              />
              {SanctionType.label(t)}
            </label>
          </fieldset>

          <p :if={@error} id="school-life-error" class="text-sm text-error">{@error}</p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
