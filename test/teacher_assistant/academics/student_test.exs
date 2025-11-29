defmodule TeacherAssistant.Resources.StudentTest do
  use TeacherAssistant.DataCase

  alias TeacherAssistant.Academics.Student

  require Ash.Query

  setup %{tenant: tenant} do
    user = generate(admin_user(tenant: tenant))
    %{user: user}
  end

  describe "TeacherAssistant.Academics.read_students" do
    test "list students", %{tenant: tenant, user: user} do
      student = generate(student(actor: user, tenant: tenant))

      assert [result] = TeacherAssistant.Academics.read_students!(tenant: tenant, actor: user)

      assert result.id == student.id
      assert result.first_name == student.first_name
      assert result.last_name == student.last_name
      assert result.matricule == student.matricule
      assert result.place_of_birth == student.place_of_birth
      assert result.date_of_birth == student.date_of_birth
      assert result.gender == student.gender
    end
  end

  describe "TeacherAssistant.Academics.create_student" do
    test "with valid data creates a student", %{tenant: tenant, user: user} do
      check all(input <- Ash.Generator.action_input(Student, :create)) do
        student =
          TeacherAssistant.Academics.create_student!(input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert student.first_name == input[:first_name]
        assert student.last_name == input[:last_name]
        assert student.matricule == value_or_nil(input, :matricule)
        assert student.place_of_birth == value_or_nil(input, :place_of_birth)
        assert student.date_of_birth == value_or_nil(input, :date_of_birth)
        assert student.gender == value_or_nil(input, :gender, :male)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.create_student(
                 %{first_name: nil, last_name: nil, date_of_birth: nil, gender: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :first_name, error_class: Ash.Error.Changes.Required)
      assert_field_error(errors, :last_name, error_class: Ash.Error.Changes.Required)
      assert_field_error(errors, :gender, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.update_student" do
    test "updates a student", %{tenant: tenant, user: user} do
      check all(input <- Ash.Generator.action_input(Student, :update)) do
        student = generate(student(tenant: tenant, actor: user))

        updated_student =
          TeacherAssistant.Academics.update_student!(student, input,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert updated_student.first_name == input[:first_name]
        assert updated_student.last_name == input[:last_name]

        assert updated_student.matricule ==
                 value_or_nil(input, :matricule, student.matricule)

        assert updated_student.place_of_birth ==
                 value_or_nil(input, :place_of_birth, student.place_of_birth)

        assert updated_student.date_of_birth ==
                 value_or_nil(input, :date_of_birth, student.date_of_birth)

        assert updated_student.gender ==
                 value_or_nil(input, :gender, student.gender)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      student = generate(student(tenant: tenant, actor: user))

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.update_student(
                 student,
                 %{first_name: nil, last_name: nil, gender: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :first_name, error_class: Ash.Error.Changes.Required)
      assert_field_error(errors, :last_name, error_class: Ash.Error.Changes.Required)
      assert_field_error(errors, :gender, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.destroy_student" do
    test "destroys a student", %{tenant: tenant, user: user} do
      student = generate(student(tenant: tenant, actor: user))

      TeacherAssistant.Academics.destroy_student!(student,
        tenant: tenant,
        actor: user,
        authorize?: false
      )

      assert Ash.count!(Student, tenant: tenant, actor: user, authorize?: false) == 0
    end
  end

  describe "policies test" do
    test "read students", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      student = generate(student(tenant: tenant))

      assert TeacherAssistant.Academics.can_read_students?(admin, tenant: tenant, data: student)
      assert TeacherAssistant.Academics.can_read_students?(user, tenant: tenant, data: student)
    end

    test "create student", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))

      assert TeacherAssistant.Academics.can_create_student?(admin, tenant: tenant)
      assert TeacherAssistant.Academics.can_create_student?(user, tenant: tenant)
    end

    test "update student", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      student = generate(student(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_update_student?(admin, student, tenant: tenant)
      assert TeacherAssistant.Academics.can_update_student?(user, student, tenant: tenant)
    end

    test "destroy student", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      student = generate(student(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_destroy_student?(admin, student, tenant: tenant)
      assert TeacherAssistant.Academics.can_destroy_student?(user, student, tenant: tenant)
    end
  end
end
