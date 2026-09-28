defmodule TeacherAssistant.Academics.SubjectCoefficientTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.{SchoolTemplates, SubjectCoefficient}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    %{scope: scope}
  end

  test "a new subject is taught at every level of the school, at its default coefficient",
       %{scope: scope} do
    {:ok, s} =
      Curriculum.create_subject(scope, %{name: "Musique", default_coefficient: Decimal.new(2)})

    cells =
      scope
      |> Curriculum.coefficient_cells()
      |> Map.values()
      |> Enum.filter(&(&1.subject_id == s.id))

    assert Enum.map(cells, & &1.level) |> Enum.sort() ==
             Enum.sort(~w(6ème 5ème 4ème 3ème 2nde 1ère Terminale))

    assert Enum.all?(cells, &(&1.subsystem == :francophone and is_nil(&1.serie)))
    assert Enum.all?(cells, &Decimal.equal?(&1.coefficient, Decimal.new(2)))
  end

  test "the seeded catalog gets its cells at school creation", %{scope: scope} do
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

    assert %SubjectCoefficient{} =
             Curriculum.coefficient_cells(scope)[{maths.id, :francophone, "2nde", nil}]
  end

  test "one cell per subject, subsystem, level and série, blank série included", %{scope: scope} do
    {:ok, s} = Curriculum.create_subject(scope, %{name: "Musique"})

    assert {:error, %Ash.Error.Invalid{}} =
             SubjectCoefficient
             |> Ash.Changeset.for_create(
               :create,
               %{
                 subject_id: s.id,
                 subsystem: :francophone,
                 level: "6ème",
                 serie: nil,
                 coefficient: 1
               },
               scope: scope
             )
             |> Ash.create()
  end

  test "a coefficient must be positive", %{scope: scope} do
    {:ok, s} = Curriculum.create_subject(scope, %{name: "Musique"})

    assert {:error, %Ash.Error.Invalid{}} =
             SubjectCoefficient
             |> Ash.Changeset.for_create(
               :create,
               %{
                 subject_id: s.id,
                 subsystem: :francophone,
                 level: "2nde",
                 serie: "C",
                 coefficient: 0
               },
               scope: scope
             )
             |> Ash.create()
  end

  test "a bilingual school edits both subsystems" do
    assert SchoolTemplates.grid_subsystems(:bilingual) == [:francophone, :anglophone]
    assert SchoolTemplates.grid_subsystems(:anglophone) == [:anglophone]
  end
end
