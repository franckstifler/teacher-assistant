defmodule TeacherAssistant.Assessment.SequenceCompetenceTest do
  @moduledoc "Spec bulletin v2 §6: the competence evaluated per course and séquence."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, MarksFixtures}

  test "put then read a competence" do
    %{t: t, tc: tc, seq: seq} = MarksFixtures.marks_world()

    assert :ok = Assessment.put_sequence_competence(t, tc, seq, "Calculer un pourcentage")

    assert Assessment.sequence_competences(t, [tc.id], [seq.id]) ==
             %{{tc.id, seq.id} => "Calculer un pourcentage"}
  end

  test "blank text removes it" do
    %{t: t, tc: tc, seq: seq} = MarksFixtures.marks_world()

    :ok = Assessment.put_sequence_competence(t, tc, seq, "Lire une carte")
    assert :ok = Assessment.put_sequence_competence(t, tc, seq, "   ")
    assert Assessment.sequence_competences(t, [tc.id], [seq.id]) == %{}
  end

  test "combined course writes every member context" do
    %{head: head, cg: cg, year: year, seq: seq} = MarksFixtures.marks_world()
    {:ok, other} = Enrollment.create_class_group(head, year, %{label: "6e B", level: "6ème"})
    {:ok, tc_a} = Curriculum.assign_teacher(head, cg, head.current_user, %{subject: "Histoire"})

    {:ok, tc_b} =
      Curriculum.assign_teacher(head, other, head.current_user, %{subject: "Histoire"})

    {:ok, _course} = Curriculum.combine_course(head, [tc_a, tc_b])
    {:ok, tc_a} = Curriculum.get_teaching_context(head, tc_a.id)

    assert :ok = Assessment.put_sequence_competence(head, tc_a, seq, "Situer les régions")

    assert Assessment.sequence_competences(head, [tc_a.id, tc_b.id], [seq.id]) == %{
             {tc_a.id, seq.id} => "Situer les régions",
             {tc_b.id, seq.id} => "Situer les régions"
           }
  end

  test "apc? follows the school's bulletin elements" do
    %{head: head, cg: cg} = MarksFixtures.marks_world()
    refute Assessment.apc?(head, cg)

    {:ok, _} =
      Assessment.update_bulletin_settings(head, %{
        "language" => "by_class",
        "elements" => ["apc", "rank"]
      })

    assert Assessment.apc?(head, cg)
  end
end
