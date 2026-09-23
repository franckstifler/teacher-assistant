defmodule TeacherAssistant.Academics.Reference do
  @moduledoc "Bilingual suggestion lists and the default academic calendar preset (see docs/domain)."

  def subsystems do
    [
      %{key: :francophone, fr: "Francophone", en: "Francophone"},
      %{key: :anglophone, fr: "Anglophone", en: "Anglophone"}
    ]
  end

  def levels(:francophone), do: ["6ème", "5ème", "4ème", "3ème", "2nde", "1ère", "Terminale"]

  def levels(:anglophone),
    do: ["Form 1", "Form 2", "Form 3", "Form 4", "Form 5", "Lower Sixth", "Upper Sixth"]

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

  # Relative weight of each séquence in the official grid (docs/domain/01 §6):
  # the span from a séquence's first day to the next séquence's first day,
  # 2025-2026 reference year. Term 1 = S1+S2, term 2 = S3+S4, term 3 = S5+S6.
  @sequence_weights [49, 35, 63, 35, 56, 40]
  @integration_weeks [false, true, false, true, false, true]

  @doc """
  The default academic calendar for a year running from `start_date` to
  `end_date`: 3 terms × 2 séquences, consecutive (no gaps, so every in-year
  date belongs to exactly one séquence), sized proportionally to the official
  grid. The first séquence starts on `start_date`, the last ends on `end_date`.
  """
  def default_calendar_preset(%Date{} = start_date, %Date{} = end_date) do
    total_days = Date.diff(end_date, start_date) + 1

    if total_days < 6 do
      raise ArgumentError,
            "an academic year needs at least 6 days for six séquences, got #{total_days}"
    end

    total_weight = Enum.sum(@sequence_weights)

    {sequences, _next_start} =
      @sequence_weights
      |> Enum.with_index(1)
      |> Enum.map_reduce(start_date, fn {weight, number}, seq_start ->
        seq_end =
          if number == 6 do
            end_date
          else
            days = max(div(total_days * weight, total_weight), 1)
            Date.add(seq_start, days - 1)
          end

        seq = %{
          number: number,
          position_in_term: rem(number - 1, 2) + 1,
          start_date: seq_start,
          end_date: seq_end,
          integration_week: Enum.at(@integration_weeks, number - 1)
        }

        {seq, Date.add(seq_end, 1)}
      end)

    terms =
      sequences
      |> Enum.chunk_every(2)
      |> Enum.with_index(1)
      |> Enum.map(fn {seqs, position} -> %{position: position, sequences: seqs} end)

    %{terms: terms}
  end

  @doc "Standard Cameroonian bell schedule: 8 lessons + mid-morning/lunch breaks (docs/domain)."
  def default_periods_preset do
    [
      %{
        position: 1,
        label: "Cours 1",
        start_time: ~T[07:30:00],
        end_time: ~T[08:25:00],
        kind: :lesson
      },
      %{
        position: 2,
        label: "Cours 2",
        start_time: ~T[08:25:00],
        end_time: ~T[09:20:00],
        kind: :lesson
      },
      %{
        position: 3,
        label: "Récréation",
        start_time: ~T[09:20:00],
        end_time: ~T[09:40:00],
        kind: :break
      },
      %{
        position: 4,
        label: "Cours 3",
        start_time: ~T[09:40:00],
        end_time: ~T[10:35:00],
        kind: :lesson
      },
      %{
        position: 5,
        label: "Cours 4",
        start_time: ~T[10:35:00],
        end_time: ~T[11:30:00],
        kind: :lesson
      },
      %{
        position: 6,
        label: "Cours 5",
        start_time: ~T[11:30:00],
        end_time: ~T[12:25:00],
        kind: :lesson
      },
      %{
        position: 7,
        label: "Pause déjeuner",
        start_time: ~T[12:25:00],
        end_time: ~T[13:25:00],
        kind: :break
      },
      %{
        position: 8,
        label: "Cours 6",
        start_time: ~T[13:25:00],
        end_time: ~T[14:20:00],
        kind: :lesson
      },
      %{
        position: 9,
        label: "Cours 7",
        start_time: ~T[14:20:00],
        end_time: ~T[15:15:00],
        kind: :lesson
      },
      %{
        position: 10,
        label: "Cours 8",
        start_time: ~T[15:15:00],
        end_time: ~T[16:10:00],
        kind: :lesson
      }
    ]
  end
end
