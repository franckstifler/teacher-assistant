defmodule TeacherAssistant.Academics.ClassSizeTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Accounts, Enrollment, Organization}
  alias TeacherAssistant.Academics.SchoolTemplates

  describe "next_class_label/3" do
    test "letters take the first free one" do
      assert SchoolTemplates.next_class_label("6ème", ["6ème A", "6ème C", "5ème B"], :letters) ==
               "6ème B"

      assert SchoolTemplates.next_class_label("6ème", [], :letters) == "6ème A"
      assert SchoolTemplates.next_class_label("2nde C", ["2nde C A"], :letters) == "2nde C B"
    end

    test "numbers do the same" do
      assert SchoolTemplates.next_class_label("6ème", ["6ème 1", "6ème 2"], :numbers) == "6ème 3"
    end
  end

  test "the class's enrolment count is one aggregate; the profile holds the limit and the rule" do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})

    [first | _] = Enrollment.list_class_groups(scope, year, load: [:enrollment_count])
    assert first.id == cg.id
    assert first.enrollment_count == 2

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.max_class_size == nil
    assert profile.class_suffix == :letters

    {:ok, profile} =
      Accounts.update_school_profile(profile, %{max_class_size: 60, class_suffix: :numbers},
        scope: scope
      )

    assert profile.max_class_size == 60

    assert {:error, _} =
             Accounts.update_school_profile(profile, %{max_class_size: 0}, scope: scope)
  end

  describe "capacity/2" do
    setup do
      %{scope: scope} = setup_complete_school_fixture()
      year = Organization.current_academic_year(scope)
      [cg | _] = Enrollment.list_class_groups(scope, year)
      {:ok, profile} = Accounts.fetch_school_profile(scope)

      for n <- 1..9,
          do: {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "S#{n}", sex: :f})

      %{scope: scope, cg: cg, profile: profile}
    end

    test "falls back to the school's maximum", %{scope: scope, cg: cg, profile: profile} do
      {:ok, _} = Accounts.update_school_profile(profile, %{max_class_size: 20}, scope: scope)
      assert %{count: 9, max: 20, over?: false, near?: false} = Enrollment.capacity(scope, cg)
    end

    test "the class's own maximum wins", %{scope: scope, cg: cg, profile: profile} do
      {:ok, _} = Accounts.update_school_profile(profile, %{max_class_size: 20}, scope: scope)
      {:ok, cg} = Ash.update(cg, %{max_size: 10}, scope: scope)
      assert %{count: 9, max: 10, over?: false, near?: true} = Enrollment.capacity(scope, cg)

      {:ok, cg} = Ash.update(cg, %{max_size: 8}, scope: scope)
      assert %{max: 8, over?: true, near?: false} = Enrollment.capacity(scope, cg)
    end

    test "no maximum anywhere means no warning", %{scope: scope, cg: cg} do
      assert %{max: nil, over?: false, near?: false} = Enrollment.capacity(scope, cg)
    end
  end
end
