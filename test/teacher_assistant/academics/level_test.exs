defmodule TeacherAssistant.Resources.LevelTest do
  use TeacherAssistant.DataCase

  alias TeacherAssistant.Academics.Level

  require Ash.Query

  setup %{tenant: tenant} do
    user = generate(admin_user(tenant: tenant))
    %{user: user}
  end

  describe "TeacherAssistant.Academics.read_levels" do
    test "list levels", %{tenant: tenant, user: user} do
      level = generate(level(actor: user, tenant: tenant))

      assert [result] = TeacherAssistant.Academics.read_levels!(tenant: tenant, actor: user)

      assert result.id == level.id
      assert result.name == level.name
      assert result.description == level.description
    end
  end

  describe "TeacherAssistant.Academics.create_level" do
    test "with valid data creates a level", %{tenant: tenant, user: user} do
      check all(input <- Ash.Generator.action_input(Level, :create)) do
        level =
          TeacherAssistant.Academics.create_level!(input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert level.name == input[:name]
        assert level.description == value_or_nil(input, :description)
      end
    end

    test "with valid data creates a level with options", %{tenant: tenant, user: user} do
      check all(
              input <- Ash.Generator.action_input(Level, :create),
              options <- StreamData.repeatedly(fn -> generate_many(option(tenant: tenant), 2) end)
            ) do
        input = Map.put(input, :option_ids, Enum.map(options, & &1.id))

        level =
          TeacherAssistant.Academics.create_level!(input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert level.name == input[:name]
        assert level.description == value_or_nil(input, :description)
        assert Enum.count(level.options) == length(options)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.create_level(%{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.update_level" do
    test "updates a level", %{tenant: tenant, user: user} do
      check all(
              input <- Ash.Generator.action_input(Level, :update),
              option <-
                StreamData.repeatedly(fn ->
                  generate(option(tenant: tenant, actor: user))
                end),
              level <-
                StreamData.repeatedly(fn ->
                  generate(level(option_ids: [option.id], tenant: tenant, actor: user))
                end)
            ) do
        new_option = generate(option(tenant: tenant, actor: user))

        input = Map.put(input, :option_ids, [new_option.id])

        updated_level =
          TeacherAssistant.Academics.update_level!(level, input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert updated_level.name == input[:name]
        assert updated_level.description == value_or_nil(input, :description, level.description)

        updated_option_ids = Enum.map(updated_level.options, & &1.id)
        refute option.id in updated_option_ids
        assert new_option.id in updated_option_ids
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      level = generate(level(tenant: tenant, actor: user))

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.update_level(level, %{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.destroy_level" do
    test "destroys a level", %{tenant: tenant, user: user} do
      level = generate(level(tenant: tenant, actor: user))

      TeacherAssistant.Academics.destroy_level!(level,
        tenant: tenant,
        actor: user,
        authorize?: false
      )

      assert Ash.count!(Level, tenant: tenant, actor: user, authorize?: false) == 0
    end
  end

  describe "policies test" do
    test "read levels", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      level = generate(level(tenant: tenant))

      assert TeacherAssistant.Academics.can_read_levels?(admin, tenant: tenant, data: level)
      assert TeacherAssistant.Academics.can_read_levels?(user, tenant: tenant, data: level)
    end

    test "create level", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))

      assert TeacherAssistant.Academics.can_create_level?(admin, tenant: tenant)
      assert TeacherAssistant.Academics.can_create_level?(user, tenant: tenant)
    end

    test "update level", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      level = generate(level(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_update_level?(admin, level, tenant: tenant)
      assert TeacherAssistant.Academics.can_update_level?(user, level, tenant: tenant)
    end

    test "destroy level", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      level = generate(level(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_destroy_level?(admin, level, tenant: tenant)
      assert TeacherAssistant.Academics.can_destroy_level?(user, level, tenant: tenant)
    end
  end
end
