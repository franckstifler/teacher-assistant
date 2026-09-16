defmodule TeacherAssistant.Accounts.SchoolProfileTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Workspace
      |> Ash.Changeset.for_create(:create, %{name: "Lycée X", kind: :school})
      |> Ash.create(authorize?: false)

    %{user: user, ws: ws}
  end

  defp create(ws, user, extra \\ %{}) do
    SchoolProfile
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          workspace_id: ws.id,
          owner_user_id: user.id,
          school_type: :lycee,
          subsystem: :francophone,
          sector: :public,
          region: :centre,
          town: "Yaoundé"
        },
        extra
      )
    )
    |> Ash.create(authorize?: false)
  end

  test "creates unverified by default", %{ws: ws, user: user} do
    assert {:ok, p} = create(ws, user)
    assert p.verification_status == :unverified
    assert p.owner_user_id == user.id
  end

  test "enforces one profile per workspace", %{ws: ws, user: user} do
    assert {:ok, _} = create(ws, user)
    assert {:error, _} = create(ws, user)
  end

  test "verify sets status, timestamp and verifier", %{ws: ws, user: user} do
    {:ok, p} = create(ws, user)
    op = TeacherFixtures.user_fixture()

    {:ok, p} =
      p
      |> Ash.Changeset.for_update(:verify, %{verified_by_user_id: op.id})
      |> Ash.update(authorize?: false)

    assert p.verification_status == :verified
    assert p.verified_at
    assert p.verified_by_user_id == op.id
  end

  test "reject records a reason", %{ws: ws, user: user} do
    {:ok, p} = create(ws, user)
    op = TeacherFixtures.user_fixture()

    {:ok, p} =
      p
      |> Ash.Changeset.for_update(:reject, %{
        verified_by_user_id: op.id,
        rejection_reason: "Nom incomplet"
      })
      |> Ash.update(authorize?: false)

    assert p.verification_status == :rejected
    assert p.rejection_reason == "Nom incomplet"
  end
end
