defmodule TeacherAssistant.Academics.Reference do
  @moduledoc "Bilingual suggestion lists and the default academic calendar preset (see docs/domain)."

  def subsystems do
    [
      %{key: :francophone, fr: "Francophone", en: "Francophone"},
      %{key: :anglophone, fr: "Anglophone", en: "Anglophone"}
    ]
  end

  def levels(:francophone), do: ["6ème", "5ème", "4ème", "3ème", "2nde", "1ère", "Terminale"]
  def levels(:anglophone), do: ["Form 1", "Form 2", "Form 3", "Form 4", "Form 5", "Lower Sixth", "Upper Sixth"]

  def subjects do
    [
      %{key: :maths, fr: "Mathématiques", en: "Mathematics"},
      %{key: :french, fr: "Français", en: "French"},
      %{key: :english, fr: "Anglais", en: "English"},
      %{key: :physics, fr: "Physique", en: "Physics"},
      %{key: :chemistry, fr: "Chimie", en: "Chemistry"},
      %{key: :biology, fr: "SVT", en: "Biology"},
      %{key: :history, fr: "Histoire", en: "History"},
      %{key: :geography, fr: "Géographie", en: "Geography"},
      %{key: :computer_science, fr: "Informatique", en: "Computer Science"},
      %{key: :citizenship, fr: "ECM", en: "Citizenship"},
      %{key: :pe, fr: "EPS", en: "Physical Education"}
    ]
  end

  def entry_types do
    [
      %{key: :lesson, fr: "Leçon", en: "Lesson"},
      %{key: :integration, fr: "Intégration", en: "Integration"},
      %{key: :evaluation, fr: "Évaluation", en: "Evaluation"},
      %{key: :revision, fr: "Révision", en: "Revision"},
      %{key: :correction, fr: "Correction", en: "Correction"},
      %{key: :remediation, fr: "Remédiation", en: "Remediation"},
      %{key: :holiday, fr: "Congé", en: "Holiday"}
    ]
  end

  def entry_type_keys, do: Enum.map(entry_types(), & &1.key)

  @doc "Official 2025-2026 grid (docs/domain/01 §6). Dates are editable in the wizard."
  def default_calendar_preset do
    %{
      terms: [
        %{position: 1, sequences: [
          %{number: 1, position_in_term: 1, start_date: ~D[2025-09-08], end_date: ~D[2025-10-24], integration_week: false},
          %{number: 2, position_in_term: 2, start_date: ~D[2025-10-27], end_date: ~D[2025-11-28], integration_week: true}
        ]},
        %{position: 2, sequences: [
          %{number: 3, position_in_term: 1, start_date: ~D[2025-12-01], end_date: ~D[2026-01-30], integration_week: false},
          %{number: 4, position_in_term: 2, start_date: ~D[2026-02-02], end_date: ~D[2026-03-06], integration_week: true}
        ]},
        %{position: 3, sequences: [
          %{number: 5, position_in_term: 1, start_date: ~D[2026-03-09], end_date: ~D[2026-04-30], integration_week: false},
          %{number: 6, position_in_term: 2, start_date: ~D[2026-05-04], end_date: ~D[2026-06-12], integration_week: true}
        ]}
      ]
    }
  end
end
