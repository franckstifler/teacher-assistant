defmodule TeacherAssistant.Academics.EntryProgressTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.EntryProgress
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée F"})

    scope = school_scope(head, school)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    seq = scope |> Organization.list_sequences(year) |> List.first()

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e A", level: "3ème"})
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "4e B", level: "4ème"})
    {:ok, empty_cg} = Enrollment.create_class_group(scope, year, %{label: "5e C", level: "5ème"})

    {:ok, s1} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, s3} = Enrollment.add_student(scope, cg, %{full_name: "Carl", sex: :m})
    {:ok, t1} = Enrollment.add_student(scope, cg2, %{full_name: "Dina", sex: :f})

    english_teacher = TeacherFixtures.member_scope_fixture(scope).current_user

    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Curriculum.assign_teacher(scope, empty_cg, head, %{subject: "Maths"})
    {:ok, _} = Curriculum.assign_teacher(scope, cg, english_teacher, %{subject: "Anglais"})
    {:ok, _} = Curriculum.assign_teacher(scope, cg2, english_teacher, %{subject: "Anglais"})
    {:ok, tc_de} = Curriculum.assign_teacher(scope, cg2, head, %{subject: "Allemand"})

    {:ok, a1} = Assessment.create_assessment(scope, tc, seq, %{label: "Interro 1"})
    {:ok, a2} = Assessment.create_assessment(scope, tc, seq, %{label: "Devoir 1"})
    {:ok, de} = Assessment.create_assessment(scope, tc_de, seq, %{label: "Devoir 1"})
    :ok = Assessment.upsert_marks(scope, de, [%{student_id: t1.id, score: Decimal.new(12)}])

    %{
      head: scope,
      year: year,
      seq: seq,
      cg: cg,
      cg2: cg2,
      empty_cg: empty_cg,
      tc: tc,
      a1: a1,
      a2: a2,
      s1: s1,
      s2: s2,
      s3: s3,
      english_teacher: english_teacher
    }
  end

  defp cell(grid, cg, label) do
    %{key: key} = Enum.find(grid.subjects, &(&1.label == label)) || %{key: :missing}
    row = Enum.find(grid.rows, &(&1.class_group.id == cg.id))
    Map.get(row.cells, key)
  end

  defp mark(ctx, assessment, student, entry \\ %{score: Decimal.new(10)}) do
    :ok = Assessment.upsert_marks(ctx.head, assessment, [Map.put(entry, :student_id, student.id)])
  end

  defp make_optional(ctx) do
    :ok =
      Curriculum.update_coefficient_grid(ctx.head, %{
        "optional" => %{ctx.tc.subject_id => "true"}
      })
  end

  defp grid(ctx), do: Assessment.sequence_entry_grid(ctx.head, ctx.year, ctx.seq)

  test "pct = entered / (students taking × assessments), any status counts", ctx do
    mark(ctx, ctx.a1, ctx.s1)
    mark(ctx, ctx.a2, ctx.s1)
    mark(ctx, ctx.a1, ctx.s2, %{status: :absent})

    cell = cell(grid(ctx), ctx.cg, "Maths")
    assert {cell.entered, cell.expected, cell.pct} == {3, 6, 50}
    assert cell.assessments == ["Interro 1", "Devoir 1"]
    assert cell.teacher.id == ctx.head.current_user.id
    assert %DateTime{} = cell.last_entry_at
  end

  test "exempted students are not expected", ctx do
    make_optional(ctx)
    :ok = Curriculum.set_exemptions(ctx.head, ctx.tc, [ctx.s1.id, ctx.s2.id])

    for a <- [ctx.a1, ctx.a2], s <- [ctx.s1, ctx.s2], do: mark(ctx, a, s)

    cell = cell(grid(ctx), ctx.cg, "Maths")
    assert {cell.entered, cell.expected, cell.pct} == {4, 4, 100}
  end

  test "a mark of a student not taking the course is not counted", ctx do
    for a <- [ctx.a1, ctx.a2], s <- [ctx.s1, ctx.s2, ctx.s3], do: mark(ctx, a, s)

    # s3 moves to 4e B: their Maths marks in 3e A stay but no longer count.
    [%{enrollment: e3}] =
      ctx.head |> Enrollment.list_roster(ctx.cg) |> Enum.filter(&(&1.student.id == ctx.s3.id))

    {:ok, _} = Enrollment.transfer(ctx.head, e3, ctx.cg2)

    cell = cell(grid(ctx), ctx.cg, "Maths")
    assert {cell.entered, cell.expected, cell.pct} == {4, 4, 100}
  end

  test "no assessment = 0 %, no course = nil cell, empty class = nil pct", ctx do
    grid = grid(ctx)
    assert cell(grid, ctx.cg, "Anglais").pct == 0
    assert cell(grid, ctx.cg, "Allemand") == nil
    assert cell(grid, ctx.cg2, "Allemand").pct == 100
    assert cell(grid, ctx.empty_cg, "Maths").pct == nil
    assert cell(grid, ctx.empty_cg, "Maths").expected == 0
  end

  test "pct rounds down: 119/120 is 99" do
    assert EntryProgress.pct(119, 120) == 99
    assert EntryProgress.pct(0, 0) == nil
  end

  test "KPIs: complete classes, late teachers grouped with their classes", ctx do
    mark(ctx, ctx.a1, ctx.s1)
    mark(ctx, ctx.a2, ctx.s1)
    mark(ctx, ctx.a1, ctx.s2, %{status: :absent})

    grid = grid(ctx)
    assert Enum.map(grid.subjects, & &1.label) |> Enum.sort() == ["Allemand", "Anglais", "Maths"]
    assert Enum.map(grid.rows, & &1.class_group.label) == ["3e A", "4e B", "5e C"]
    # 3e A: Maths 50, Anglais 0; 4e B: Anglais 0, Allemand 100; 5e C: nil (no students)
    assert grid.complete_classes == {0, 3}
    teacher_id = ctx.english_teacher.id

    assert [%{teacher: %{id: ^teacher_id}, subject: "Anglais", classes: ["3e A", "4e B"]}] =
             grid.late

    assert grid.overall_pct == div(50 + 0 + 0 + 100, 4)
    assert grid.council_date == nil
  end

  test "council date is the séquence's term class council date", ctx do
    date = Date.add(ctx.seq.end_date, 7)

    {:ok, _} =
      ctx.seq.term
      |> Ash.Changeset.for_update(:update, %{class_council_date: date}, scope: ctx.head)
      |> Ash.update()

    unloaded = %{ctx.seq | term: %Ash.NotLoaded{field: :term, type: :relationship}}
    assert Assessment.sequence_entry_grid(ctx.head, ctx.year, unloaded).council_date == date
  end

  test "a class whose every course is complete counts as complete", ctx do
    {:ok, cg} = Enrollment.create_class_group(ctx.head, ctx.year, %{label: "6e A", level: "6ème"})
    {:ok, s} = Enrollment.add_student(ctx.head, cg, %{full_name: "Eva", sex: :f})

    {:ok, tc} =
      Curriculum.assign_teacher(ctx.head, cg, ctx.head.current_user, %{subject: "Maths"})

    {:ok, a} = Assessment.create_assessment(ctx.head, tc, ctx.seq, %{label: "Devoir 1"})
    mark(ctx, a, s)

    assert grid(ctx).complete_classes == {1, 4}
  end

  test "the number of queries does not grow with the number of classes", ctx do
    before = count_queries(fn -> grid(ctx) end)

    for n <- 1..3 do
      {:ok, cg} =
        Enrollment.create_class_group(ctx.head, ctx.year, %{label: "2nde #{n}", level: "2nde"})

      {:ok, s} = Enrollment.add_student(ctx.head, cg, %{full_name: "S#{n}", sex: :f})

      {:ok, tc} =
        Curriculum.assign_teacher(ctx.head, cg, ctx.head.current_user, %{subject: "Maths"})

      {:ok, a} = Assessment.create_assessment(ctx.head, tc, ctx.seq, %{label: "D"})
      mark(ctx, a, s)
    end

    assert count_queries(fn -> grid(ctx) end) == before
  end

  test "default_sequence picks the current, else last started, else first" do
    seqs = [seq(~D[2026-09-07], ~D[2026-10-02]), seq(~D[2026-10-05], ~D[2026-11-06])]
    assert Assessment.default_sequence(seqs, ~D[2026-09-20]) == hd(seqs)
    assert Assessment.default_sequence(seqs, ~D[2026-10-03]) == hd(seqs)
    assert Assessment.default_sequence(seqs, ~D[2026-10-10]) == List.last(seqs)
    assert Assessment.default_sequence(seqs, ~D[2026-12-10]) == List.last(seqs)
    assert Assessment.default_sequence(seqs, ~D[2026-08-01]) == hd(seqs)
    assert Assessment.default_sequence([], ~D[2026-08-01]) == nil
  end

  defp seq(from, to),
    do: %TeacherAssistant.Academics.Sequence{
      start_date: from,
      end_date: to,
      id: Ecto.UUID.generate()
    }

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    handler = "entry-progress-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:teacher_assistant, :repo, :query],
      fn _event, _measurements, _meta, _ ->
        if self() == parent, do: send(parent, {ref, :query})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    drain(ref, 0)
  end

  defp drain(ref, n) do
    receive do
      {^ref, :query} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end
end
