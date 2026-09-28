defmodule TeacherAssistant.Academics.BulletinsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{Bulletins, GradingRules}

  # helper: one subject with a /20 mark per student (max 20, weight 1)
  defp subject(context_id, label, coef, marks) do
    aid = context_id <> "-a"

    %{
      context_id: context_id,
      label: label,
      coefficient: Decimal.new(coef),
      assessments_by_id: %{aid => %{weight: Decimal.new(1), max_score: Decimal.new(20)}},
      marks:
        Enum.map(marks, fn {sid, score} ->
          %{student_id: sid, assessment_id: aid, score: score && Decimal.new(score)}
        end)
    }
  end

  test "moyenne générale is coefficient-weighted over graded subjects" do
    students = [%{id: "s1", sex: :m}]

    subjects = [
      subject("maths", "Maths", "4", [{"s1", "15"}]),
      subject("eps", "EPS", "1", [{"s1", "10"}])
    ]

    r = Bulletins.compile(students, subjects)
    # (15*4 + 10*1) / (4+1) = 70/5 = 14
    assert Decimal.equal?(r.per_student["s1"].moyenne_generale, Decimal.new(14))
    assert Decimal.equal?(r.per_student["s1"].total_points, Decimal.new(70))
    assert Decimal.equal?(r.per_student["s1"].total_coef, Decimal.new(5))
    assert r.per_student["s1"].mention == :bien
  end

  test "a subject with no mark is excluded from the moyenne générale, not counted as 0" do
    students = [%{id: "s1", sex: :f}]

    subjects = [
      subject("maths", "Maths", "4", [{"s1", "12"}]),
      subject("svt", "SVT", "4", [{"s1", nil}])
    ]

    r = Bulletins.compile(students, subjects)
    # only Maths graded ⇒ 12; SVT excluded from Σcoef
    assert Decimal.equal?(r.per_student["s1"].moyenne_generale, Decimal.new(12))
    assert Decimal.equal?(r.per_student["s1"].total_coef, Decimal.new(4))
    svt = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "svt"))
    assert svt.average == nil
  end

  test "ranks students by moyenne générale with ex-aequo" do
    students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :m}, %{id: "s3", sex: :f}]
    subjects = [subject("maths", "Maths", "1", [{"s1", "16"}, {"s2", "16"}, {"s3", "8"}])]
    r = Bulletins.compile(students, subjects)
    assert r.per_student["s1"].rank == 1
    assert r.per_student["s2"].rank == 1
    assert r.per_student["s3"].rank == 3
  end

  test "class stats and gender split over graded students only" do
    students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :f}, %{id: "s3", sex: :f}]
    subjects = [subject("maths", "Maths", "1", [{"s1", "10"}, {"s2", "16"}, {"s3", nil}])]
    r = Bulletins.compile(students, subjects)
    assert r.effectif == 3
    assert r.graded_count == 2
    assert Decimal.equal?(r.class_average, Decimal.new(13))
    assert r.pass_rate == 1.0
    assert Decimal.equal?(r.highest, Decimal.new(16))
    assert Decimal.equal?(r.lowest, Decimal.new(10))
    assert r.by_sex.f.graded_count == 1
    assert Decimal.equal?(r.by_sex.f.class_average, Decimal.new(16))
    # ungraded student is unranked
    assert r.per_student["s3"].rank == nil
    assert r.per_student["s3"].moyenne_generale == nil
  end

  test "per-subject class min/max and subject rank" do
    students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :m}]
    subjects = [subject("maths", "Maths", "1", [{"s1", "18"}, {"s2", "12"}])]
    r = Bulletins.compile(students, subjects)
    m1 = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "maths"))
    assert Decimal.equal?(m1.class_max, Decimal.new(18))
    assert Decimal.equal?(m1.class_min, Decimal.new(12))
    assert m1.subject_rank == 1
    assert Decimal.equal?(m1.note_x_coef, Decimal.new(18))
  end

  test "distinctions: highest applicable roll, gated on all subjects >= 10" do
    students = [%{id: "hi", sex: :m}, %{id: "mid", sex: :m}, %{id: "fail", sex: :f}]

    subjects = [
      subject("maths", "Maths", "1", [{"hi", "17"}, {"mid", "14"}, {"fail", "18"}]),
      subject("fr", "Français", "1", [{"hi", "16"}, {"mid", "15"}, {"fail", "8"}])
    ]

    r = Bulletins.compile(students, subjects)
    # hi: avg 16.5 ⇒ Félicitations; mid: 14.5, all ≥10 ⇒ Encouragements;
    # fail: avg 13 but a subject <10 ⇒ no roll
    assert "hi" in r.distinctions.felicitations
    assert "mid" in r.distinctions.encouragements
    refute "fail" in r.distinctions.tableau_honneur
    refute "fail" in r.distinctions.encouragements
  end

  describe "aggregate/2" do
    test "ranks and weights pre-computed subject averages, carrying components" do
      students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :f}]

      inputs = [
        %{
          context_id: "maths",
          label: "Maths",
          coefficient: Decimal.new(4),
          per_student_avg: %{"s1" => Decimal.new(15), "s2" => Decimal.new(9)},
          components: %{
            "s1" => %{
              sequences: [
                %{number: 1, average: Decimal.new(14)},
                %{number: 2, average: Decimal.new(16)}
              ]
            },
            "s2" => %{
              sequences: [
                %{number: 1, average: Decimal.new(8)},
                %{number: 2, average: Decimal.new(10)}
              ]
            }
          }
        },
        %{
          context_id: "eps",
          label: "EPS",
          coefficient: Decimal.new(1),
          per_student_avg: %{"s1" => Decimal.new(10), "s2" => Decimal.new(12)},
          components: nil
        }
      ]

      r = Bulletins.aggregate(students, inputs)
      # s1: (15*4 + 10*1)/5 = 14 ; s2: (9*4 + 12*1)/5 = 9.6
      assert Decimal.equal?(r.per_student["s1"].moyenne_generale, Decimal.new(14))
      assert Decimal.equal?(r.per_student["s2"].moyenne_generale, Decimal.new("9.6"))
      assert r.per_student["s1"].rank == 1
      assert r.per_student["s2"].rank == 2
      # component passthrough on the maths row
      maths = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "maths"))
      assert [%{number: 1, average: a1}, %{number: 2, average: a2}] = maths.components.sequences
      assert Decimal.equal?(a1, Decimal.new(14)) and Decimal.equal?(a2, Decimal.new(16))
      # nil components on the eps row
      eps = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "eps"))
      assert eps.components == nil
    end
  end

  test "rows are ordered by bulletin group, then position, and grouped with subtotals" do
    students = [%{id: "s1", sex: :m}]

    subjects = [
      "eps"
      |> subject("EPS", "1", [{"s1", "10"}])
      |> Map.merge(%{group: :g3_autres, position: 0}),
      "maths"
      |> subject("Maths", "4", [{"s1", "15"}])
      |> Map.merge(%{group: :g2_sciences, position: 0}),
      "fr"
      |> subject("Français", "4", [{"s1", "12"}])
      |> Map.merge(%{group: :g1_lettres, position: 1}),
      "ang"
      |> subject("Anglais", "2", [{"s1", nil}])
      |> Map.merge(%{group: :g1_lettres, position: 0})
    ]

    d = Bulletins.compile(students, subjects).per_student["s1"]
    assert Enum.map(d.subjects, & &1.label) == ["Anglais", "Français", "Maths", "EPS"]
    assert Enum.map(d.groups, & &1.group) == [:g1_lettres, :g2_sciences, :g3_autres]

    [lettres | _] = d.groups
    assert Enum.map(lettres.rows, & &1.label) == ["Anglais", "Français"]
    assert Decimal.equal?(lettres.total_coef, 4)
    assert Decimal.equal?(lettres.total_points, 48)
    assert Decimal.equal?(lettres.average, 12)

    # (12*4 + 15*4 + 10*1) / 9 — grouping never changes the moyenne générale
    assert Decimal.equal?(d.moyenne_generale, Decimal.div(Decimal.new(118), Decimal.new(9)))
  end

  test "subjects without a group fall in G3, and a group with no graded subject has no average" do
    students = [%{id: "s1", sex: :f}]
    d = Bulletins.compile(students, [subject("x", "X", "1", [{"s1", nil}])]).per_student["s1"]
    assert [%{group: :g3_autres, average: nil, total_points: nil}] = d.groups
  end

  test "with rules, subject averages are rounded first and the bulletin adds up" do
    students = [%{id: "s1", sex: :m, name: "Awa"}]
    # Maths: 12.345/20 → 12.35 ; EPS 10
    subjects = [
      subject("maths", "Maths", "3", [{"s1", "12.345"}]),
      subject("eps", "EPS", "1", [{"s1", "10"}])
    ]

    rules = %GradingRules{rounding: :hundredth}
    d = Bulletins.compile(students, subjects, rules).per_student["s1"]
    maths = Enum.find(d.subjects, &(&1.label == "Maths"))
    assert Decimal.equal?(maths.average, Decimal.new("12.35"))
    assert Decimal.equal?(maths.note_x_coef, Decimal.new("37.05"))
    # (37.05 + 10) / 4 = 11.7625 → 11.76
    assert Decimal.equal?(d.moyenne_generale, Decimal.new("11.76"))
  end

  test "ties created by rounding: shared, or (class level) broken by the moyenne then the name" do
    students = [%{id: "a", sex: :f, name: "Awa"}, %{id: "b", sex: :m, name: "Bob"}]
    # a: 13.12 → quarter 13.00 ; b: 12.9 → quarter 13.00 ; unrounded a > b
    subjects = [subject("m", "Maths", "1", [{"a", "13.12"}, {"b", "12.9"}])]

    shared = Bulletins.compile(students, subjects, %GradingRules{rounding: :quarter})
    assert shared.per_student["a"].rank == 1 and shared.per_student["b"].rank == 1

    strict =
      Bulletins.compile(students, subjects, %GradingRules{
        rounding: :quarter,
        shared_ranks?: false
      })

    assert strict.per_student["a"].rank == 1 and strict.per_student["b"].rank == 2
  end

  test "the absence rule, make-up flags and exemptions reach the bulletin" do
    students = [%{id: "s1", sex: :f, name: "Awa"}, %{id: "s2", sex: :m, name: "Bob"}]

    maths = %{
      subject("maths", "Maths", "2", [{"s1", "14"}])
      | marks: [
          %{student_id: "s1", assessment_id: "maths-a", score: Decimal.new(14), status: :graded},
          %{student_id: "s2", assessment_id: "maths-a", score: nil, status: :absent}
        ]
    }

    esp = subject("esp", "Espagnol", "1", [{"s1", "10"}]) |> Map.put(:exempt, MapSet.new(["s2"]))

    zero = Bulletins.compile(students, [maths, esp], %GradingRules{absence: :zero})

    assert Decimal.equal?(
             Enum.find(zero.per_student["s2"].subjects, &(&1.label == "Maths")).average,
             0
           )

    refute Enum.any?(zero.per_student["s2"].subjects, &(&1.label == "Espagnol"))
    assert zero.makeup_pending_count == 0

    makeup = Bulletins.compile(students, [maths, esp], %GradingRules{absence: :makeup})
    row = Enum.find(makeup.per_student["s2"].subjects, &(&1.label == "Maths"))
    assert row.average == nil and row.makeup_pending
    assert makeup.makeup_pending_count == 1
  end

  test "per-subject ranks break rounding ties by the unrounded average, like the marks summary" do
    # Zoé 13.12 and Awa 12.9 both round to 13.00 at quarter precision; names sort
    # the opposite way to the unrounded averages, so a name tie-break would flip them.
    students = [%{id: "z", sex: :f, name: "Zoé"}, %{id: "a", sex: :f, name: "Awa"}]
    subjects = [subject("m", "Maths", "1", [{"z", "13.12"}, {"a", "12.9"}])]
    rules = %GradingRules{rounding: :quarter, shared_ranks?: false}

    r = Bulletins.compile(students, subjects, rules)
    [z_row] = r.per_student["z"].subjects
    [a_row] = r.per_student["a"].subjects
    assert z_row.subject_rank == 1 and a_row.subject_rank == 2

    summary =
      TeacherAssistant.Academics.Marks.summarize(
        students,
        [%{id: "m-a", weight: Decimal.new(1), max_score: Decimal.new(20)}],
        [
          %{assessment_id: "m-a", student_id: "z", score: Decimal.new("13.12")},
          %{assessment_id: "m-a", student_id: "a", score: Decimal.new("12.9")}
        ],
        rules
      )

    assert summary.per_student["z"].rank == z_row.subject_rank
    assert summary.per_student["a"].rank == a_row.subject_rank
  end

  test "period results keep the unrounded subject average for the tie-break" do
    students = [%{id: "z", sex: :f, name: "Zoé"}, %{id: "a", sex: :f, name: "Awa"}]
    rules = %GradingRules{rounding: :quarter, shared_ranks?: false}

    input = %{
      context_id: "m",
      label: "Maths",
      coefficient: Decimal.new(1),
      per_student_avg: %{"z" => Decimal.new(13), "a" => Decimal.new(13)},
      per_student_precise: %{"z" => Decimal.new("13.06"), "a" => Decimal.new("12.94")},
      components: nil
    }

    r = Bulletins.aggregate(students, [input], rules)
    assert [%{subject_rank: 1}] = r.per_student["z"].subjects
    assert [%{subject_rank: 2}] = r.per_student["a"].subjects
  end
end
