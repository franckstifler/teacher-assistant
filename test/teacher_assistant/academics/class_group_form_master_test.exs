defmodule TeacherAssistant.Academics.ClassGroupFormMasterTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Schools

  setup do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, %{name: "Lycée FM"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    %{user: user, cg: cg}
  end

  test "form_master_user_id can be set and cleared", %{user: user, cg: cg} do
    {:ok, cg} =
      cg
      |> Ash.Changeset.for_update(:update, %{form_master_user_id: user.id})
      |> Ash.update(authorize?: false)

    assert cg.form_master_user_id == user.id

    {:ok, cg} =
      cg
      |> Ash.Changeset.for_update(:update, %{form_master_user_id: nil})
      |> Ash.update(authorize?: false)

    assert cg.form_master_user_id == nil
  end

  test "form_master relationship loads the user", %{user: user, cg: cg} do
    {:ok, cg} =
      cg
      |> Ash.Changeset.for_update(:update, %{form_master_user_id: user.id})
      |> Ash.update(authorize?: false)

    cg = Ash.load!(cg, :form_master, authorize?: false)
    assert cg.form_master.id == user.id
  end
end
