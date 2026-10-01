defmodule TeacherAssistantWeb.School.AppreciationsLive do
  @moduledoc """
  Settings → Appréciations & distinctions (spec I1): the school's appreciation scale
  (editable bands, mockup "Paramètres · Appréciations") and the distinction and
  work-warning thresholds with their two gates. The scale is edited locally and saved
  as a whole; the thresholds save as one form.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.{Appreciations, GradingRules}

  @twenty Decimal.new(20)

  # {distinction, profile field, comparison shown}
  @thresholds [
    {:felicitations, :felicitations_min, "≥"},
    {:encouragements, :encouragements_min, "≥"},
    {:tableau_honneur, :tableau_honneur_min, "≥"},
    {:avertissement_travail, :avertissement_travail_below, "<"},
    {:blame_travail, :blame_travail_below, "<"}
  ]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok,
       socket
       |> assign(thresholds: @thresholds, test: "", bands_error: nil, distinctions_error: nil)
       |> load_rules(Assessment.grading_rules(scope))}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load_rules(socket, %GradingRules{} = rules),
    do: assign(socket, rules: rules, rows: rows_from(Appreciations.bands(rules)))

  # Editor rows hold what the user edits: each row's upper bound ("À (exclu)", a
  # string; nil on the last row) and its label. A row's lower bound is the previous
  # row's upper bound (0 for the first).
  defp rows_from(bands) do
    uppers = bands |> Enum.drop(1) |> Enum.map(&show_bound(&1.from))
    Enum.zip_with(bands, uppers ++ [nil], fn band, to -> %{to: to, label: band.label} end)
  end

  defp lower_bounds(rows), do: ["0" | rows |> Enum.drop(-1) |> Enum.map(& &1.to)]

  defp band_rows(rows) do
    rows
    |> lower_bounds()
    |> Enum.zip_with(rows, fn from, row -> %{from: from || "", label: row.label} end)
  end

  defp show_bound(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp parse(text) when is_binary(text) do
    case text |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse(_), do: nil

  # The scale being edited, for the test box and the bar; nil when a bound is not a number.
  defp draft_rules(rows) do
    bands = band_rows(rows)
    froms = Enum.map(bands, &parse(&1.from))

    if Enum.all?(froms, & &1),
      do: %GradingRules{
        appreciation_bands: Enum.zip_with(froms, bands, &%{from: &1, label: &2.label})
      }
  end

  defp test_result(rows, test) do
    with %Decimal{} = mark <- parse(test),
         %GradingRules{} = rules <- draft_rules(rows) do
      Appreciations.appreciation(mark, rules).label
    else
      _ -> nil
    end
  end

  # Bar segments: {label, width share} from the draft scale.
  defp segments(rows) do
    case draft_rules(rows) do
      nil ->
        []

      rules ->
        bands = Appreciations.bands(rules)
        uppers = bands |> Enum.drop(1) |> Enum.map(& &1.from)

        Enum.zip_with(bands, uppers ++ [@twenty], fn band, upper ->
          width = upper |> Decimal.sub(band.from) |> Decimal.max(Decimal.new(0))
          {band.label, Decimal.to_float(width) / 20 * 100}
        end)
    end
  end

  defp threshold_value(rules, field) do
    case Map.fetch!(rules, field) do
      nil -> ""
      d -> show_bound(d)
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="appreciations" class="space-y-6">
        <.page_header
          eyebrow={gettext("Paramètres")}
          title={gettext("Appréciations & distinctions")}
        />

        <div class="rounded-box border border-base-300 bg-base-100 p-4 space-y-4">
          <h2 class="ta-eyebrow">{gettext("Appréciation selon la note (sur 20)")}</h2>

          <div class="flex h-8 overflow-hidden rounded-field border border-base-300">
            <div
              :for={{label, pct} <- segments(@rows)}
              class="flex items-center justify-center truncate border-r border-base-100 bg-primary/15 px-1 text-xs last:border-r-0"
              style={"width: #{pct}%"}
              title={label}
            >
              {if pct >= 10, do: label}
            </div>
          </div>

          <.form for={%{}} as={:bands} id="bands-form" phx-change="edit_bands" class="space-y-2">
            <div class="grid grid-cols-[4rem_1rem_5rem_1fr_2rem] gap-2 text-xs text-base-content/60">
              <span>{gettext("De")}</span><span></span><span>{gettext("À (exclu)")}</span>
              <span>{gettext("Appréciation")}</span><span></span>
            </div>
            <div
              :for={{{row, from}, i} <- Enum.with_index(Enum.zip(@rows, lower_bounds(@rows)))}
              class="grid grid-cols-[4rem_1rem_5rem_1fr_2rem] items-center gap-2"
            >
              <span class="ta-num text-sm">{from}</span>
              <span class="text-base-content/40">→</span>
              <.input
                :if={row.to}
                id={"band-#{i}-to"}
                name={"bands[#{i}][to]"}
                value={row.to}
                inputmode="decimal"
                class="input input-sm w-20 text-right"
              />
              <span :if={is_nil(row.to)} class="ta-num text-sm">20</span>
              <.input
                id={"band-#{i}-label"}
                name={"bands[#{i}][label]"}
                value={row.label}
                class="input input-sm w-full"
              />
              <button
                :if={length(@rows) > 1}
                id={"remove-band-#{i}"}
                type="button"
                phx-click="remove_band"
                phx-value-index={i}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Supprimer")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </.form>

          <p :if={@bands_error} id="bands-error" class="text-sm text-error">{@bands_error}</p>

          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-wrap gap-2">
              <button
                id="split-last-band"
                type="button"
                phx-click="split_last"
                class="btn btn-ghost btn-sm"
              >
                {gettext("+ Scinder la dernière tranche")}
              </button>
              <button
                id="reset-bands"
                type="button"
                phx-click="reset_bands"
                class="btn btn-ghost btn-sm"
              >
                {gettext("Rétablir le barème par défaut")}
              </button>
              <button
                id="save-bands"
                type="button"
                phx-click="save_bands"
                class="btn btn-primary btn-sm"
              >
                {gettext("Enregistrer le barème")}
              </button>
            </div>
            <.form
              for={%{}}
              id="band-test-form"
              phx-change="test_mark"
              class="flex items-center gap-2"
            >
              <span class="text-xs text-base-content/60">{gettext("Tester une note")}</span>
              <.input
                name="test"
                value={@test}
                inputmode="decimal"
                class="input input-sm w-20 text-right"
              />
              <span id="band-test-result" class="text-sm font-semibold">
                {test_result(@rows, @test) || "—"}
              </span>
            </.form>
          </div>
        </div>

        <.form
          for={%{}}
          as={:distinctions}
          id="distinctions-form"
          phx-submit="save_distinctions"
          class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3"
        >
          <h2 class="ta-eyebrow">{gettext("Distinctions et sanctions de travail")}</h2>
          <p class="text-xs text-base-content/60">
            {gettext("Seuils sur la moyenne de la période. Laisser vide pour ne pas l'attribuer.")}
          </p>
          <div :for={{kind, field, op} <- @thresholds} class="flex items-center gap-3">
            <span class="flex-1"><.distinction_badge distinction={kind} /></span>
            <span class="ta-num text-sm text-base-content/60">{op}</span>
            <.input
              name={"distinctions[#{field}]"}
              value={threshold_value(@rules, field)}
              inputmode="decimal"
              class="input input-sm w-20 text-right"
            />
          </div>
          <.input
            type="checkbox"
            name="distinctions[distinctions_require_all_passed?]"
            checked={@rules.distinctions_require_all_passed?}
            label={gettext("Distinctions seulement si toutes les matières sont ≥ 10")}
          />
          <.input
            type="checkbox"
            name="distinctions[distinctions_require_conduct?]"
            checked={@rules.distinctions_require_conduct?}
            label={gettext("Distinctions soumises à une conduite ≥ 12")}
          />
          <p :if={@distinctions_error} id="distinctions-error" class="text-sm text-error">
            {@distinctions_error}
          </p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("edit_bands", %{"bands" => params}, socket) do
    rows =
      socket.assigns.rows
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        p = Map.get(params, Integer.to_string(i), %{})

        %{
          to: if(row.to, do: Map.get(p, "to", row.to), else: nil),
          label: Map.get(p, "label", row.label)
        }
      end)

    {:noreply, assign(socket, rows: rows, bands_error: nil)}
  end

  def handle_event("edit_bands", _params, socket), do: {:noreply, socket}

  def handle_event("remove_band", %{"index" => index}, socket) do
    rows = socket.assigns.rows

    rows =
      case Integer.parse(index) do
        {i, ""} when length(rows) > 1 and i >= 0 and i < length(rows) ->
          rows |> List.delete_at(i) |> close_last()

        _ ->
          rows
      end

    {:noreply, assign(socket, rows: rows, bands_error: nil)}
  end

  def handle_event("split_last", _params, socket) do
    rows = socket.assigns.rows

    case rows |> lower_bounds() |> List.last() |> parse() do
      %Decimal{} = from ->
        mid = from |> Decimal.add(@twenty) |> Decimal.div(2) |> Decimal.round(2)
        {last, rest} = List.pop_at(rows, -1)

        new_rows =
          rest ++ [%{last | to: show_bound(mid)}, %{to: nil, label: gettext("Nouvelle tranche")}]

        {:noreply, assign(socket, rows: new_rows, bands_error: nil)}

      nil ->
        {:noreply, assign(socket, bands_error: gettext("Corrigez d'abord les bornes."))}
    end
  end

  def handle_event("test_mark", %{"test" => test}, socket),
    do: {:noreply, assign(socket, test: test)}

  def handle_event("save_bands", _params, socket) do
    scope = socket.assigns.current_scope

    socket.assigns.rows
    |> band_rows()
    |> then(&Assessment.update_appreciation_bands(scope, &1))
    |> after_save(socket, :bands_error, gettext("Barème enregistré."))
  end

  def handle_event("reset_bands", _params, socket) do
    socket.assigns.current_scope
    |> Assessment.reset_appreciation_bands()
    |> after_save(socket, :bands_error, gettext("Barème par défaut rétabli."))
  end

  def handle_event("save_distinctions", %{"distinctions" => params}, socket) do
    socket.assigns.current_scope
    |> Assessment.update_distinction_rules(params)
    |> after_save(socket, :distinctions_error, gettext("Réglage enregistré."))
  end

  defp after_save({:ok, _profile}, socket, error_key, message) do
    rules = Assessment.grading_rules(socket.assigns.current_scope)

    {:noreply,
     socket
     |> load_rules(rules)
     |> assign(error_key, nil)
     |> put_flash(:info, message)}
  end

  defp after_save({:error, %Ash.Error.Forbidden{}}, socket, _key, _message),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_save({:error, :invalid_number}, socket, key, _message),
    do: {:noreply, assign(socket, key, gettext("Utilisez des nombres, par exemple 9,5."))}

  defp after_save({:error, %Ash.Error.Invalid{errors: errors}}, socket, key, _message) do
    message = Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
    {:noreply, assign(socket, key, message)}
  end

  defp after_save({:error, _other}, socket, key, _message),
    do: {:noreply, assign(socket, key, gettext("Réglage non enregistré."))}

  defp close_last(rows) do
    {last, rest} = List.pop_at(rows, -1)
    rest ++ [%{last | to: nil}]
  end
end
