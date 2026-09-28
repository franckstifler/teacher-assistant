defmodule TeacherAssistantWeb.School.CoefficientsLive do
  @moduledoc """
  Settings → Matières & coefficients: the coefficient grid (subject × level, per série
  for streamed 2nd-cycle levels), bulletin groups, and the two related school settings.
  An empty cell means "not taught at this level"; in a série view an empty cell
  inherits the blank-série value (shown as placeholder).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Curriculum}
  alias TeacherAssistant.Academics.{BulletinGroup, CoefficientRules}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Curriculum.can_manage_subjects?(scope) do
      [first | _] = layout = Curriculum.coefficient_grid_layout(scope)

      {:ok,
       socket
       |> assign(
         grid_views: layout,
         subsystem: first.subsystem,
         serie: nil,
         errors: %{},
         submitted: %{}
       )
       |> load_grid()}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    assigns = assign(assigns, :columns, columns(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="coefficients" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Matières & coefficients")} />
        <p class="text-sm text-base-content/70">
          {gettext(
            "Case vide : matière non enseignée à ce niveau. Bordure ambre : une classe a un coefficient propre."
          )}
        </p>

        <div class="flex flex-wrap items-center gap-2">
          <%= for view <- @grid_views do %>
            <button
              :for={serie <- [nil | view.series]}
              id={"grid-view-#{view.subsystem}-#{serie || "all"}"}
              type="button"
              phx-click="select_view"
              phx-value-subsystem={view.subsystem}
              phx-value-serie={serie || ""}
              class={[
                "btn btn-sm",
                if(view.subsystem == @subsystem and serie == @serie,
                  do: "btn-primary",
                  else: "btn-ghost"
                )
              ]}
            >
              {view_label(view.subsystem, serie, length(@grid_views) > 1)}
            </button>
          <% end %>
        </div>

        <.form
          for={%{}}
          as={:grid}
          id="coefficient-grid-form"
          phx-submit="save_grid"
          class="space-y-3"
        >
          <div class="overflow-x-auto rounded-box border border-base-300">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Matière")}</th>
                  <th>{gettext("Groupe")}</th>
                  <th :for={col <- @columns} class="text-center">{col.level}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={s <- @subjects} id={"grid-row-#{s.id}"} class="align-top">
                  <td class="whitespace-nowrap font-medium">{s.name}</td>
                  <td>
                    <.input
                      type="select"
                      name={"grid[groups][#{s.id}]"}
                      value={to_string(s.bulletin_group)}
                      options={
                        for g <- BulletinGroup.values(), do: {BulletinGroup.short(g), to_string(g)}
                      }
                      errors={error_texts(@errors, {:group, s.id})}
                    />
                  </td>
                  <td :for={col <- @columns} class="min-w-20">
                    <.input
                      type="text"
                      inputmode="decimal"
                      name={"grid[cells][#{s.id}][#{Curriculum.cell_token(col.key)}]"}
                      value={cell_value(@submitted, @cells, s.id, col.key)}
                      placeholder={col.inherits? && fmt(@cells[put_elem(key(s.id, col.key), 3, nil)])}
                      class={cell_class(MapSet.member?(@overridden, key(s.id, col.key)))}
                      errors={error_texts(@errors, key(s.id, col.key))}
                    />
                  </td>
                </tr>
              </tbody>
              <tfoot>
                <tr>
                  <th colspan="2">{gettext("Total des coefficients")}</th>
                  <th :for={col <- @columns} class="ta-num text-center">
                    {fmt(column_total(@subjects, @cells, col))}
                  </th>
                </tr>
              </tfoot>
            </table>
          </div>
          <button type="submit" class="btn btn-primary btn-sm">{gettext(
            "Enregistrer les coefficients"
          )}</button>
        </.form>

        <div class="rounded-box border border-base-300 bg-base-100 divide-y divide-base-300">
          <div class="flex items-center justify-between gap-4 p-4">
            <div>
              <p class="font-medium">{gettext("Autoriser un coefficient propre à une classe")}</p>
              <p class="text-xs text-base-content/60">
                {gettext("Modifiable depuis la page de la classe.")}
              </p>
            </div>
            <input
              id="toggle-class-coefficients"
              type="checkbox"
              class="toggle toggle-primary"
              checked={@profile.class_coefficients_allowed?}
              phx-click="toggle_class_coefficients"
            />
          </div>
          <div class="flex items-center justify-between gap-4 p-4">
            <p class="font-medium">{gettext("Sous-totaux par groupe sur le bulletin")}</p>
            <input
              id="toggle-group-subtotals"
              type="checkbox"
              class="toggle toggle-primary"
              checked={@profile.bulletin_group_subtotals?}
              phx-click="toggle_group_subtotals"
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("select_view", %{"subsystem" => sub, "serie" => serie}, socket) do
    view = Enum.find(socket.assigns.grid_views, &(Atom.to_string(&1.subsystem) == sub))

    if view && (serie == "" or serie in view.series) do
      {:noreply,
       assign(socket,
         subsystem: view.subsystem,
         serie: if(serie == "", do: nil, else: serie),
         errors: %{},
         submitted: %{}
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_grid", %{"grid" => params}, socket) do
    case Curriculum.update_coefficient_grid(socket.assigns.current_scope, params) do
      :ok ->
        {:noreply,
         socket
         |> assign(errors: %{}, submitted: %{})
         |> load_grid()
         |> put_flash(:info, gettext("Coefficients enregistrés."))}

      {:error, {:invalid, errors}} ->
        {:noreply,
         socket
         |> assign(errors: errors, submitted: Map.get(params, "cells", %{}))
         |> put_flash(
           :error,
           gettext("Coefficients non enregistrés : corrigez les cases signalées.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Coefficients non enregistrés."))}
    end
  end

  def handle_event("save_grid", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_class_coefficients", _params, socket) do
    allowed? = !socket.assigns.profile.class_coefficients_allowed?

    case Curriculum.set_class_coefficients_allowed(socket.assigns.current_scope, allowed?) do
      {:ok, _} ->
        {:noreply, load_grid(socket)}

      {:error, {:overrides_exist, labels}} ->
        {:noreply,
         socket
         |> load_grid()
         |> put_flash(
           :error,
           gettext(
             "%{count} classes ont un coefficient propre : réinitialisez-les d'abord (%{classes}).",
             count: length(labels),
             classes: Enum.join(labels, ", ")
           )
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  def handle_event("toggle_group_subtotals", _params, socket) do
    on? = !socket.assigns.profile.bulletin_group_subtotals?

    case Curriculum.set_bulletin_group_subtotals(socket.assigns.current_scope, on?) do
      {:ok, _} -> {:noreply, load_grid(socket)}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  defp load_grid(socket) do
    scope = socket.assigns.current_scope
    cells = Map.new(Curriculum.coefficient_cells(scope), fn {k, c} -> {k, c.coefficient} end)
    {:ok, profile} = Accounts.fetch_school_profile(scope)

    overridden =
      for a <- Curriculum.grid_assignments(scope),
          a.override?,
          key = CoefficientRules.resolve(cells, a),
          key != nil,
          into: MapSet.new(),
          do: key

    subjects =
      scope
      |> Curriculum.list_subjects()
      |> Enum.filter(& &1.active?)
      |> Enum.sort_by(&{BulletinGroup.rank(&1.bulletin_group), &1.position, &1.name})

    assign(socket, cells: cells, overridden: overridden, subjects: subjects, profile: profile)
  end

  # Columns of the current view: every level of the subsystem; streamed levels use
  # the selected série (inheriting the blank-série value), others the blank série.
  defp columns(%{grid_views: layout, subsystem: subsystem, serie: serie}) do
    view = Enum.find(layout, &(&1.subsystem == subsystem))

    for %{level: level, streamed?: streamed?} <- view.levels do
      col_serie = if streamed?, do: serie, else: nil
      %{level: level, key: {subsystem, level, col_serie}, inherits?: col_serie != nil}
    end
  end

  defp key(subject_id, {subsystem, level, serie}), do: {subject_id, subsystem, level, serie}

  defp cell_value(submitted, cells, subject_id, col_key) do
    case get_in(submitted, [subject_id, Curriculum.cell_token(col_key)]) do
      nil -> fmt(cells[key(subject_id, col_key)])
      value -> value
    end
  end

  defp column_total(subjects, cells, col) do
    subjects
    |> Enum.map(fn s ->
      cells[key(s.id, col.key)] || (col.inherits? && cells[put_elem(key(s.id, col.key), 3, nil)]) ||
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp error_texts(errors, key), do: Enum.map(Map.get(errors, key, []), &error_text/1)

  defp error_text(:invalid_coefficient), do: gettext("Coefficient invalide.")
  defp error_text(:invalid_group), do: gettext("Groupe invalide.")

  defp error_text({:in_use, labels}),
    do: gettext("Utilisée par : %{classes}", classes: Enum.join(labels, ", "))

  defp view_label(subsystem, nil, true),
    do: "#{TeacherAssistant.Academics.Subsystem.label(subsystem)} · #{gettext("Toutes séries")}"

  defp view_label(_subsystem, nil, false), do: gettext("Toutes séries")
  defp view_label(_subsystem, serie, _), do: gettext("Série %{serie}", serie: serie)

  defp fmt(nil), do: nil
  defp fmt(false), do: nil
  defp fmt(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)

  # `<.input>` takes a string class, which replaces its default classes entirely.
  defp cell_class(true), do: "input input-sm w-16 text-center border-warning"
  defp cell_class(false), do: "input input-sm w-16 text-center"
end
