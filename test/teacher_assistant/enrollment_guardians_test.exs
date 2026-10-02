defmodule TeacherAssistant.EnrollmentGuardiansTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Organization}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Nkolo", sex: :f})
    {:ok, paul} = Enrollment.add_student(scope, cg, %{full_name: "Paul Nkolo", sex: :m})
    %{scope: scope, awa: awa, paul: paul}
  end

  @father %{full_name: "Jean Nkolo", relationship: :pere, phone: "+237 6 77 12 34 56"}

  test "a sibling's parent is found by phone whatever the formatting", %{
    scope: scope,
    awa: awa,
    paul: paul
  } do
    {:ok, jean} = Enrollment.add_guardian(scope, awa, @father)

    assert [%{id: id}] = Enrollment.find_guardians_by_phone(scope, "677123456")
    assert id == jean.id
    assert Enrollment.find_guardians_by_phone(scope, "12") == []

    assert {:ok, link} = Enrollment.link_guardian(scope, paul, jean)
    assert link.primary_contact
    assert {:error, :already_linked} = Enrollment.link_guardian(scope, paul, jean)
  end

  test "making another guardian the main contact unsets the previous one", %{scope: scope, awa: awa} do
    {:ok, _} = Enrollment.add_guardian(scope, awa, @father)

    {:ok, _} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Marie Nkolo",
        relationship: :mere,
        phone: "699 00 00 01"
      })

    [first, second] = Enrollment.list_guardian_links(scope, awa)
    assert first.primary_contact and first.guardian.full_name == "Jean Nkolo"
    refute second.primary_contact

    assert {:ok, _} = Enrollment.make_primary_guardian(scope, second)

    assert [%{guardian: %{full_name: "Marie Nkolo"}, primary_contact: true}, %{primary_contact: false}] =
             Enrollment.list_guardian_links(scope, awa)
  end

  test "unlinking keeps a guardian shared by a sibling and deletes an orphan", %{
    scope: scope,
    awa: awa,
    paul: paul
  } do
    {:ok, jean} = Enrollment.add_guardian(scope, awa, @father)
    {:ok, _} = Enrollment.link_guardian(scope, paul, jean)

    [awa_link] = Enrollment.list_guardian_links(scope, awa)
    assert :ok = Enrollment.unlink_guardian(scope, awa_link)
    assert Enrollment.list_guardian_links(scope, awa) == []
    assert [%{guardian: %{id: id}}] = Enrollment.list_guardian_links(scope, paul)
    assert id == jean.id

    [paul_link] = Enrollment.list_guardian_links(scope, paul)
    assert :ok = Enrollment.unlink_guardian(scope, paul_link)
    assert Enrollment.find_guardians_by_phone(scope, "677123456") == []
  end

  test "a refused or invalid add leaves nothing behind", %{scope: scope, awa: awa} do
    assert {:error, _} = Enrollment.add_guardian(scope, awa, %{@father | phone: "12"})
    assert Enrollment.list_guardian_links(scope, awa) == []

    teacher = member_scope_fixture(scope, %{roles: [:teacher]})
    assert_forbidden(Enrollment.add_guardian(teacher, awa, @father))
    assert Enrollment.find_guardians_by_phone(scope, "677123456") == []
  end

  test "can_manage_register? is true for admins and the SG only", %{scope: scope} do
    assert Enrollment.can_manage_register?(scope)
    assert Enrollment.can_manage_register?(member_scope_fixture(scope, %{roles: [:discipline_master]}))
    refute Enrollment.can_manage_register?(member_scope_fixture(scope, %{roles: [:teacher]}))
  end
end
