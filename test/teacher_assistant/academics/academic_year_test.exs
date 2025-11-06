defmodule TeacherAssistant.Resources.AcademicYearTest do
  use TeacherAssistant.DataCase

  alias TeacherAssistant.Academics.AcademicYear

  require Ash.Query

  setup %{tenant: tenant} do
    user = generate(admin_user(tenant: tenant))
    %{user: user}
  end

  describe "TeacherAssistant.Academics.read_academic_years" do
    test "list academic_years", %{tenant: tenant, user: user} do
      academic_year = generate(academic_year(actor: user, tenant: tenant))

      assert [result] =
               TeacherAssistant.Academics.read_academic_years!(tenant: tenant, actor: user)

      assert result.id == academic_year.id
      assert result.name == academic_year.name
      assert result.description == academic_year.description
      assert result.start_date == academic_year.start_date
      assert result.end_date == academic_year.end_date
    end
  end

  describe "TeacherAssistant.Academics.create_academic_year" do
    test "with valid data creates a academic_year", %{tenant: tenant, user: user} do
      check all(
              input <- Ash.Generator.action_input(AcademicYear, :create),
              terms <-
                StreamData.list_of(
                  StreamData.fixed_map(%{
                    name: Ash.Generator.sequence(:term, &"Sequence #{&1}"),
                    description: StreamData.string(:utf8),
                    start_date: StreamData.repeatedly(&Date.utc_today/0),
                    end_date: StreamData.repeatedly(&Date.utc_today/0)
                  }),
                  min_length: 1,
                  max_length: 5
                )
            ) do
        params = Map.put(input, :terms, terms)

        academic_year =
          TeacherAssistant.Academics.create_academic_year!(params,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert academic_year.name == input[:name]
        assert academic_year.description == value_or_nil(input, :description)
        assert academic_year.start_date == value_or_nil(input, :start_date)
        assert academic_year.end_date == value_or_nil(input, :end_date)

        Enum.each(academic_year.terms, fn term ->
          assert Enum.find(terms, &(&1.name == term.name))
          # dbg(term_data)
          # assert term.description == term_data.description
          # assert term.start_date == term_data.start_date
          # assert term.end_date == term_data.end_date
        end)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.create_academic_year(%{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.update_academic_year" do
    test "updates a academic_year", %{tenant: tenant, user: user} do
      check all(
              academic_year <-
                StreamData.repeatedly(fn ->
                  generate(academic_year(tenant: tenant, actor: user))
                end),
              input <- Ash.Generator.action_input(academic_year, :update),
              terms <-
                StreamData.list_of(
                  StreamData.fixed_map(
                    name: Ash.Generator.sequence(:term, &"Updated term #{&1}"),
                    description: StreamData.string(:utf8),
                    start_date: StreamData.constant(~D[2025-01-01]),
                    end_date: StreamData.constant(~D[2025-04-01])
                  ),
                  min_length: 1,
                  max_length: 5
                )
            ) do
        params = Map.put(input, :terms, terms)

        updated_academic_year =
          TeacherAssistant.Academics.update_academic_year!(academic_year, params,
            tenant: tenant,
            actor: user,
            authorize?: false
          )

        assert updated_academic_year.name == input[:name]

        assert updated_academic_year.description ==
                 value_or_nil(input, :description, academic_year.description)
      end
    end

    test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
      academic_year = generate(academic_year(tenant: tenant, actor: user))

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               TeacherAssistant.Academics.update_academic_year(
                 academic_year,
                 %{name: nil, description: nil},
                 tenant: tenant,
                 actor: user,
                 authorize?: false
               )

      assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
    end
  end

  describe "TeacherAssistant.Academics.destroy_academic_year" do
    test "destroys a academic_year", %{tenant: tenant, user: user} do
      academic_year = generate(academic_year(tenant: tenant, actor: user))

      TeacherAssistant.Academics.destroy_academic_year!(academic_year,
        tenant: tenant,
        actor: user,
        authorize?: false
      )

      assert Ash.count!(AcademicYear, tenant: tenant, actor: user, authorize?: false) == 0
    end
  end

  describe "policies test" do
    test "read academic_years", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      academic_year = generate(academic_year(tenant: tenant))

      assert TeacherAssistant.Academics.can_read_academic_years?(admin,
               tenant: tenant,
               data: academic_year
             )

      assert TeacherAssistant.Academics.can_read_academic_years?(user,
               tenant: tenant,
               data: academic_year
             )
    end

    test "create academic_year", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))

      assert TeacherAssistant.Academics.can_create_academic_year?(admin, tenant: tenant)
      assert TeacherAssistant.Academics.can_create_academic_year?(user, tenant: tenant)
    end

    test "update academic_year", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      academic_year = generate(academic_year(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_update_academic_year?(admin, academic_year,
               tenant: tenant
             )

      assert TeacherAssistant.Academics.can_update_academic_year?(user, academic_year,
               tenant: tenant
             )
    end

    test "destroy academic_year", %{tenant: tenant} do
      admin = generate(admin_user(tenant: tenant))
      user = generate(user(tenant: tenant))
      academic_year = generate(academic_year(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_destroy_academic_year?(admin, academic_year,
               tenant: tenant
             )

      assert TeacherAssistant.Academics.can_destroy_academic_year?(user, academic_year,
               tenant: tenant
             )
    end
  end
end
