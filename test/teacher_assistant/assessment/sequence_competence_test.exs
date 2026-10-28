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

  test "the course's teacher writes it even when a member class was reassigned to someone else" do
    %{head: head, t: t, tc: tc, year: year, seq: seq} = MarksFixtures.marks_world()
    {:ok, other_cg} = Enrollment.create_class_group(head, year, %{label: "6e C", level: "6ème"})
    {:ok, tc2} = Curriculum.assign_teacher(head, other_cg, t.current_user, %{subject: tc.subject})
    {:ok, _course} = Curriculum.combine_course(head, [tc, tc2])

    %{teacher: other} =
      TeacherAssistant.TeacherFixtures.school_teacher_fixture(head, %{subject: "Anglais"})

    {:ok, tc2} = Curriculum.get_teaching_context(head, tc2.id)
    {:ok, _} = Curriculum.reassign_teacher(head, tc2, other)
    {:ok, tc} = Curriculum.get_teaching_context(head, tc.id)

    assert :ok = Assessment.put_sequence_competence(t, tc, seq, "Lire un graphique")

    assert Assessment.sequence_competences(head, [tc.id, tc2.id], [seq.id]) == %{
             {tc.id, seq.id} => "Lire un graphique",
             {tc2.id, seq.id} => "Lire un graphique"
           }
  end

  describe "competences_due/3" do
    defp tick_apc(head) do
      {:ok, _} =
        Assessment.update_bulletin_settings(head, %{
          "language" => "by_class",
          "elements" => ["apc", "rank"]
        })
    end

    test "nil when the school's report cards are not APC" do
      %{head: head, tc: tc, seq: seq} = MarksFixtures.marks_world()
      assert Assessment.competences_due(head, seq, [tc.id]) == nil
    end

    test "each course's competence, nil when missing, for a started séquence" do
      %{head: head, t: t, tc: tc, cg: cg, seq: seq} = MarksFixtures.marks_world()
      tick_apc(head)
      {:ok, other} = Curriculum.assign_teacher(head, cg, head.current_user, %{subject: "SVT"})

      assert Assessment.competences_due(head, seq, [tc.id, other.id]) ==
               %{tc.id => nil, other.id => nil}

      :ok = Assessment.put_sequence_competence(t, tc, seq, "Calculer un pourcentage")

      assert Assessment.competences_due(head, seq, [tc.id, other.id]) ==
               %{tc.id => "Calculer un pourcentage", other.id => nil}
    end

    test "nil for a séquence not yet started" do
      %{head: head, tc: tc, year: year} = MarksFixtures.marks_world()
      tick_apc(head)
      [_first, second | _] = TeacherAssistant.Organization.list_sequences(head, year)
      assert Date.after?(second.start_date, TeacherAssistant.Academics.Reference.today())
      assert Assessment.competences_due(head, second, [tc.id]) == nil
    end
  end
end
