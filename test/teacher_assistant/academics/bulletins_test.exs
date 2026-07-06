defmodule TeacherAssistant.Academics.BulletinsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Bulletins

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
end
