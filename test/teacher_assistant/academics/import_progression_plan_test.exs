defmodule TeacherAssistant.Academics.ImportProgressionPlanTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
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
             Academics.import_progression_plan(
               ws,
               %{teaching_context_id: ctx.id, title: "Imported"},
               rows()
             )

    assert plan.title == "Imported"
    assert plan.status == :draft
    entries = Academics.list_progression_entries(plan)
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
             Academics.import_progression_plan(
               ws,
               %{teaching_context_id: ctx.id, title: "Bad"},
               bad
             )

    assert Academics.list_progression_plans(ws) == []
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
      Academics.import_progression_plan(ws, %{title: "T", teaching_context_id: ctx.id}, rows)

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M1", "Général", "M2"]
    assert Enum.map(hd(mods).entries, & &1.lesson_title) == ["L1", "L2"]

    assert Enum.any?(
             mods,
             &(&1.default? and
                 Enum.map(&1.entries, fn e -> e.lesson_title end) == ["Prise de contact"])
           )
  end

  test "rejects a teaching context owned by another workspace", %{ws: ws} do
    other_ws = Academics.ensure_personal_workspace!(TeacherFixtures.user_fixture())

    {:ok, other_year} =
      Academics.create_academic_year(other_ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, other_ctx} =
      Academics.create_teaching_context(other_ws, other_year, %{
        subject: "Physics",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 3
      })

    assert {:error, :not_found} =
             Academics.import_progression_plan(
               ws,
               %{teaching_context_id: other_ctx.id, title: "Nope"},
               rows()
             )
  end
end
