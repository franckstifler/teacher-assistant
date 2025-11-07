defmodule TeacherAssistant.Resources.SubjectTest do
  use TeacherAssistant.DataCase

  alias TeacherAssistant.Academics.Subject

  require Ash.Query

  setup %{tenant: tenant} do
    user = generate(admin_user(tenant: tenant))
    %{user: user}
  end

  describe "TeacherAssistant.Academics.read_subjects" do
    test "list subjects", %{tenant: tenant, user: user} do
      subject = generate(subject(actor: user, tenant: tenant))

      assert [result] = TeacherAssistant.Academics.read_subjects!(tenant: tenant, actor: user)

      assert result.id == subject.id
      assert result.name == subject.name
      assert result.default_coefficient == subject.default_coefficient
      assert result.description == subject.description
    end
  end

  describe "TeacherAssistant.Academics.create_subject" do
    test "with valid data creates a subject", %{tenant: tenant, user: user} do
      check all(input <- Ash.Generator.action_input(Subject, :create)) do
        subject =
          TeacherAssistant.Academics.create_subject!(input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert subject.name == input[:name]
        assert subject.default_coefficient == value_or_nil(input, :default_coefficient, 1)
        assert subject.description == value_or_nil(input, :description)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.create_subject(%{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.update_subject" do
    test "updates a subject", %{tenant: tenant, user: user} do
      check all(input <- Ash.Generator.action_input(Subject, :update)) do
        subject = generate(subject(tenant: tenant, actor: user))

        updated_subject =
          TeacherAssistant.Academics.update_subject!(subject, input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert updated_subject.name == input[:name]

        assert updated_subject.default_coefficient ==
                 value_or_nil(input, :default_coefficient, subject.default_coefficient)

        assert updated_subject.description ==
                 value_or_nil(input, :description, subject.description)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      subject = generate(subject(tenant: tenant, actor: user))

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.update_subject(subject, %{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.destroy_subject" do
    test "destroys a subject", %{tenant: tenant, user: user} do
      subject = generate(subject(tenant: tenant, actor: user))

      TeacherAssistant.Academics.destroy_subject!(subject,
        tenant: tenant,
        actor: user,
        authorize?: false
      )

      assert Ash.count!(Subject, tenant: tenant, actor: user, authorize?: false) == 0
    end
  end

  describe "policies test" do
    test "read subjects", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      subject = generate(subject(tenant: tenant))

      assert TeacherAssistant.Academics.can_read_subjects?(admin, tenant: tenant, data: subject)
      assert TeacherAssistant.Academics.can_read_subjects?(user, tenant: tenant, data: subject)
    end

    test "create subject", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))

      assert TeacherAssistant.Academics.can_create_subject?(admin, tenant: tenant)
      assert TeacherAssistant.Academics.can_create_subject?(user, tenant: tenant)
    end

    test "update subject", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      subject = generate(subject(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_update_subject?(admin, subject, tenant: tenant)
      assert TeacherAssistant.Academics.can_update_subject?(user, subject, tenant: tenant)
    end

    test "destroy subject", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      subject = generate(subject(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_destroy_subject?(admin, subject, tenant: tenant)
      assert TeacherAssistant.Academics.can_destroy_subject?(user, subject, tenant: tenant)
    end
  end
end
