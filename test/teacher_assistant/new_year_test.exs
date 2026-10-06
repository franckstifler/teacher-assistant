defmodule TeacherAssistant.NewYearTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{
    Councils,
    Curriculum,
    Enrollment,
    NewYear,
    Organization,
    TeacherFixtures
  }

  setup do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, a6} = Enrollment.create_class_group(head, year, %{label: "6ème A", level: "6ème"})
    {:ok, a5} = Enrollment.create_class_group(head, year, %{label: "5ème A", level: "5ème"})

    # The fixture's starter classes already include « Terminale C ».
    tc = Enum.find(Enrollment.list_class_groups(head, year), &(&1.label == "Terminale C"))

    teacher = TeacherFixtures.member_scope_fixture(head)
    {:ok, _} = Enrollment.set_form_master(head, a6, teacher.current_user.id)

    {:ok, maths6} =
      Curriculum.assign_teacher(head, a6, teacher.current_user, %{
        subject: "Maths",
        weekly_hours: 5,
        coefficient: Decimal.new(4)
      })

    {:ok, maths5} = Curriculum.assign_teacher(head, a5, teacher.current_user, %{subject: "Maths"})
    {:ok, _} = Curriculum.combine_course(head, [maths6, maths5])

    {:ok, awa} = Enrollment.add_student(head, a6, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(head, a6, %{full_name: "Bob", sex: :m})
    {:ok, _carl} = Enrollment.add_student(head, a6, %{full_name: "Carl", sex: :m})
    {:ok, dina} = Enrollment.add_student(head, tc, %{full_name: "Dina", sex: :f})

    for {cg, s, d} <- [{a6, awa, "admis"}, {a6, bob, "redouble"}, {tc, dina, "admis"}] do
      {:ok, _} =
        Councils.set_decision(head, cg, {:annual, year}, s.id, %{"passage_decision" => d})
    end

    %{head: head, year: year, a6: a6, a5: a5, tc: tc, teacher: teacher, awa: awa}
  end

  defp attrs(extra \\ %{}) do
    Map.merge(
      %{name: "2026-2027", start_date: ~D[2026-09-07], end_date: ~D[2027-07-30]},
      extra
    )
  end

  defp roster(scope, cg),
    do: scope |> Enrollment.list_roster(cg) |> Map.new(&{&1.student.full_name, &1.enrollment})

  test "the plan proposes targets, reads decisions and lists what to check", ctx do
    plan = NewYear.plan(ctx.head, ctx.year)

    assert plan.default_targets[ctx.a6.id] == ctx.a5.id
    assert plan.default_targets[ctx.tc.id] == nil

    by = Map.new(plan.students, &{&1.name, &1})
    assert %{decision: :admis, source: :council} = by["Awa"]
    assert %{decision: :redouble} = by["Bob"]
    # No decision and no marks, so no proposal either.
    assert %{decision: nil, source: nil} = by["Carl"]

    assert ctx.a6.id in Enum.map(plan.checks.open_councils, & &1.id)
    assert plan.checks.departed_courses == 0
    # The test clock (2025-09-15) is before the year's end.
    assert plan.checks.before_end?
  end

  test "starting the next year carries classes, courses and students over, then closes the old one",
       ctx do
    assert {:ok, new} =
             NewYear.start(ctx.head, ctx.year, attrs(%{labels: %{ctx.a5.id => "5ème A bis"}}))

    {:ok, old} = Organization.get_academic_year(ctx.head, ctx.year.id)
    assert old.status == :closed
    refute old.active
    assert Organization.current_academic_year(ctx.head).id == new.id
    assert length(Organization.list_sequences(ctx.head, new)) == 6

    classes = Map.new(Enrollment.list_class_groups(ctx.head, new), &{&1.label, &1})
    a6n = classes["6ème A"]
    a5n = classes["5ème A bis"]
    tcn = classes["Terminale C"]
    assert a6n.form_master_user_id == ctx.teacher.current_user.id

    [maths] = Curriculum.list_assignments_for_class(ctx.head, a6n)
    assert maths.weekly_hours == 5
    assert Decimal.equal?(maths.coefficient, 4)
    assert maths.teacher_user_id == ctx.teacher.current_user.id
    assert maths.combined_course_id

    assert %{"Awa" => %{status: :reinscription, repeater: false}} = roster(ctx.head, a5n)
    assert %{"Bob" => %{status: :reinscription, repeater: true}} = r6 = roster(ctx.head, a6n)
    refute Map.has_key?(r6, "Carl")
    # Last level: Dina admis has no class to go to.
    assert roster(ctx.head, tcn) == %{}
  end

  test "a failure keeps nothing; a second start is refused", ctx do
    years = length(Organization.list_academic_years(ctx.head))

    # Two classes with the same label: the copy fails, everything is rolled back.
    assert {:error, _} =
             NewYear.start(ctx.head, ctx.year, attrs(%{labels: %{ctx.a5.id => "6ème A"}}))

    assert length(Organization.list_academic_years(ctx.head)) == years

    assert {:ok, %{status: :open, active: true}} =
             Organization.get_academic_year(ctx.head, ctx.year.id)

    assert {:ok, _} = NewYear.start(ctx.head, ctx.year, attrs())

    assert {:error, :already_closed} =
             NewYear.start(ctx.head, ctx.year, attrs(%{name: "2027-2028"}))
  end

  test "a forged target is ignored: the student is simply not re-enrolled", ctx do
    assert {:ok, new} =
             NewYear.start(
               ctx.head,
               ctx.year,
               attrs(%{targets: %{ctx.a6.id => Ecto.UUID.generate(), "garbage" => ctx.a5.id}})
             )

    a5n = Enum.find(Enrollment.list_class_groups(ctx.head, new), &(&1.label == "5ème A"))
    refute Map.has_key?(roster(ctx.head, a5n), "Awa")
  end

  test "a teacher cannot start the next year", ctx do
    assert {:error, :forbidden} = NewYear.start(ctx.teacher, ctx.year, attrs())
    assert {:ok, %{status: :open}} = Organization.get_academic_year(ctx.head, ctx.year.id)
  end
end
