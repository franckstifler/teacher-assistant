defmodule TeacherAssistant.Academics.GuardianTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Academics.{Guardian, StudentGuardian}
  alias TeacherAssistant.Academics.Guardian.Phone
  alias TeacherAssistant.{Enrollment, Organization}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Nkolo", sex: :f})
    %{scope: scope, cg: cg, awa: awa}
  end

  defp create_guardian(scope, attrs) do
    Guardian
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{full_name: "Jean Nkolo", relationship: :pere, phone: "677 12 34 56"}, attrs),
      scope: scope
    )
    |> Ash.create()
  end

  describe "Phone.key/1" do
    test "keeps digits and drops the Cameroon prefix" do
      assert Phone.key("+237 6 77 12 34 56") == "677123456"
      assert Phone.key("00237677123456") == "677123456"
      assert Phone.key("677-12-34-56") == "677123456"
      assert Phone.key("237") == "237"
      assert Phone.key(nil) == nil
    end
  end

  test "a guardian stores a phone key and refuses a short number", %{scope: scope} do
    assert {:ok, g} = create_guardian(scope, %{phone: "+237 677 12 34 56"})
    assert g.phone_key == "677123456"
    assert g.language == :fr

    assert {:error, %Ash.Error.Invalid{}} = create_guardian(scope, %{phone: "12 34"})
  end

  test "the student gains an optional date and place of birth", %{scope: scope, awa: awa} do
    {:ok, awa} =
      Enrollment.update_student(awa, %{birth_date: ~D[2013-04-02], birth_place: "Yaoundé"},
        scope: scope
      )

    assert awa.birth_date == ~D[2013-04-02]
    assert awa.birth_place == "Yaoundé"

    assert {:error, %Ash.Error.Invalid{}} =
             Enrollment.update_student(awa, %{birth_date: ~D[2099-01-01]}, scope: scope)
  end

  test "the first link becomes the main contact; the partial index forbids a second", %{
    scope: scope,
    awa: awa
  } do
    {:ok, g1} = create_guardian(scope, %{})
    {:ok, g2} = create_guardian(scope, %{full_name: "Marie Nkolo", relationship: :mere, phone: "699 00 00 01"})

    link = fn g ->
      StudentGuardian
      |> Ash.Changeset.for_create(:link, %{student_id: awa.id, guardian_id: g.id}, scope: scope)
      |> Ash.create()
    end

    assert {:ok, %{primary_contact: true}} = link.(g1)
    assert {:ok, %{primary_contact: false}} = link.(g2)
    assert {:error, _} = link.(g1)

    assert {:error, _} =
             StudentGuardian
             |> Ash.Changeset.for_create(:create, %{
               student_id: awa.id,
               guardian_id: g2.id,
               primary_contact: true
             })
             |> Ash.create(scope: scope, authorize?: false)
  end

  test "a plain teacher with no class of the student cannot read or write guardians", %{
    scope: scope,
    awa: awa
  } do
    {:ok, g} = create_guardian(scope, %{})

    {:ok, _} =
      StudentGuardian
      |> Ash.Changeset.for_create(:link, %{student_id: awa.id, guardian_id: g.id}, scope: scope)
      |> Ash.create()

    stranger = member_scope_fixture(scope, %{roles: [:teacher]})

    assert Ash.read!(Guardian, scope: stranger) == []
    assert Ash.read!(StudentGuardian, scope: stranger) == []
    assert_forbidden(create_guardian(stranger, %{phone: "699 11 22 33"}))
  end

  test "the student's form master reads them; the SG writes them", %{scope: scope, cg: cg, awa: awa} do
    {:ok, g} = create_guardian(scope, %{})

    {:ok, _} =
      StudentGuardian
      |> Ash.Changeset.for_create(:link, %{student_id: awa.id, guardian_id: g.id}, scope: scope)
      |> Ash.create()

    master = member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(scope, cg, master.current_user.id)
    assert [%{id: id}] = Ash.read!(Guardian, scope: master)
    assert id == g.id

    sg = member_scope_fixture(scope, %{roles: [:discipline_master]})
    assert {:ok, _} = create_guardian(sg, %{phone: "699 11 22 33"})
  end
end
