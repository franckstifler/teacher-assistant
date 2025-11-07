defmodule TeacherAssistant.AcademicFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TeacherAssistant.Academics` domain.
  """

  use Ash.Generator

  def level(opts \\ []) do
    actor = get_actor(opts)
    tenant = Keyword.fetch!(opts, :tenant)

    changeset_generator(TeacherAssistant.Academics.Level, :create,
      defaults: [
        name: sequence(:level, &"Level #{&1}"),
        decription: Faker.Lorem.sentence()
      ],
      overrides: opts,
      actor: actor,
      tenant: tenant
    )
  end

  def option(opts \\ []) do
    actor = get_actor(opts)
    tenant = Keyword.fetch!(opts, :tenant)

    changeset_generator(TeacherAssistant.Academics.Option, :create,
      defaults: [
        name: sequence(:option, &"Option #{&1}"),
        decription: Faker.Lorem.sentence()
      ],
      overrides: opts,
      actor: actor,
      tenant: tenant
    )
  end

  def level_option(opts \\ []) do
    actor = get_actor(opts)
    tenant = Keyword.fetch!(opts, :tenant)

    level_id =
      opts[:level_id] ||
        StreamData.repeatedly(fn -> generate(level(tenant: tenant, actor: actor)).id end)

    option_id =
      opts[:option_id] ||
        StreamData.repeatedly(fn -> generate(option(tenant: tenant, actor: actor)).id end)

    changeset_generator(TeacherAssistant.Academics.LevelOption, :create,
      defaults: [
        level_id: level_id,
        option_id: option_id
      ],
      overrides: opts,
      actor: actor,
      tenant: tenant
    )
  end

  def subject(opts \\ []) do
    actor = get_actor(opts)
    tenant = Keyword.fetch!(opts, :tenant)

    changeset_generator(TeacherAssistant.Academics.Subject, :create,
      defaults: [
        name: sequence(:subject, &"Subject #{&1}"),
        decription: Faker.Lorem.sentence()
      ],
      overrides: opts,
      actor: actor,
      tenant: tenant
    )
  end

  def term(opts \\ []) do
    actor = get_actor(opts)
    tenant = Keyword.fetch!(opts, :tenant)
    academic_year_id = Keyword.fetch!(opts, :academic_year_id)

    after_action =
      if opts[:sequence_count] do
        fn term ->
          generate_many(term_sequence(tenant: tenant), opts[:sequence_count])

          Ash.load!(term, [:sequences])
        end
      end

    changeset_generator(TeacherAssistant.Academics.Term, :create,
      defaults: [
        name: sequence(:term, &"Term #{&1}"),
        academic_year_id: academic_year_id,
        start_date: Date.utc_today(),
        end_date: Date.add(Date.utc_today(), 90)
      ],
      overrides: opts,
      actor: actor,
      tenant: tenant,
      after_action: after_action
    )
  end

  def term_sequence(opts \\ []) do
    actor = get_actor(opts)
    tenant = Keyword.fetch!(opts, :tenant)

    term_id =
      opts[:term_id] ||
        once(:default_term_id, fn -> generate(term(tenant: tenant, actor: actor)).id end)

    changeset_generator(TeacherAssistant.Academics.Sequence, :create,
      defaults: [
        name: sequence(:option, &"Option #{&1}"),
        decription: Faker.Lorem.sentence(),
        term_id: term_id
      ],
      overrides: opts,
      actor: actor,
      tenant: tenant
    )
  end

  def academic_year(opts \\ []) do
    actor = get_actor(opts)
    tenant = Keyword.fetch!(opts, :tenant)

    changeset_generator(TeacherAssistant.Academics.AcademicYear, :create,
      defaults: [
        name: sequence(:term, &"Year 202#{&1}"),
        description: Faker.Lorem.sentence(),
        active: true,
        start_date: Date.utc_today(),
        end_date: Date.add(Date.utc_today(), 90),
        terms: [
          %{
            name: Faker.Lorem.sentence(),
            start_date: Date.utc_today(),
            end_date: Date.add(Date.utc_today(), 30),
            position: 1
          }
        ]
      ],
      overrides: opts,
      actor: actor,
      tenant: tenant
    )
  end

  def admin_user(opts \\ []) do
    tenant = Keyword.fetch!(opts, :tenant)

    changeset_generator(TeacherAssistant.Accounts.User, :create,
      defaults: [
        email: Faker.Internet.email()
      ],
      overrides: opts,
      tenant: tenant
    )
  end

  def user(opts \\ []) do
    tenant = Keyword.fetch!(opts, :tenant)

    changeset_generator(TeacherAssistant.Accounts.User, :create,
      defaults: [
        email: Faker.Internet.email()
      ],
      overrides: opts,
      tenant: tenant
    )
  end

  def school(opts \\ []) do
    changeset_generator(TeacherAssistant.Academics.School, :create,
      defaults: [
        name: sequence(:school, &"School #{&1}"),
        abbreviation: "GBHS Bda",
        type: :technical,
        sub_system: :francophone,
        description: Faker.Lorem.sentence()
      ],
      overrides: opts
    )
  end

  defp get_actor(_opts) do
    # opts[:actor] ||
    #   :default_actor
    #   |> once(fn ->
    #     nil
    #     # generate(root_user(tenant: opts[:tenant]))
    #   end)
    #   |> Enum.at(0)

    nil
  end
end
