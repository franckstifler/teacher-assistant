defmodule TeacherAssistant.Resources.OptionTest do
  use TeacherAssistant.DataCase

  alias TeacherAssistant.Academics.Option

  require Ash.Query

  setup %{tenant: tenant} do
    user = generate(admin_user(tenant: tenant))
    %{user: user}
  end

  describe "TeacherAssistant.Academics.read_options" do
    test "list options", %{tenant: tenant, user: user} do
      option = generate(option(actor: user, tenant: tenant))

      assert [result] = TeacherAssistant.Academics.read_options!(tenant: tenant, actor: user)

      assert result.id == option.id
      assert result.name == option.name
      assert result.description == option.description
    end
  end

  describe "TeacherAssistant.Academics.create_option" do
    test "with valid data creates a option", %{tenant: tenant, user: user} do
      check all(input <- Ash.Generator.action_input(Option, :create)) do
        option =
          TeacherAssistant.Academics.create_option!(input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert option.name == input[:name]
        assert option.description == value_or_nil(input, :description)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.create_option(%{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.update_option" do
    test "updates a option", %{tenant: tenant, user: user} do
      check all(input <- Ash.Generator.action_input(Option, :update)) do
        option = generate(option(tenant: tenant, actor: user))

        updated_option =
          TeacherAssistant.Academics.update_option!(option, input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert updated_option.name == input[:name]
        assert updated_option.description == value_or_nil(input, :description, option.description)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      option = generate(option(tenant: tenant, actor: user))

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.update_option(option, %{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.destroy_option" do
    test "destroys a option", %{tenant: tenant, user: user} do
      option = generate(option(tenant: tenant, actor: user))

      TeacherAssistant.Academics.destroy_option!(option,
        tenant: tenant,
        actor: user,
        authorize?: false
      )

      assert Ash.count!(Option, tenant: tenant, actor: user, authorize?: false) == 0
    end
  end

  describe "policies test" do
    test "read options", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      option = generate(option(tenant: tenant))

      assert TeacherAssistant.Academics.can_read_options?(admin, tenant: tenant, data: option)
      assert TeacherAssistant.Academics.can_read_options?(user, tenant: tenant, data: option)
    end

    test "create option", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))

      assert TeacherAssistant.Academics.can_create_option?(admin, tenant: tenant)
      assert TeacherAssistant.Academics.can_create_option?(user, tenant: tenant)
    end

    test "update option", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      option = generate(option(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_update_option?(admin, option, tenant: tenant)
      assert TeacherAssistant.Academics.can_update_option?(user, option, tenant: tenant)
    end

    test "destroy option", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      option = generate(option(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_destroy_option?(admin, option, tenant: tenant)
      assert TeacherAssistant.Academics.can_destroy_option?(user, option, tenant: tenant)
    end
  end
end
