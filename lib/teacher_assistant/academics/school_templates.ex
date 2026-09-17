defmodule TeacherAssistant.Academics.SchoolTemplates do
  @moduledoc """
  Starter structure per {school_type, subsystem}: levels, streams
  (séries/spécialités), and a starter subject catalog. Séries are configurable
  reference data (docs/domain/01 §3) — these are seed suggestions the head
  edits, not a frozen enum. Exhaustive OBC/CETIC codes are a later refinement.
  """

  @dec &Decimal.new/1

  @technical_types [:cetic, :lycee_technique, :gtc, :gths, :sar_sm]

  @general_subjects [
    {"Mathématiques", "MATH", :general, 4},
    {"Français", "FR", :general, 4},
    {"Anglais", "ANG", :language, 2},
    {"Physique", "PHY", :general, 2},
    {"Chimie", "CHI", :general, 2},
    {"SVT", "SVT", :general, 2},
    {"Histoire-Géographie", "HG", :general, 2},
    {"ECM", "ECM", :general, 1},
    {"Informatique", "INFO", :general, 1},
    {"EPS", "EPS", :general, 1}
  ]

  @technical_subjects [
    {"Technologie", "TECHNO", :technical, 4},
    {"Dessin technique", "DESS", :technical, 3},
    {"Atelier / Pratique", "ATEL", :technical, 4}
  ]

  @francophone_general_levels ~w(6ème 5ème 4ème 3ème 2nde 1ère Terminale)
  @lycee_streamed_levels ~w(2nde 1ère Terminale)
  @lycee_series ~w(A4 C D)
  @collège_levels ~w(6ème 5ème 4ème 3ème)
  @technical_levels ["1ère Année", "2ème Année", "3ème Année", "4ème Année"]
  @cetic_specialities ~w(ELEQ MACO MENU)
  @anglophone_levels ["Form 1", "Form 2", "Form 3", "Form 4", "Form 5", "Lower Sixth", "Upper Sixth"]
  @sixth ["Lower Sixth", "Upper Sixth"]

  # ---- subjects ------------------------------------------------------------

  def subjects_for(type, _subsystem) when type in @technical_types,
    do: to_subjects(@general_subjects ++ @technical_subjects)

  def subjects_for(_type, _subsystem), do: to_subjects(@general_subjects)

  defp to_subjects(list) do
    for {name, code, cat, coef} <- list,
        do: %{name: name, code: code, category: cat, default_coefficient: @dec.(coef)}
  end

  # ---- levels --------------------------------------------------------------

  def levels_for(type, _) when type in [:cetic, :sar_sm, :gtc, :gths], do: @technical_levels
  def levels_for(:lycee_technique, _), do: ~w(2nde 1ère Terminale)
  def levels_for(:ces_ceg, _), do: @collège_levels
  def levels_for(_type, :anglophone), do: @anglophone_levels
  def levels_for(_type, _subsystem), do: @francophone_general_levels

  # ---- streams (séries / spécialités) -------------------------------------

  def streams_for(type, _) when type in [:cetic, :sar_sm],
    do: %{kind: :specialite, values: @cetic_specialities, levels: @technical_levels}

  def streams_for(:lycee_technique, _),
    do: %{kind: :specialite, values: ~w(F1 F2 F3 G1 G2), levels: ~w(2nde 1ère Terminale)}

  def streams_for(type, subsystem) when type in [:gtc, :gths] do
    levels = levels_for(type, subsystem)
    %{kind: :specialite, values: @cetic_specialities, levels: levels}
  end

  def streams_for(:ces_ceg, _), do: %{kind: :serie, values: [], levels: []}

  def streams_for(_type, :anglophone),
    do: %{kind: :stream, values: ["Arts", "Science"], levels: @sixth}

  def streams_for(_type, _subsystem),
    do: %{kind: :serie, values: @lycee_series, levels: @lycee_streamed_levels}

  def stream_label(:serie), do: "Série"
  def stream_label(:specialite), do: "Spécialité"
  def stream_label(:stream), do: "Stream"

  # ---- starter classes -----------------------------------------------------

  def classes_for(type, subsystem) do
    %{values: streams, levels: streamed} = streams_for(type, subsystem)

    for level <- levels_for(type, subsystem), row <- classes_at(level, streams, streamed) do
      row
    end
  end

  defp classes_at(level, streams, streamed) do
    if streams != [] and level in streamed do
      for s <- streams, do: %{label: "#{level} #{s}", level: level, serie: s}
    else
      [%{label: level, level: level, serie: nil}]
    end
  end
end
