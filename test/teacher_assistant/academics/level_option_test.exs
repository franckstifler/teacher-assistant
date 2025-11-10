defmodule TeacherAssistant.Resources.LevelOptionTest do
  use TeacherAssistant.DataCase

  require Ash.Query

  setup %{tenant: tenant} do
    user = generate(admin_user(tenant: tenant))
    %{user: user}
  end

  describe "TeacherAssistant.Academics.read_levels_level_options" do
    test "list levels_level_options", %{tenant: tenant, user: user} do
      level_option = generate(level_option(actor: user, tenant: tenant))
      level_option = Ash.load!(level_option, [:full_name])

      assert [result] =
               TeacherAssistant.Academics.read_levels_level_options!(
                 load: [:full_name],
                 tenant: tenant,
                 actor: user
               )

      assert result.id == level_option.id
      assert result.full_name == level_option.full_name
    end
  end

  describe "TeacherAssistant.Academics.manage_level_option_subjects" do
    test "updates a level_option", %{tenant: tenant, user: user} do
      check all(
              coefficient_1 <- StreamData.integer(1..100),
              coefficient_2 <- StreamData.integer(1..100)
            ) do
        level_option = generate(level_option(tenant: tenant, actor: user))
        [subject_1, subject_2] = generate_many(subject(tenant: tenant), 2)

        input = %{
          subjects: [
            %{
              subject_id: subject_1.id,
              coefficient: coefficient_1
            },
            %{
              subject_id: subject_2.id,
              coefficient: coefficient_2
            }
          ]
        }

        updated_level_option =
          TeacherAssistant.Academics.manage_level_option_subjects!(level_option, input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert [sub_1, sub_2] = updated_level_option.subjects
        assert sub_1.subject_id == subject_1.id
        assert sub_1.coefficient == coefficient_1

        assert sub_2.subject_id == subject_2.id
        assert sub_2.coefficient == coefficient_2
      end
    end
  end

  describe "policies test" do
    test "read levels_level_options", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      level_option = generate(level_option(tenant: tenant))

      assert TeacherAssistant.Academics.can_read_levels_level_options?(admin,
               tenant: tenant,
               data: level_option
             )

      assert TeacherAssistant.Academics.can_read_levels_level_options?(user,
               tenant: tenant,
               data: level_option
             )
    end

    test "manage_subjects level_option subjects", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      level_option = generate(level_option(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_manage_level_option_subjects?(admin, level_option,
               tenant: tenant
             )

      assert TeacherAssistant.Academics.can_manage_level_option_subjects?(user, level_option,
               tenant: tenant
             )
    end

    test "destroy level_option", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      level_option = generate(level_option(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_destroy_level_option?(admin, level_option,
               tenant: tenant
             )

      assert TeacherAssistant.Academics.can_destroy_level_option?(user, level_option,
               tenant: tenant
             )
    end
  end
end
