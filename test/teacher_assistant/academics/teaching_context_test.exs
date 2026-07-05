defmodule TeacherAssistant.Academics.TeachingContextTest do
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

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    %{user: user, ws: ws, year: year, cg: cg}
  end

  test "two personal contexts with same subject/level collide", %{ws: ws, year: year} do
    attrs = %{subject: "Maths", level: "6ème", subsystem: :francophone}
    {:ok, _} = Academics.create_teaching_context(ws, year, attrs)
    assert {:error, _} = Academics.create_teaching_context(ws, year, attrs)
  end

  test "two teachers can hold the same subject/level on different classes", ctx do
    %{ws: ws, year: year, cg: cg, user: u1} = ctx
    u2 = TeacherFixtures.user_fixture()
    {:ok, cg2} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})

    base = %{subject: "Maths", level: "6ème", subsystem: :francophone}

    {:ok, _} =
      Academics.create_teaching_context(
        ws,
        year,
        base |> Map.put(:teacher_user_id, u1.id) |> Map.put(:class_group_id, cg.id)
      )

    {:ok, _} =
      Academics.create_teaching_context(
        ws,
        year,
        base |> Map.put(:teacher_user_id, u2.id) |> Map.put(:class_group_id, cg2.id)
      )
  end

  test "one teacher per subject per class", ctx do
    %{ws: ws, year: year, cg: cg, user: u1} = ctx
    u2 = TeacherFixtures.user_fixture()

    base = %{
      subject: "Maths",
      level: "6ème",
      subsystem: :francophone,
      class_group_id: cg.id
    }

    {:ok, _} =
      Academics.create_teaching_context(ws, year, Map.put(base, :teacher_user_id, u1.id))

    assert {:error, _} =
             Academics.create_teaching_context(ws, year, Map.put(base, :teacher_user_id, u2.id))
  end
end
