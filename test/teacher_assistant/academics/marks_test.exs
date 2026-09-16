defmodule TeacherAssistant.Academics.MarksTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Marks

  defp d(n), do: Decimal.new(n)

  describe "mention/1" do
    test "bands per domain doc" do
      assert Marks.mention(d("9")) == nil
      assert Marks.mention(d("10")) == :passable
      assert Marks.mention(d("12")) == :assez_bien
      assert Marks.mention(d("14")) == :bien
      assert Marks.mention(d("16")) == :tres_bien
      assert Marks.mention(d("18")) == :excellent
      assert Marks.mention(nil) == nil
    end
  end

  describe "subject_average/2" do
    test "weights marks and normalizes to /20" do
      assessments = %{
        "a" => %{weight: d(1), max_score: d(20)},
        "b" => %{weight: d(3), max_score: d(10)}
      }

      # a: 10/20 → 10 (w1); b: 8/10 → 16/20 (w3) ⇒ (10*1 + 16*3)/4 = 58/4 = 14.5
      marks = [%{assessment_id: "a", score: d(10)}, %{assessment_id: "b", score: d(8)}]
      assert Decimal.equal?(Marks.subject_average(marks, assessments), d("14.5"))
    end

    test "ignores nil scores and returns nil when nothing graded" do
      assessments = %{"a" => %{weight: d(1), max_score: d(20)}}
      assert Marks.subject_average([%{assessment_id: "a", score: nil}], assessments) == nil
      assert Marks.subject_average([], assessments) == nil
    end
  end

  describe "annual_average/1" do
    test "unweighted mean of non-nil sequence averages" do
      assert Decimal.equal?(Marks.annual_average([d("10"), d("14"), nil]), d("12"))
    end

    test "nil when nothing graded" do
      assert Marks.annual_average([nil, nil]) == nil
    end
  end

  describe "summarize/3" do
    setup do
      students = [%{id: "s1", sex: :f}, %{id: "s2", sex: :m}, %{id: "s3", sex: :m}]

      assessments = [
        %{id: "a1", weight: d("1"), max_score: d("20")},
        %{id: "a2", weight: d("2"), max_score: d("20")}
      ]

      # s1: (16*1 + 10*2)/3 = 12 ; s2: (8*1 + 8*2)/3 = 8 ; s3: no marks -> nil
      marks = [
        %{assessment_id: "a1", student_id: "s1", score: d("16")},
        %{assessment_id: "a2", student_id: "s1", score: d("10")},
        %{assessment_id: "a1", student_id: "s2", score: d("8")},
        %{assessment_id: "a2", student_id: "s2", score: d("8")}
      ]

      %{result: Marks.summarize(students, assessments, marks)}
    end

    test "weighted per-student averages and mentions", %{result: r} do
      assert Decimal.equal?(r.per_student["s1"].average, d("12"))
      assert r.per_student["s1"].mention == :assez_bien
      assert Decimal.equal?(r.per_student["s2"].average, d("8"))
      assert r.per_student["s3"].average == nil
      assert r.per_student["s3"].mention == nil
    end

    test "ranking, ungraded students unranked", %{result: r} do
      assert r.per_student["s1"].rank == 1
      assert r.per_student["s2"].rank == 2
      assert r.per_student["s3"].rank == nil
    end

    test "class stats exclude ungraded", %{result: r} do
      assert Decimal.equal?(r.class_average, d("10"))
      assert r.graded_count == 2
      assert r.pass_rate == 0.5
      assert Decimal.equal?(r.highest, d("12"))
      assert Decimal.equal?(r.lowest, d("8"))
    end

    test "gender split", %{result: r} do
      assert Decimal.equal?(r.by_sex.f.class_average, d("12"))
      assert r.by_sex.f.pass_rate == 1.0
      assert Decimal.equal?(r.by_sex.m.class_average, d("8"))
      assert r.by_sex.m.pass_rate == 0.0
      assert r.by_sex.m.graded_count == 1
    end
  end

  describe "summarize/3 ties" do
    test "ex-aequo share a rank" do
      students = [%{id: "s1", sex: :f}, %{id: "s2", sex: :m}]
      assessments = [%{id: "a1", weight: d("1"), max_score: d("20")}]

      marks = [
        %{assessment_id: "a1", student_id: "s1", score: d("14")},
        %{assessment_id: "a1", student_id: "s2", score: d("14")}
      ]

      r = Marks.summarize(students, assessments, marks)
      assert r.per_student["s1"].rank == 1
      assert r.per_student["s2"].rank == 1
    end

    test "competition ranking: tie consumes ranks, next student skips to 3" do
      students = [%{id: "s1", sex: :f}, %{id: "s2", sex: :m}, %{id: "s3", sex: :m}]
      assessments = [%{id: "a1", weight: d("1"), max_score: d("20")}]

      marks = [
        %{assessment_id: "a1", student_id: "s1", score: d("14")},
        %{assessment_id: "a1", student_id: "s2", score: d("14")},
        %{assessment_id: "a1", student_id: "s3", score: d("10")}
      ]

      r = Marks.summarize(students, assessments, marks)
      assert r.per_student["s1"].rank == 1
      assert r.per_student["s2"].rank == 1
      assert r.per_student["s3"].rank == 3
    end
  end
end
