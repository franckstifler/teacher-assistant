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
        name: sequence(:chool, &"School #{&1}"),
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
