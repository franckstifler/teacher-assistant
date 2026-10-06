defmodule TeacherAssistantWeb.School.NewYearLive do
  @moduledoc """
  Spec KLM9 (rule 11): « Préparer l'année suivante », four steps — checks, the new year,
  the classes (label, admis target, projected size), the confirmation — then
  `NewYear.start/3`. The plan lives in the LiveView; nothing is saved before the start.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, NewYear, Organization}
  alias TeacherAssistant.Academics.NewYearPlan
  alias TeacherAssistantWeb.Dates

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    cond do
      not Organization.can_manage_calendar?(scope) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           gettext("La préparation de l'année est réservée au Proviseur et au Censeur.")
         )
         |> push_navigate(to: ~p"/school")}

      year == nil or year.status == :closed ->
        {:ok, push_navigate(socket, to: ~p"/school/settings")}

      true ->
        plan = NewYear.plan(scope, year)

        max =
          case Accounts.fetch_school_profile(scope) do
            {:ok, profile} -> profile.max_class_size
            _ -> nil
          end

        {:ok,
         socket
         |> assign(
           year: year,
           plan: plan,
           max: max,
           step: 1,
           taken_names: scope |> Organization.list_academic_years() |> MapSet.new(& &1.name),
           year_params: %{
             "name" => NewYearPlan.next_name(year.name),
             "start_date" => year.start_date |> Date.shift(year: 1) |> Date.to_iso8601(),
             "end_date" => year.end_date |> Date.shift(year: 1) |> Date.to_iso8601()
           },
           year_attrs: nil,
           year_error: nil,
           labels: Map.new(plan.classes, &{&1.id, &1.label}),
           targets: plan.default_targets,
           classes_error: nil
         )
         |> derive()}
    end
  end

  def handle_event("checked", _params, %{assigns: %{step: 1}} = socket),
    do: {:noreply, assign(socket, step: 2)}

  # Back to an earlier step only.
  def handle_event("back", %{"step" => step}, socket) do
    case Integer.parse(step) do
      {n, ""} when n >= 1 and n < socket.assigns.step -> {:noreply, assign(socket, step: n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_year", %{"year" => params}, %{assigns: %{step: 2}} = socket) do
    case parse_year(params, socket.assigns.taken_names) do
      {:ok, attrs} ->
        {:noreply,
         socket
         |> assign(year_params: params, year_attrs: attrs, year_error: nil, step: 3)
         |> derive()}

      {:error, message} ->
        {:noreply, socket |> assign(year_params: params, year_error: message) |> derive()}
    end
  end

  def handle_event("change_classes", params, %{assigns: %{step: 3}} = socket),
    do: {:noreply, socket |> put_classes(params) |> derive()}

  def handle_event("save_classes", params, %{assigns: %{step: 3}} = socket) do
    socket = put_classes(socket, params)

    case labels_error(socket.assigns.labels) do
      nil -> {:noreply, socket |> assign(classes_error: nil, step: 4) |> derive()}
      message -> {:noreply, socket |> assign(classes_error: message) |> derive()}
    end
  end

  def handle_event("start", _params, %{assigns: %{step: 4}} = socket) do
    %{current_scope: scope, year: year, year_attrs: attrs, labels: labels, targets: targets} =
      socket.assigns

    case NewYear.start(scope, year, Map.merge(attrs, %{labels: labels, targets: targets})) do
      {:ok, new} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("L'année %{name} a démarré.", name: new.name))
         |> push_navigate(to: ~p"/school/classes")}

      {:error, :already_closed} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("L'année %{name} est déjà clôturée.", name: year.name))
         |> push_navigate(to: ~p"/school/settings")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("L'année suivante n'a pas pu démarrer ; rien n'a été modifié.")
         )}
    end
  end

  # Events of another step (a stale or forged click) do nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp parse_year(params, taken) do
    name = params |> Map.get("name", "") |> String.trim()

    with {:name, false} <- {:name, name == ""},
         {:taken, false} <- {:taken, MapSet.member?(taken, name)},
         {:ok, start} <- Date.from_iso8601(Map.get(params, "start_date", "")),
         {:ok, finish} <- Date.from_iso8601(Map.get(params, "end_date", "")),
         :gt <- Date.compare(finish, start) do
      {:ok, %{name: name, start_date: start, end_date: finish}}
    else
      {:name, true} -> {:error, gettext("Donnez un nom à la nouvelle année.")}
      {:taken, true} -> {:error, gettext("Une année porte déjà ce nom.")}
      order when order in [:lt, :eq] -> {:error, gettext("La fin doit suivre le début.")}
      _ -> {:error, gettext("Dates invalides.")}
    end
  end

  defp put_classes(socket, params) do
    ids = MapSet.new(socket.assigns.plan.classes, & &1.id)

    labels =
      for {id, label} <- Map.get(params, "labels", %{}),
          MapSet.member?(ids, id),
          into: socket.assigns.labels,
          do: {id, label}

    targets =
      for {id, target} <- Map.get(params, "targets", %{}),
          MapSet.member?(ids, id),
          into: socket.assigns.targets,
          do: {id, if(MapSet.member?(ids, target), do: target)}

    assign(socket, labels: labels, targets: targets)
  end

  defp labels_error(labels) do
    names = labels |> Map.values() |> Enum.map(&String.trim/1)

    cond do
      Enum.any?(names, &(&1 == "")) ->
        gettext("Chaque classe doit avoir un nom.")

      length(Enum.uniq_by(names, &String.downcase/1)) != length(names) ->
        gettext("Deux classes portent le même nom.")

      true ->
        nil
    end
  end

  defp derive(socket) do
    placements = NewYearPlan.placements(socket.assigns.plan.students, socket.assigns.targets)

    assign(socket,
      sizes: NewYearPlan.sizes(placements),
      totals: NewYearPlan.totals(placements),
      year_form: to_form(socket.assigns.year_params, as: :year)
    )
  end

  defp steps do
    [
      {1, gettext("Vérification")},
      {2, gettext("Nouvelle année")},
      {3, gettext("Classes")},
      {4, gettext("Confirmation")}
    ]
  end

  defp target_options(classes, labels),
    do: [{gettext("Ne pas réinscrire"), ""} | Enum.map(classes, &{labels[&1.id], &1.id})]

  defp over?(size, max), do: is_integer(max) and size > max

  defp size_text(size, nil), do: to_string(size)
  defp size_text(size, max), do: "#{size} / #{max}"

  defp reason_label(:exclu), do: gettext("Exclus")
  defp reason_label(:sans_decision), do: gettext("Sans décision")
  defp reason_label(:sans_classe), do: gettext("Admis sans classe d'accueil")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="new-year" class="mx-auto flex w-full max-w-3xl flex-col gap-5">
        <.page_header
          eyebrow={gettext("Paramètres · Année")}
          title={gettext("Préparer l'année suivante")}
          subtitle={gettext("À partir de %{name}", name: @year.name)}
        />

        <ol id="new-year-steps" class="flex flex-wrap gap-2 text-xs font-semibold">
          <li
            :for={{n, label} <- steps()}
            aria-current={n == @step && "step"}
            class={[
              "rounded-full border px-3 py-1 transition-colors",
              cond do
                n == @step -> "border-primary bg-primary/15 text-primary"
                n < @step -> "border-base-300 text-base-content/80"
                true -> "border-base-300 text-base-content/40"
              end
            ]}
          >
            <span class="ta-num">{n}</span> · {label}
          </li>
        </ol>

        <div :if={@step == 1} id="step-checks" class="ta-panel flex flex-col gap-3">
          <h2 class="ta-eyebrow">{gettext("Vérification")}</h2>
          <p :if={@plan.checks.before_end?} id="check-before-end" class="alert alert-warning text-sm">
            {gettext("L'année %{name} se termine le %{date} : vous la clôturez en avance.",
              name: @year.name,
              date: Dates.short(@year.end_date)
            )}
          </p>
          <p id="check-councils" class="text-sm">
            <%= if @plan.checks.open_councils == [] do %>
              {gettext("Tous les conseils de fin d'année sont clos.")}
            <% else %>
              {gettext("Conseil de fin d'année non clos : %{classes}",
                classes: Enum.map_join(@plan.checks.open_councils, ", ", & &1.label)
              )}
            <% end %>
          </p>
          <div :if={@plan.checks.proposals != %{}} id="check-proposals" class="text-sm">
            <p>{gettext("Décisions non confirmées par le conseil (la proposition sera suivie) :")}</p>
            <ul class="mt-1 list-inside list-disc text-base-content/80">
              <li :for={cg <- @plan.classes} :if={@plan.checks.proposals[cg.id]}>
                {cg.label} · <span class="ta-num">{@plan.checks.proposals[cg.id]}</span>
              </li>
            </ul>
          </div>
          <p :if={@plan.checks.departed_courses > 0} id="check-departed" class="text-sm">
            {ngettext(
              "%{count} cours est attribué à un enseignant parti : à réattribuer dans Affectations.",
              "%{count} cours sont attribués à des enseignants partis : à réattribuer dans Affectations.",
              @plan.checks.departed_courses
            )}
          </p>
          <button
            id="to-step-2"
            type="button"
            phx-click="checked"
            class="btn btn-primary btn-sm self-end"
          >
            {gettext("Continuer")}
          </button>
        </div>

        <.form
          :if={@step == 2}
          for={@year_form}
          id="new-year-form"
          phx-submit="save_year"
          class="ta-panel flex flex-col gap-3"
        >
          <h2 class="ta-eyebrow">{gettext("Nouvelle année")}</h2>
          <div class="grid gap-3 sm:grid-cols-3">
            <.input field={@year_form[:name]} label={gettext("Nom")} />
            <.input field={@year_form[:start_date]} type="date" label={gettext("Début")} />
            <.input field={@year_form[:end_date]} type="date" label={gettext("Fin")} />
          </div>
          <p :if={@year_error} id="year-error" class="text-sm text-error">{@year_error}</p>
          <div class="flex justify-between gap-2">
            <button type="button" phx-click="back" phx-value-step="1" class="btn btn-ghost btn-sm">
              {gettext("Retour")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Continuer")}</button>
          </div>
        </.form>

        <form
          :if={@step == 3}
          id="classes-form"
          phx-change="change_classes"
          phx-submit="save_classes"
          class="ta-panel flex flex-col gap-2"
        >
          <h2 class="ta-eyebrow">{gettext("Classes de %{name}", name: @year_attrs.name)}</h2>
          <div
            :for={cg <- @plan.classes}
            id={"class-row-#{cg.id}"}
            class="grid items-end gap-2 border-t border-base-300 pt-2 sm:grid-cols-[1fr_1fr_5rem]"
          >
            <.input name={"labels[#{cg.id}]"} value={@labels[cg.id]} label={cg.label} />
            <.input
              type="select"
              name={"targets[#{cg.id}]"}
              value={@targets[cg.id] || ""}
              label={gettext("Admis vers")}
              options={target_options(@plan.classes, @labels)}
            />
            <span
              id={"class-size-#{cg.id}"}
              title={gettext("Effectif prévu")}
              class={[
                "ta-num pb-3 text-right text-sm",
                over?(@sizes[cg.id] || 0, @max) && "font-semibold text-warning"
              ]}
            >
              {size_text(@sizes[cg.id] || 0, @max)}
            </span>
          </div>
          <p :if={@classes_error} id="classes-error" class="text-sm text-error">{@classes_error}</p>
          <div class="flex justify-between gap-2 pt-2">
            <button type="button" phx-click="back" phx-value-step="2" class="btn btn-ghost btn-sm">
              {gettext("Retour")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Continuer")}</button>
          </div>
        </form>

        <div :if={@step == 4} id="step-summary" class="ta-panel flex flex-col gap-4">
          <h2 class="ta-eyebrow">{gettext("Confirmation")}</h2>
          <dl class="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            <div>
              <dt class="ta-eyebrow">{gettext("Classes")}</dt>
              <dd class="ta-num text-xl font-semibold">{length(@plan.classes)}</dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("Réinscrits")}</dt>
              <dd id="summary-reenrolled" class="ta-num text-xl font-semibold">
                {@totals.reenrolled}
              </dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("dont redoublants")}</dt>
              <dd id="summary-repeaters" class="ta-num text-xl font-semibold">{@totals.repeaters}</dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("Non réinscrits")}</dt>
              <dd id="summary-not" class="ta-num text-xl font-semibold">
                {@totals.not_reenrolled |> Map.values() |> Enum.sum()}
              </dd>
            </div>
          </dl>
          <ul :if={@totals.not_reenrolled != %{}} class="text-sm text-base-content/80">
            <li :for={{reason, n} <- @totals.not_reenrolled}>
              {reason_label(reason)} · <span class="ta-num">{n}</span>
            </li>
          </ul>
          <p class="text-sm text-base-content/70">
            {gettext("L'année %{old} sera clôturée : plus aucune modification n'y sera possible.",
              old: @year.name
            )}
          </p>
          <div class="flex justify-between gap-2">
            <button type="button" phx-click="back" phx-value-step="3" class="btn btn-ghost btn-sm">
              {gettext("Retour")}
            </button>
            <button
              id="start-year"
              type="button"
              phx-click="start"
              phx-disable-with={gettext("Démarrage…")}
              class="btn btn-primary btn-sm"
            >
              {gettext("Démarrer l'année %{name}", name: @year_attrs.name)}
            </button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
