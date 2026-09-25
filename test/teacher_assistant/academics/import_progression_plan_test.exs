defmodule TeacherAssistant.Academics.ImportProgressionPlanTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head
      })

    %{ws: ws, ctx: ctx}
  end

  defp rows do
    [
      %{
        module: "Algèbre",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson,
        week_no: 1,
        sequence_no: nil
      },
      %{
        module: "Algèbre",
        lesson_title: "Évaluation",
        planned_hours: Decimal.new("1"),
        entry_type: :evaluation,
        week_no: 2,
        sequence_no: nil
      }
    ]
  end

  test "creates a draft plan with entries in order", %{ws: ws, ctx: ctx} do
    assert {:ok, plan} =
             Curriculum.import_progression_plan(
               ws,
               %{teaching_context_id: ctx.id, title: "Imported"},
               rows()
             )

    assert plan.title == "Imported"
    assert plan.status == :draft
    entries = Curriculum.list_progression_entries!(plan.id, tenant: ws.id)
    assert Enum.map(entries, & &1.lesson_title) == ["Les entiers", "Évaluation"]
    assert Enum.map(entries, & &1.position) == [1, 2]
    assert Enum.at(entries, 1).entry_type == :evaluation
  end

  test "rolls back entirely when a row is invalid (no orphan plan)", %{ws: ws, ctx: ctx} do
    bad =
      rows() ++
        [
          %{
            module: "X",
            lesson_title: nil,
            planned_hours: Decimal.new("1"),
            entry_type: :lesson,
            week_no: nil,
            sequence_no: nil
          }
        ]

    assert {:error, _} =
             Curriculum.import_progression_plan(
               ws,
               %{teaching_context_id: ctx.id, title: "Bad"},
               bad
             )

    assert Curriculum.list_progression_plans!(tenant: ws.id) == []
  end

  test "import creates modules from row order and links entries", %{ws: ws, ctx: ctx} do
    rows = [
      %{module: "M1", lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson},
      %{module: "M1", lesson_title: "L2", planned_hours: Decimal.new("2"), entry_type: :lesson},
      %{
        module: "",
        lesson_title: "Prise de contact",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      },
      %{module: "M2", lesson_title: "L3", planned_hours: Decimal.new("2"), entry_type: :lesson}
    ]

    {:ok, plan} =
      Curriculum.import_progression_plan(ws, %{title: "T", teaching_context_id: ctx.id}, rows)

    mods = Curriculum.list_progression_modules!(plan.id, tenant: ws.id)
    assert Enum.map(mods, & &1.title) == ["M1", "Général", "M2"]
    assert Enum.map(hd(mods).entries, & &1.lesson_title) == ["L1", "L2"]

    assert Enum.any?(
             mods,
             &(&1.default? and
                 Enum.map(&1.entries, fn e -> e.lesson_title end) == ["Prise de contact"])
           )
  end

  test "rejects a teaching context owned by another workspace", %{ws: ws} do
    %{head_user: other_head, year: other_year, scope: other_scope} =
      TeacherFixtures.setup_complete_school_fixture()

    other_ctx =
      TeacherFixtures.assigned_context_fixture(other_scope, other_year, %{
        subject: "Physics",
        level: "6ème",
        teacher: other_head
      })

    assert {:error, :not_found} =
             Curriculum.import_progression_plan(
               ws,
               %{teaching_context_id: other_ctx.id, title: "Nope"},
               rows()
             )
  end
end
