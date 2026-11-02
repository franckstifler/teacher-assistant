defmodule TeacherAssistantWeb.School.SchoolLifeSettingsLive do
  @moduledoc """
  Settings → Assiduité & discipline (spec KLM2, mockup `Paramètres école` → Vie
  scolaire): when a late counts as an absence, the justification deadline, the
  absence alert, the conduct scale with a live worked example, and the sanction
  types in use. Admins and the SG.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Academics.{AbsenceHoursSource, SanctionType, SchoolLifeRules}
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

  # Spec 2026-10-28: paper roll call for every class of the year at once.
  def handle_event("paper_all", %{"paper" => paper}, socket) do
    scope = socket.assigns.current_scope

    case scope.current_academic_year &&
           Attendance.set_paper_roll_call_all(scope, scope.current_academic_year, paper == "true") do
      :ok ->
        {:noreply, put_flash(socket, :info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  # Spec 2026-10-30 §1: the bulletin absence-hours source for every class at once.
  def handle_event("absence_source_all", %{"source" => value}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, source} <- AbsenceHoursSource.match(value),
         %{} = year <- scope.current_academic_year,
         :ok <- Attendance.set_absence_hours_source_all(scope, year, source) do
      {:noreply, put_flash(socket, :info, gettext("Réglage enregistré."))}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
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

      {:error, {:out_of_range, field, min, max}} ->
        {:noreply,
         assign(socket,
           error:
             gettext("%{field} : entre %{min} et %{max}.",
               field: field_label(field),
               min: min,
               max: max
             )
         )}

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

  defp field_label(:late_as_absence_minutes), do: gettext("Retard compté comme absence")
  defp field_label(:justification_deadline_days), do: gettext("Délai de justification")
  defp field_label(:absence_alert_hours), do: gettext("Alerte")

  defp field_label(:conduct_points_per_absence_hour),
    do: gettext("Par heure d'absence non justifiée")

  defp field_label(:conduct_points_per_late), do: gettext("Par retard")
  defp field_label({:sanction_points, type}), do: SanctionType.label(type)

  defp shown(nil), do: ""

  defp shown(%Decimal{} = d),
    do: d |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp shown(n) when is_integer(n), do: Integer.to_string(n)

  # Without the « Appel » module there is no roll call to compute from (spec 2026-10-30 §1).
  defp absence_sources(scope) do
    if TeacherAssistant.Scope.module?(scope, :appel),
      do: AbsenceHoursSource.values(),
      else: AbsenceHoursSource.values() -- [:roll_call]
  end

  def render(assigns) do
    assigns = assign(assigns, types: SanctionType.values())

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-life-settings" class="mx-auto max-w-3xl space-y-6">
        <%!-- Under Paramètres only for whom the menu has it; the intendant and the
             surveillant open this page from their own menu entry. --%>
        <.back_header
          back={
            TeacherAssistantWeb.Spaces.owner_item_for(@current_scope, ["settings"]) &&
              ~p"/school/settings"
          }
          back_label={gettext("Paramètres")}
          title={gettext("Assiduité & discipline")}
        />

        <.form
          for={%{}}
          as={:school_life}
          id="school-life-form"
          phx-change="preview"
          phx-submit="save"
          phx-hook="DirtyForm"
          class="space-y-5"
        >
          <.settings_section title={gettext("Retards et absences")}>
            <.settings_row
              label={gettext("Un retard compte comme une absence")}
              for="late-as-absence"
              help={gettext("Au-delà de ce nombre de minutes. Vide : jamais.")}
            >
              <.unit_input
                id="late-as-absence"
                name="school_life[late_as_absence_minutes]"
                value={shown(@rules.late_as_absence_minutes)}
                placeholder={gettext("jamais")}
                inputmode="numeric"
                unit={gettext("min")}
              />
            </.settings_row>
            <.settings_row
              label={gettext("Délai de justification")}
              for="justification-deadline"
              help={gettext("En jours de cours. Vide : à tout moment.")}
            >
              <.unit_input
                id="justification-deadline"
                name="school_life[justification_deadline_days]"
                value={shown(@rules.justification_deadline_days)}
                placeholder={gettext("à tout moment")}
                inputmode="numeric"
                unit={gettext("jours")}
              />
            </.settings_row>
            <.settings_row
              label={gettext("Alerte d'absences")}
              for="absence-alert"
              help={gettext("Heures d'absence non justifiée dans la séquence.")}
            >
              <.unit_input
                id="absence-alert"
                name="school_life[absence_alert_hours]"
                value={shown(@rules.absence_alert_hours)}
                inputmode="numeric"
                unit={gettext("h")}
              />
            </.settings_row>
          </.settings_section>

          <.settings_section
            title={gettext("Barème de conduite")}
            subtitle={
              gettext("Chaque élève part de 20/20 par séquence ; chaque fait retire des points.")
            }
          >
            <.settings_row
              label={gettext("Par heure d'absence non justifiée")}
              for="points-absence-hour"
            >
              <.unit_input
                id="points-absence-hour"
                name="school_life[conduct_points_per_absence_hour]"
                value={shown(@rules.points_per_absence_hour)}
                inputmode="decimal"
                unit={gettext("pt")}
              />
            </.settings_row>
            <.settings_row label={gettext("Par retard")} for="points-late">
              <.unit_input
                id="points-late"
                name="school_life[conduct_points_per_late]"
                value={shown(@rules.points_per_late)}
                inputmode="decimal"
                unit={gettext("pt")}
              />
            </.settings_row>
            <.settings_row :for={t <- @types} label={SanctionType.label(t)} for={"points-#{t}"}>
              <.unit_input
                id={"points-#{t}"}
                name={"school_life[sanction_points][#{t}]"}
                value={shown(@rules.sanction_points[t])}
                inputmode="decimal"
                unit={gettext("pt")}
              />
            </.settings_row>
            <p id="conduct-example" class="ta-setting text-sm">
              <span class="text-base-content/70">
                {gettext("Exemple : 6 h non justifiées, 2 retards, 1 avertissement")}
              </span>
              <span class="ta-num text-right text-base font-semibold">{shown(@example)}/20</span>
            </p>
          </.settings_section>

          <.settings_section
            title={gettext("Sanctions utilisées")}
            subtitle={gettext("Seules les sanctions cochées sont proposées.")}
          >
            <input type="hidden" name="school_life[sanction_types_in_use][]" value="" />
            <label
              :for={t <- @types}
              class="ta-setting cursor-pointer !grid-cols-[minmax(0,1fr)_auto] items-center"
            >
              <span class="text-[0.95rem] font-medium">{SanctionType.label(t)}</span>
              <span class="ta-setting__control flex justify-end">
                <input
                  type="checkbox"
                  class="toggle toggle-primary"
                  name="school_life[sanction_types_in_use][]"
                  value={t}
                  checked={t in @rules.sanction_types_in_use}
                />
              </span>
            </label>
          </.settings_section>

          <p :if={@error} id="school-life-error" class="text-sm text-error">{@error}</p>
          <.save_bar />
        </.form>

        <.settings_section
          id="paper-roll-call"
          title={gettext("Appel sur feuille")}
          subtitle={
            gettext(
              "Chaque semaine, une feuille d'appel imprimée par classe, saisie par le surveillant. Chaque classe peut aussi le changer dans son cahier d'appel."
            )
          }
        >
          <div class="flex flex-wrap gap-2 px-4 pb-4 sm:px-5">
            <button
              id="paper-all-on"
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="paper_all"
              phx-value-paper="true"
            >
              {gettext("Toutes les classes")}
            </button>
            <button
              id="paper-all-off"
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="paper_all"
              phx-value-paper="false"
              data-confirm={
                gettext(
                  "Plus aucune classe sur feuille : les appels non faits dans l'application seront signalés le jour même."
                )
              }
            >
              {gettext("Aucune classe")}
            </button>
          </div>
        </.settings_section>

        <.settings_section
          id="absence-hours-source"
          title={gettext("Heures d'absence au bulletin")}
          subtitle={
            gettext(
              "Calculées depuis l'appel, ou saisies à la main à partir des feuilles. Pour toutes les classes ; chaque classe peut aussi le changer dans sa page Discipline."
            )
          }
        >
          <div class="flex flex-wrap gap-2 px-4 pb-4 sm:px-5">
            <button
              :for={source <- absence_sources(@current_scope)}
              id={"absence-source-all-#{source}"}
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="absence_source_all"
              phx-value-source={source}
            >
              {AbsenceHoursSource.label(source)}
            </button>
          </div>
        </.settings_section>
      </section>
    </Layouts.app>
    """
  end
end
