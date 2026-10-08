defmodule TeacherAssistantWeb.School.EnrollImportLive do
  @moduledoc """
  Import d'élèves (Élèves redesign, 2026-10-08): paste one line per student,
  check what each line will do, confirm. Lines are re-checked at confirm.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.RosterLine

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Enrollment.can_manage_classes?(scope) do
      {:ok,
       socket
       |> assign(cg: cg, stage: :paste, raw: "", preview: [], result: nil)
       |> assign(:capacity, Enrollment.capacity(scope, cg))}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes/#{id}")}
    end
  end

  def handle_event("parse", %{"import" => %{"raw" => raw}}, socket) do
    preview =
      Enrollment.preview_rows(socket.assigns.current_scope, socket.assigns.cg, RosterLine.parse(raw))

    {:noreply, assign(socket, raw: raw, preview: preview, stage: :preview)}
  end

  def handle_event("back", _params, socket), do: {:noreply, assign(socket, :stage, :paste)}

  def handle_event("restart", _params, socket),
    do: {:noreply, assign(socket, stage: :paste, raw: "", preview: [], result: nil)}

  def handle_event("confirm", _params, socket) do
    %{current_scope: scope, cg: cg, raw: raw} = socket.assigns
    result = Enrollment.import_rows(scope, cg, RosterLine.parse(raw))

    {:noreply,
     assign(socket, result: result, stage: :done, capacity: Enrollment.capacity(scope, cg))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="enroll-import" class="flex flex-col gap-5">
        <.breadcrumb>
          <:crumb navigate={~p"/school/classes"}>{gettext("Classes")}</:crumb>
          <:crumb navigate={~p"/school/classes/#{@cg.id}"}>{@cg.label}</:crumb>
          <:crumb>{gettext("Import")}</:crumb>
        </.breadcrumb>

        <.page_header
          eyebrow={"#{@cg.label} · #{capacity_text(@capacity.count, @capacity.max)}"}
          title={gettext("Importer une liste d'élèves")}
        />

        <ol id="import-stepper" class="flex flex-wrap gap-2 text-sm">
          <li
            :for={{{stage, label}, n} <- Enum.with_index(steps(), 1)}
            aria-current={stage == @stage && "step"}
            class={[
              "inline-flex items-center gap-2 rounded-full border px-3 py-1 font-semibold",
              if(reached?(stage, @stage),
                do: "border-primary text-base-content",
                else: "border-base-300 text-base-content/60"
              )
            ]}
          >
            <span class={[
              "ta-num grid size-5 place-items-center rounded-full text-xs",
              if(reached?(stage, @stage),
                do: "bg-primary text-primary-content",
                else: "bg-base-300"
              )
            ]}>
              {n}
            </span>
            {label}
          </li>
        </ol>

        <div :if={@stage == :paste} class="grid gap-4 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          <.form for={%{}} id="import-form" phx-submit="parse" class="ta-panel flex flex-col gap-3">
            <label for="import-raw" class="text-sm font-semibold">
              {gettext("Collez les lignes depuis Excel, Word ou WhatsApp")}
            </label>
            <textarea
              id="import-raw"
              name="import[raw]"
              rows="11"
              class="textarea textarea-bordered ta-num w-full"
              placeholder="Abessolo Marc ; M ; ; 12/02/2014 ; 677 45 12 90"
            >{@raw}</textarea>
            <div class="flex flex-wrap gap-2">
              <button id="import-parse" type="submit" class="btn btn-primary btn-sm">
                {gettext("Vérifier la liste")}
              </button>
              <.link navigate={~p"/school/classes/#{@cg.id}"} class="btn btn-ghost btn-sm">
                {gettext("Annuler")}
              </.link>
            </div>
          </.form>

          <aside id="import-format" class="ta-panel flex flex-col gap-2 text-sm">
            <span class="ta-eyebrow">{gettext("Format attendu · une ligne par élève")}</span>
            <code class="ta-num rounded bg-base-200 p-2 text-xs">
              {gettext(
                "Nom et prénoms ; Sexe ; Matricule ; Date de naissance ; Téléphone du parent"
              )}
            </code>
            <p>
              {gettext(
                "Séparateur : point-virgule ou tabulation. Seuls le nom et le sexe sont obligatoires."
              )}
            </p>
            <p>
              {gettext(
                "Un matricule déjà connu de l'école réinscrit l'élève au lieu de le recréer."
              )}
            </p>
            <p>
              {gettext(
                "Le téléphone est écrit comme vous voulez (677 45 12 90, +237…) : il est lié au parent existant s'il est déjà enregistré."
              )}
            </p>
          </aside>
        </div>

        <div :if={@stage == :preview} class="flex flex-col gap-4">
          <div id="import-summary" class="flex flex-wrap gap-2 text-sm">
            <span
              :for={{id, tone, text} <- summary_chips(@preview)}
              id={"import-chip-#{id}"}
              class={["rounded-full px-3 py-1 font-semibold", tone]}
            >
              {text}
            </span>
          </div>

          <div class="overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100">
            <table id="import-preview-rows" class="table table-sm">
              <tbody>
                <tr :for={{row, action, parent} <- @preview}>
                  <td class="w-32">
                    <span class={["badge badge-sm", badge_class(action)]}>
                      {action_label(action)}
                    </span>
                  </td>
                  <td class="font-semibold">{row.full_name}</td>
                  <td class="ta-num whitespace-nowrap text-sm">{sex_and_birth(row)}</td>
                  <td class="text-sm text-base-content/80">{row_note(action, parent)}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <button
              type="button"
              id="import-confirm"
              phx-click="confirm"
              disabled={Enrollment.importable_count(@preview) == 0}
              class="btn btn-primary btn-sm"
            >
              {ngettext(
                "Confirmer l'import de %{count} élève",
                "Confirmer l'import de %{count} élèves",
                Enrollment.importable_count(@preview)
              )}
            </button>
            <button type="button" id="import-back" phx-click="back" class="btn btn-ghost btn-sm">
              {gettext("Corriger la liste")}
            </button>
            <span
              id="import-after"
              class={[
                "ta-num text-sm",
                after_capacity(@capacity, @preview).over? && "text-warning"
              ]}
            >
              {gettext("Après import : %{size}.",
                size:
                  capacity_text(
                    after_capacity(@capacity, @preview).count,
                    @capacity.max
                  )
              )}
            </span>
          </div>
        </div>

        <div :if={@stage == :done} id="import-done" class="ta-panel flex flex-col gap-3">
          <h2 class="font-display text-xl font-semibold">{done_headline(@result)}</h2>
          <p :if={@result.skipped != []} id="import-skipped" class="text-sm">
            {gettext("Ignoré :")} {Enum.map_join(@result.skipped, " ", &skipped_text/1)}
          </p>
          <p :if={@result.guardian_issues != []} id="guardian-issues" class="text-sm">
            {Enum.map_join(@result.guardian_issues, " ", &issue_text/1)}
          </p>
          <p :if={@capacity.over?} id="import-capacity" class="text-sm text-warning">
            {gettext("La classe dépasse l'effectif maximum (%{max}).", max: @capacity.max)}
          </p>
          <div class="flex flex-wrap gap-2">
            <.link navigate={~p"/school/classes/#{@cg.id}"} class="btn btn-primary btn-sm">
              {gettext("Retour à la %{class}", class: @cg.label)}
            </.link>
            <button type="button" id="import-restart" phx-click="restart" class="btn btn-ghost btn-sm">
              {gettext("Importer une autre liste")}
            </button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp steps,
    do: [paste: gettext("Coller"), preview: gettext("Vérifier"), done: gettext("Terminé")]

  defp reached?(stage, current) do
    order = [:paste, :preview, :done]
    Enum.find_index(order, &(&1 == stage)) <= Enum.find_index(order, &(&1 == current))
  end

  defp capacity_text(count, nil), do: ngettext("%{count} élève", "%{count} élèves", count)

  defp capacity_text(count, max),
    do: gettext("%{count} / %{max} élèves", count: count, max: max)

  defp after_capacity(capacity, preview),
    do: Enrollment.capacity_of(capacity.count + Enrollment.importable_count(preview), capacity.max)

  defp summary_chips(preview) do
    count = fn pred -> Enum.count(preview, pred) end

    [
      {"create", "bg-success/15 text-success", count.(&match?({_, :create, _}, &1)), :create},
      {"reenroll", "bg-info/15 text-info", count.(&match?({_, {:reenroll, _, _}, _}, &1)),
       :reenroll},
      {"conflict", "bg-warning/20 text-warning",
       count.(&match?({_, {:conflict, _, _}, _}, &1)), :conflict},
      {"error", "bg-error/15 text-error", count.(&match?({_, {:error, _}, _}, &1)), :error},
      {"invalid-phone", "bg-error/15 text-error",
       count.(fn {_, action, parent} ->
         match?({:invalid, _}, parent) and Enrollment.importable?(action)
       end), :invalid_phone}
    ]
    |> Enum.filter(fn {_id, _tone, n, _kind} -> n > 0 end)
    |> Enum.map(fn {id, tone, n, kind} -> {id, tone, chip_text(kind, n)} end)
  end

  defp chip_text(:create, n), do: ngettext("%{count} nouvel élève", "%{count} nouveaux élèves", n)

  defp chip_text(:reenroll, n),
    do: ngettext("%{count} réinscription", "%{count} réinscriptions", n)

  defp chip_text(:conflict, n),
    do: ngettext("%{count} conflit — ignoré", "%{count} conflits — ignorés", n)

  defp chip_text(:error, n),
    do: ngettext("%{count} erreur — ignorée", "%{count} erreurs — ignorées", n)

  defp chip_text(:invalid_phone, n),
    do:
      ngettext(
        "%{count} numéro de parent invalide",
        "%{count} numéros de parent invalides",
        n
      )

  defp sex_and_birth(row) do
    sex =
      case row.sex do
        :m -> gettext("G")
        :f -> gettext("F")
        nil -> "—"
      end

    case row.birth_date do
      nil -> sex
      date -> "#{sex} · #{Calendar.strftime(date, "%d/%m/%Y")}"
    end
  end

  defp badge_class(:create), do: "badge-success"
  defp badge_class({:reenroll, _, _}), do: "badge-info"
  defp badge_class({:conflict, _, _}), do: "badge-warning"
  defp badge_class({:error, _}), do: "badge-error"

  defp action_label(:create), do: gettext("Créer")
  defp action_label({:reenroll, _, _}), do: gettext("Réinscription")
  defp action_label({:conflict, _, _}), do: gettext("Conflit")
  defp action_label({:error, _}), do: gettext("Erreur")

  defp row_note({:error, :sex}, _parent), do: gettext("Sexe manquant ou inconnu (M ou F)")

  defp row_note({:conflict, :already_enrolled, label}, _parent),
    do: gettext("Déjà inscrit cette année (%{class})", class: label)

  defp row_note({:conflict, :matricule_taken, name}, _parent),
    do: gettext("Matricule déjà utilisé (%{name})", name: name)

  defp row_note({:conflict, _reason, _detail}, _parent),
    do: gettext("Vérification impossible — ignoré")

  defp row_note({:reenroll, _student, last}, parent),
    do: [last_note(last), parent_note(parent)] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

  defp row_note(:create, parent), do: parent_note(parent)

  defp last_note(nil), do: nil

  defp last_note(last),
    do:
      gettext("Était en %{class} en %{year}",
        class: last.class_group.label,
        year: last.academic_year.name
      )

  defp parent_note(nil), do: nil
  defp parent_note({:new, phone}), do: gettext("Parent : %{phone}", phone: phone)

  defp parent_note({:existing, guardian}),
    do: gettext("Parent existant lié : %{name}", name: guardian.full_name)

  defp parent_note({:invalid, phone}),
    do: gettext("Numéro « %{phone} » invalide — parent ignoré", phone: phone)

  defp done_headline(result) do
    [
      ngettext("%{count} inscription", "%{count} inscriptions", result.created),
      ngettext("%{count} réinscription", "%{count} réinscriptions", result.reenrolled)
    ]
    |> Enum.join(", ")
    |> Kernel.<>(".")
  end

  defp skipped_text(row), do: "#{row.full_name} — #{skip_reason(row.reason)}."

  defp skip_reason(:sex), do: gettext("sexe manquant ou inconnu")
  defp skip_reason(:already_enrolled), do: gettext("déjà inscrit cette année")
  defp skip_reason(:matricule_taken), do: gettext("matricule déjà utilisé")
  defp skip_reason(:duplicate_matricule), do: gettext("matricule déjà utilisé")
  defp skip_reason(:forbidden), do: gettext("action non autorisée")
  defp skip_reason(_reason), do: gettext("inscription impossible")

  defp issue_text(%{reason: :invalid_phone} = issue),
    do:
      gettext("Parent non enregistré pour %{name} (numéro « %{phone} » invalide).",
        name: issue.full_name,
        phone: issue.phone
      )

  defp issue_text(issue),
    do: gettext("Parent non enregistré pour %{name}.", name: issue.full_name)
end
