defmodule TeacherAssistant.Academics.OfficialHeaderTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Academics.{BulletinElement, BulletinTemplate}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    %{scope: scope}
  end

  test "saved lines replace the generated ones; nil brings them back", %{scope: scope} do
    header = %{region: nil, department: nil}
    assert hd(BulletinTemplate.official_lines(header)) == "République du Cameroun"

    assert {:ok, _} =
             Accounts.update_official_header(scope, %{official_header_lines: ["République du Cameroun", "Délégation X"]})

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == ["République du Cameroun", "Délégation X"]
    assert BulletinTemplate.official_lines(Map.put(header, :official_lines, profile.official_header_lines)) ==
             ["République du Cameroun", "Délégation X"]

    assert {:ok, _} = Accounts.update_official_header(scope, %{official_header_lines: nil})
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == nil
  end

  test "at most six lines of 120 characters", %{scope: scope} do
    assert {:error, _} = Accounts.update_official_header(scope, %{official_header_lines: List.duplicate("x", 7)})
    assert {:error, _} = Accounts.update_official_header(scope, %{official_header_lines: [String.duplicate("x", 121)]})
  end

  test "only the head may change the header or the images", %{scope: scope} do
    censeur = member_scope_fixture(scope, %{roles: [:vice_principal]})
    refute Accounts.can_edit_official_header?(censeur)
    assert Accounts.can_edit_official_header?(scope)
    assert_forbidden(Accounts.update_official_header(censeur, %{signature_path: "x.png"}))
  end

  test "signature and stamp are bulletin elements on by default" do
    assert :signature in BulletinElement.defaults()
    assert :stamp in BulletinElement.defaults()
  end
end
