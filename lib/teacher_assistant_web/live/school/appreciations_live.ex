defmodule TeacherAssistantWeb.School.AppreciationsLive do
  @moduledoc """
  Settings → Appréciations & distinctions (spec I1): the school's appreciation scale
  (editable bands, mockup "Paramètres · Appréciations") and the distinction and
  work-warning thresholds with their two gates. The scale is edited locally and saved
  as a whole; the thresholds save as one form. Edits wait in the page until the
  sticky bar's "Enregistrer" (or "Annuler").
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
       |> assign(
         page_title: gettext("Appréciations & distinctions"),
         thresholds: @thresholds,
         test: "13,5",
         bands_error: nil,
         distinctions_error: nil
       )
       |> load_rules(Assessment.grading_rules(scope))}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load_rules(socket, %GradingRules{} = rules) do
    assign(socket,
      rules: rules,
      rows: rows_from(Appreciations.bands(rules)),
      dist: dist_from(rules),
      bands_dirty?: false,
      dist_dirty?: false
    )
  end

  # The thresholds and gates as the form shows them (strings / booleans).
  defp dist_from(rules) do
    @thresholds
    |> Map.new(fn {_kind, field, _op} ->
      {Atom.to_string(field), threshold_value(rules, field)}
    end)
    |> Map.merge(%{
      "distinctions_require_all_passed?" => rules.distinctions_require_all_passed?,
      "distinctions_require_conduct?" => rules.distinctions_require_conduct?
    })
  end

  # Editor rows hold what the user edits: each row's upper bound ("À (exclu)", a
  # string; nil on the last row) and its label. A row's lower bound is the previous
  # row's upper bound (0 for the first).
  defp rows_from(bands) do
    uppers = bands |> Enum.drop(1) |> Enum.map(&show_bound(&1.from))

    Enum.zip_with(bands, uppers ++ [nil], fn band, to ->
      %{to: to, label: band.label, code: band.code}
    end)
  end

  defp lower_bounds(rows), do: ["0" | rows |> Enum.drop(-1) |> Enum.map(& &1.to)]

  defp band_rows(rows) do
    rows
    |> lower_bounds()
    |> Enum.zip_with(rows, fn from, row ->
      %{from: from || "", label: row.label, code: row.code}
    end)
  end

  defp show_bound(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp parse(text) when is_binary(text) do
    case text |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      # NaN and ±Infinity carry an atom coefficient.
      {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> d
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
          # Clamped to 0..20 so an out-of-range draft bound never overflows to_float.
          width =
            upper |> Decimal.sub(band.from) |> Decimal.max(Decimal.new(0)) |> Decimal.min(@twenty)

          {band.label, Decimal.to_float(width) / 20 * 100}
        end)
        |> Enum.with_index(fn {label, pct}, i -> {label, pct, band_color(i, length(bands))} end)
    end
  end

  # Red to green along the scale, as in the mockup.
  defp band_color(i, n) do
    hue = if n > 1, do: round(30 + (162 - 30) * i / (n - 1)), else: 162
    "oklch(70% 0.12 #{hue})"
  end

  # The colour of the band the test mark falls in, for the result pill.
  defp test_color(rows, test) do
    with %Decimal{} = mark <- parse(test),
         %GradingRules{} = rules <- draft_rules(rows) do
      bands = Appreciations.bands(rules)
      i = Enum.find_index(bands, &(&1.label == Appreciations.appreciation(mark, rules).label))
      i && band_color(i, length(bands))
    else
      _ -> nil
    end
  end

  # A row's upper bound is wrong when it is not a number, not above the lower one, or ≥ 20.
  defp bad_bound?(from, to) do
    with %Decimal{} = lo <- parse(from), %Decimal{} = hi <- parse(to) do
      Decimal.compare(hi, lo) != :gt or Decimal.compare(hi, @twenty) != :lt
    else
      _ -> true
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
      <section id="appreciations" class="flex flex-col gap-4 pb-4">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Appréciations & distinctions")}
          subtitle={
            gettext(
              "Appréciation automatique selon la note, et seuils des distinctions et sanctions de travail."
            )
          }
        />

        <div class="ta-panel flex flex-col gap-3 !px-[18px] !py-4">
          <h2 class="ta-eyebrow">{gettext("Appréciation selon la note (sur 20)")}</h2>

          <div
            id="band-bar"
            class="flex h-[30px] overflow-hidden rounded-[0.4rem] border border-base-300"
          >
            <div
              :for={{label, pct, color} <- segments(@rows)}
              class="ta-num grid place-items-center overflow-hidden whitespace-nowrap border-r border-base-200 text-[0.62rem] font-semibold text-[oklch(20%_0.03_164)] last:border-r-0"
              style={"width: #{pct}%; background: #{color}"}
              title={label}
            >
              {if pct >= 10, do: label}
            </div>
          </div>

          <.form for={%{}} as={:bands} id="bands-form" phx-change="edit_bands" class="flex flex-col">
            <div class={[
              band_grid(),
              "ta-text-2 py-1 text-xs font-medium"
            ]}>
              <span>{gettext("De")}</span><span></span><span>{gettext("À (exclu)")}</span>
              <span>{gettext("Cote")}</span><span>{gettext("Appréciation")}</span><span></span>
            </div>
            <div
              :for={{{row, from}, i} <- Enum.with_index(Enum.zip(@rows, lower_bounds(@rows)))}
              class={[band_grid(), "ta-row-rule items-center py-1"]}
            >
              <span class="ta-num text-[0.88rem] font-semibold">{from}</span>
              <i class="size-3 rounded-[3px]" style={"background: #{band_color(i, length(@rows))}"}></i>
              <input
                :if={row.to}
                id={"band-#{i}-to"}
                name={"bands[#{i}][to]"}
                value={row.to}
                inputmode="decimal"
                class={[
                  "input input-sm ta-num h-[34px] w-[90px] text-right",
                  bad_bound?(from, row.to) && "!border-error"
                ]}
              />
              <input
                :if={is_nil(row.to)}
                value="20"
                disabled
                aria-label={gettext("À (exclu)")}
                class="input input-sm ta-num h-[34px] w-[90px] text-right"
              />
              <input
                id={"band-#{i}-code"}
                name={"bands[#{i}][code]"}
                value={row.code}
                maxlength="8"
                aria-label={gettext("Cote")}
                placeholder="—"
                class="input input-sm h-[34px] w-full min-w-0 uppercase"
              />
              <input
                id={"band-#{i}-label"}
                name={"bands[#{i}][label]"}
                value={row.label}
                class="input input-sm h-[34px] w-full min-w-0"
              />
              <button
                :if={length(@rows) > 1}
                id={"remove-band-#{i}"}
                type="button"
                phx-click="remove_band"
                phx-value-index={i}
                class="grid size-10 cursor-pointer place-items-center rounded-[0.4rem] border border-base-300 text-base-content/75 transition-colors hover:border-error hover:text-error"
                title={gettext("Supprimer")}
                aria-label={gettext("Supprimer")}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </.form>

          <p :if={@bands_error} id="bands-error" class="text-sm text-error">{@bands_error}</p>

          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-wrap items-center gap-2">
              <button
                id="split-last-band"
                type="button"
                phx-click="split_last"
                class="h-9 cursor-pointer rounded-[0.4rem] border border-primary px-3.5 text-[0.8rem] font-semibold text-primary transition-colors hover:bg-primary/10"
              >
                {gettext("+ Scinder la dernière tranche")}
              </button>
              <button
                id="apc-preset"
                type="button"
                phx-click="apc_preset"
                class="h-9 cursor-pointer rounded-[0.4rem] border border-base-300 px-3.5 text-[0.8rem] font-semibold transition-colors hover:border-primary hover:text-primary"
              >
                {gettext("Barème APC (CTBA → CNA)")}
              </button>
              <button
                id="reset-bands"
                type="button"
                phx-click="reset_bands"
                data-confirm={gettext("Remplacer votre barème par le barème par défaut ?")}
                class="h-9 cursor-pointer px-2 text-[0.8rem] text-base-content/70 underline-offset-2 hover:underline"
              >
                {gettext("Rétablir le barème par défaut")}
              </button>
            </div>
            <.form
              for={%{}}
              id="band-test-form"
              phx-change="test_mark"
              class="flex items-center gap-2 text-[0.85rem]"
            >
              <span class="text-base-content/80">{gettext("Tester une note")}</span>
              <input
                name="test"
                value={@test}
                inputmode="decimal"
                aria-label={gettext("Tester une note")}
                class="input input-sm ta-num h-[34px] w-20 text-right"
              />
              <span
                id="band-test-result"
                class={[
                  "rounded-full px-2.5 py-[5px] font-semibold",
                  if(test_color(@rows, @test),
                    do: "text-[oklch(20%_0.03_164)]",
                    else: "text-base-content/70"
                  )
                ]}
                style={test_color(@rows, @test) && "background: #{test_color(@rows, @test)}"}
              >
                {test_result(@rows, @test) || "—"}
              </span>
            </.form>
          </div>
        </div>

        <.form
          for={%{}}
          as={:distinctions}
          id="distinctions-form"
          phx-change="edit_distinctions"
          phx-submit="save_distinctions"
          class="flex flex-col gap-4"
        >
          <div class="ta-panel flex flex-col gap-1.5 !px-[18px] !py-4">
            <h2 class="ta-eyebrow">
              {gettext("Distinctions et sanctions de travail (moyenne trimestrielle)")}
            </h2>
            <p class="text-[0.78rem] text-base-content/70">
              {gettext("Laisser vide pour ne pas l'attribuer.")}
            </p>
            <div
              :for={{kind, field, op} <- @thresholds}
              class="ta-row-rule flex items-center gap-2.5 py-1.5"
            >
              <span class={["flex-1 text-[0.9rem] font-semibold", distinction_tone(kind)]}>
                {TeacherAssistant.Academics.Distinction.label(kind)}
              </span>
              <span class="ta-num text-[0.9rem] text-base-content/80">{op}</span>
              <input
                name={"distinctions[#{field}]"}
                value={@dist[Atom.to_string(field)]}
                inputmode="decimal"
                aria-label={TeacherAssistant.Academics.Distinction.label(kind)}
                class="input input-sm ta-num h-[34px] w-[74px] text-right"
              />
            </div>
          </div>

          <div class="ta-panel flex flex-col !px-[18px] !py-2">
            <.gate
              name="distinctions_require_all_passed?"
              on={@dist["distinctions_require_all_passed?"]}
              label={gettext("Distinctions seulement si toutes les matières sont ≥ 10")}
            />
            <.gate
              name="distinctions_require_conduct?"
              on={@dist["distinctions_require_conduct?"]}
              label={gettext("Distinctions soumises à une conduite ≥ 12")}
            />
          </div>

          <p :if={@distinctions_error} id="distinctions-error" class="text-sm text-error">
            {@distinctions_error}
          </p>
        </.form>
      </section>

      <div
        :if={@bands_dirty? or @dist_dirty?}
        id="unsaved-bar"
        class="ta-stickyfoot sticky bottom-0 z-10 -mx-4 flex flex-wrap items-center justify-between gap-3 border-t border-base-300 bg-[color-mix(in_oklch,var(--color-base-200)_85%,black)] px-7 py-3 sm:-mx-6"
      >
        <span class="text-[0.88rem] text-warning">{gettext("Modifications non enregistrées")}</span>
        <div class="flex gap-2">
          <button
            id="discard-settings"
            type="button"
            phx-click="discard"
            class="h-10 cursor-pointer rounded-[0.4rem] border border-base-300 px-4 text-[0.85rem] font-semibold transition-colors hover:border-base-content/60"
          >
            {gettext("Annuler")}
          </button>
          <button
            id="save-settings"
            type="button"
            phx-click="save"
            class="btn btn-primary h-10 px-[18px]"
          >
            {gettext("Enregistrer")}
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :name, :string, required: true
  attr :on, :boolean, required: true
  attr :label, :string, required: true

  defp gate(assigns) do
    ~H"""
    <label class="ta-row-rule flex cursor-pointer items-center gap-4 py-3 last:border-b-0">
      <span class="flex-1 text-[0.9rem] font-semibold">{@label}</span>
      <input type="hidden" name={"distinctions[#{@name}]"} value="false" form="distinctions-form" />
      <input
        type="checkbox"
        name={"distinctions[#{@name}]"}
        value="true"
        checked={@on}
        form="distinctions-form"
        class="ta-switch"
      />
      <span class="w-8 text-[0.8rem] text-base-content/80">
        {if @on, do: gettext("Oui"), else: gettext("Non")}
      </span>
    </label>
    """
  end

  defp band_grid, do: "grid grid-cols-[52px_16px_80px_64px_minmax(0,1fr)_34px] gap-2"

  defp distinction_tone(:avertissement_travail), do: "text-warning"
  defp distinction_tone(:blame_travail), do: "text-error"
  defp distinction_tone(_), do: "text-primary"

  def handle_event("edit_bands", %{"bands" => params}, socket) do
    rows =
      socket.assigns.rows
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        p = Map.get(params, Integer.to_string(i), %{})

        %{
          to: if(row.to, do: Map.get(p, "to", row.to), else: nil),
          label: Map.get(p, "label", row.label),
          code: Map.get(p, "code", row.code)
        }
      end)

    {:noreply, assign(socket, rows: rows, bands_error: nil, bands_dirty?: true)}
  end

  def handle_event("edit_bands", _params, socket), do: {:noreply, socket}

  def handle_event("edit_distinctions", %{"distinctions" => params}, socket) do
    dist =
      Map.new(socket.assigns.dist, fn
        {key, value} when is_boolean(value) ->
          {key, Map.get(params, key, to_string(value)) == "true"}

        {key, value} ->
          {key, Map.get(params, key, value)}
      end)

    {:noreply, assign(socket, dist: dist, distinctions_error: nil, dist_dirty?: true)}
  end

  def handle_event("discard", _params, socket),
    do:
      {:noreply,
       socket
       |> load_rules(socket.assigns.rules)
       |> assign(bands_error: nil, distinctions_error: nil)}

  # The sticky bar's "Enregistrer": the scale, then the thresholds, each only when edited.
  def handle_event("save", _params, socket) do
    with {:noreply, socket} <- maybe_save(socket, :bands_dirty?, "save_bands"),
         {:noreply, socket} <- maybe_save(socket, :dist_dirty?, "save_distinctions") do
      {:noreply, socket}
    end
  end

  def handle_event("remove_band", %{"index" => index}, socket) do
    rows = socket.assigns.rows

    rows =
      case Integer.parse(index) do
        {i, ""} when length(rows) > 1 and i >= 0 and i < length(rows) ->
          rows |> List.delete_at(i) |> close_last()

        _ ->
          rows
      end

    {:noreply, assign(socket, rows: rows, bands_error: nil, bands_dirty?: true)}
  end

  def handle_event("split_last", _params, socket) do
    rows = socket.assigns.rows

    case rows |> lower_bounds() |> List.last() |> parse() do
      %Decimal{} = from ->
        mid = from |> Decimal.add(@twenty) |> Decimal.div(2) |> Decimal.round(2)
        {last, rest} = List.pop_at(rows, -1)

        new_rows =
          rest ++
            [
              %{last | to: show_bound(mid)},
              %{to: nil, label: gettext("Nouvelle tranche"), code: nil}
            ]

        {:noreply, assign(socket, rows: new_rows, bands_error: nil, bands_dirty?: true)}

      nil ->
        {:noreply, assign(socket, bands_error: gettext("Corrigez d'abord les bornes."))}
    end
  end

  # Spec bulletin v2 §5.3: fills the APC « cotes »; saved with the bar like any edit.
  def handle_event("apc_preset", _params, socket),
    do:
      {:noreply,
       assign(socket,
         rows: rows_from(Appreciations.apc_bands()),
         bands_error: nil,
         bands_dirty?: true
       )}

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
    {:noreply, socket} = handle_event("edit_distinctions", %{"distinctions" => params}, socket)
    handle_event("save_distinctions", %{}, socket)
  end

  def handle_event("save_distinctions", _params, socket) do
    params =
      Map.new(socket.assigns.dist, fn {key, value} -> {key, to_string(value)} end)

    socket.assigns.current_scope
    |> Assessment.update_distinction_rules(params)
    |> after_save(socket, :distinctions_error, gettext("Réglage enregistré."))
  end

  defp maybe_save(socket, dirty_key, event) do
    if socket.assigns[dirty_key], do: handle_event(event, %{}, socket), else: {:noreply, socket}
  end

  # Reloads the saved rules but keeps the other section's unsaved edits.
  defp after_save({:ok, _profile}, socket, error_key, message) do
    %{rows: rows, dist: dist, bands_dirty?: bands_dirty?, dist_dirty?: dist_dirty?} =
      socket.assigns

    socket = load_rules(socket, Assessment.grading_rules(socket.assigns.current_scope))

    socket =
      case error_key do
        :bands_error -> assign(socket, dist: dist, dist_dirty?: dist_dirty?)
        :distinctions_error -> assign(socket, rows: rows, bands_dirty?: bands_dirty?)
      end

    {:noreply, socket |> assign(error_key, nil) |> put_flash(:info, message)}
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
