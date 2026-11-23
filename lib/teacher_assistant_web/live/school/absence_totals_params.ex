defmodule TeacherAssistantWeb.School.AbsenceTotalsParams do
  @moduledoc """
  Spec 2026-11-23 « Bilan des absences »: the URL params (`period`, `class`, `seuil`)
  resolved into what the page and its print show, so screen and paper always agree.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.{Attendance, Enrollment, Organization}
  alias TeacherAssistant.Academics.{AbsenceTotals, EntryProgress, Reference, SchoolTemplates}

  @doc """
  `{:ok, view}` for the scope's current year, or `:no_sequences` before its calendar
  exists. `view.all_groups` holds the figures read; `view.groups` is the shown list
  (see `refilter/2`).
  """
  def resolve(%{current_academic_year: %{} = year} = scope, params) do
    case Organization.list_sequences(scope, year) do
      [] ->
        :no_sequences

      sequences ->
        terms = Organization.list_terms(scope, year)

        class_groups =
          scope
          |> Enrollment.list_class_groups(year)
          |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)

        period =
          (is_binary(params["period"]) &&
             Organization.resolve_period(scope, year, params["period"])) ||
            {:sequence, EntryProgress.default_sequence(sequences, Reference.today())}

        class_group = Enum.find(class_groups, &(&1.id == params["class"]))
        count = length(Organization.period_sequences(scope, period))

        view = %{
          period: period,
          period_param: Organization.period_param(period),
          class_group: class_group,
          class_groups: class_groups,
          sequences: sequences,
          terms: terms,
          default_threshold: AbsenceTotals.default_threshold(count),
          sequence_count: count,
          all_groups:
            Attendance.absence_totals(scope, period, List.wrap(class_group || class_groups))
        }

        {:ok, refilter(view, params)}
    end
  end

  def resolve(_scope, _params), do: :no_sequences

  @doc """
  Whether `params` name the same period and class as `view`: then only the threshold
  may have changed, and `refilter/2` is enough (no reads).
  """
  def same_figures?(view, params),
    do:
      params["period"] == view.period_param and
        (params["class"] || "") == ((view.class_group && view.class_group.id) || "")

  @doc """
  `view` with the threshold of `params` and the shown groups: one class in full, or
  every class cut to the students at or over the threshold. No reads.
  """
  def refilter(view, params) do
    threshold = AbsenceTotals.parse_threshold(params["seuil"], view.default_threshold)

    groups =
      if view.class_group,
        do: view.all_groups,
        else: AbsenceTotals.over_threshold(view.all_groups, threshold)

    Map.merge(view, %{threshold: threshold, groups: groups})
  end

  @doc "The URL params of `view` (the threshold only when it is not the default), with `overrides`."
  def query(view, overrides \\ []) do
    [
      period: view.period_param,
      class: view.class_group && view.class_group.id,
      seuil:
        if(Decimal.equal?(view.threshold, view.default_threshold),
          do: nil,
          else: Decimal.to_string(view.threshold, :normal)
        )
    ]
    |> Keyword.merge(overrides)
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
  end

  @doc "The period picker's options: séquences, trimesters, the year."
  def period_options(view) do
    for(s <- view.sequences, do: {gettext("Séquence %{n}", n: s.number), "seq:#{s.id}"}) ++
      for(t <- view.terms, do: {gettext("Trimestre %{n}", n: t.position), "trim:#{t.id}"}) ++
      [{gettext("Année"), "annee"}]
  end

  @doc "« Séquence 2 », « Trimestre 1 », « Année »: the period as a title."
  def period_label({:sequence, s}), do: gettext("Séquence %{n}", n: s.number)
  def period_label({:trimester, t}), do: gettext("Trimestre %{n}", n: t.position)
  def period_label({:annual, _}), do: gettext("Année")

  @doc "« Seuil : 60 h — 20 h × 3 séquences », or « Seuil : 20 h » when typed or for one séquence."
  def threshold_line(view) do
    hours = TeacherAssistantWeb.Numbers.hours(view.threshold)

    if view.sequence_count > 1 and Decimal.equal?(view.threshold, view.default_threshold),
      do:
        gettext("Seuil : %{hours} — 20 h × %{count} séquences",
          hours: hours,
          count: view.sequence_count
        ),
      else: gettext("Seuil : %{hours}", hours: hours)
  end
end
