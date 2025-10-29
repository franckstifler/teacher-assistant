defmodule TeacherAssistantWeb.Seed do
  @levels %{
    technical: %{
      francophone: [
        "1ere Annee",
        "2eme Annee",
        "3eme Annee",
        "4eme Annee",
        "Seconde",
        "Premiere",
        "Terminale"
      ],
      anglophone: [
        "Year 1",
        "Year 2",
        "Year 3",
        "Year 4",
        "Year 5",
        "Lower Sixth",
        "Upper Sixth"
      ]
    },
    general: %{
      francophone: [
        "6eme",
        "5eme",
        "4eme",
        "3eme",
        "2nde",
        "1ere",
        "Terminale"
      ],
      anglophone: [
        "Form 1",
        "Form 2",
        "Form 3",
        "Form 4",
        "Form 5",
        "Lower Sixth",
        "Upper Sixth"
      ]
    }
  }

  @options %{
    technical: [
      "MACO",
      "MENU",
      "ELEQ",
      "ESCOM",
      "COME",
      "ESF",
      "F1",
      "F2",
      "F3",
      "F4-BA",
      "IH",
      "CG"
    ],
    general: ["M1", "M2", "M3", "M4", "M5", "M6", "A1", "A2", "A3", "A4", "C", "D", "TI"]
  }

  @subjects [
    "Mathematiques",
    "Francais",
    "Anglais",
    "Physique",
    "Physique/Chimie",
    "GSO",
    "Informatique",
    "TM"
  ]

  def seed do
    school =
      Ash.create!(
        TeacherAssistant.Academics.School,
        %{
          name: "Lycee Technique de Douala",
          abbreviation: "LTD",
          type: :technical,
          sub_system: :francophone
        },
        upsert?: true,
        upsert_identity: :unique_name
      )

    seed_default_data(school)
    # {year, levels, options, subjects} = seed_default_data(school)

    # levels_options =
    #   for level <- levels, option <- options do
    #     Ash.Seed.seed!(%TeacherAssistant.Academics.LevelOption{
    #       level_id: level.id,
    #       option_id: option.id
    #     })
    #   end
  end

  def seed_default_data(school) do
    year =
      Ash.create!(
        TeacherAssistant.Academics.AcademicYear,
        %{
          name: "2025-2026",
          active: true,
          start_date: Date.utc_today(),
          end_date: Date.utc_today() |> Date.add(270),
          terms: [
            %{
              name: "1er Trimestre",
              start_date: Date.utc_today(),
              end_date: Date.utc_today() |> Date.add(90)
            },
            %{
              name: "2eme Trimestre",
              start_date: Date.utc_today() |> Date.add(91),
              end_date: Date.utc_today() |> Date.add(180)
            },
            %{
              name: "3eme Trimestre",
              start_date: Date.utc_today() |> Date.add(181),
              end_date: Date.utc_today() |> Date.add(270)
            }
          ]
        },
        upsert?: true,
        upsert_identity: :unique_name,
        scope: %TeacherAssistant.Scope{current_tenant: school}
      )

    %Ash.BulkResult{records: levels} =
      Map.get(@levels, school.type)
      |> Map.get(school.sub_system)
      |> Enum.map(fn level ->
        %{name: level}
      end)
      |> Ash.bulk_create!(
        TeacherAssistant.Academics.Level,
        :create,
        scope: %TeacherAssistant.Scope{current_tenant: school},
        upsert?: true,
        upsert_identity: :unique_name,
        upsert_fields: [:description],
        return_records?: true
      )

    %Ash.BulkResult{records: options} =
      Map.get(@options, school.type)
      |> Enum.map(fn option ->
        %{name: option}
      end)
      |> Ash.bulk_create!(
        TeacherAssistant.Academics.Option,
        :create,
        scope: %TeacherAssistant.Scope{current_tenant: school},
        upsert?: true,
        upsert_identity: :unique_name,
        upsert_fields: [:description],
        return_records?: true
      )

    %Ash.BulkResult{records: subjects} =
      @subjects
      |> Enum.map(fn subject ->
        %{name: subject}
      end)
      |> Ash.bulk_create!(
        TeacherAssistant.Academics.Subject,
        :create,
        scope: %TeacherAssistant.Scope{current_tenant: school},
        upsert?: true,
        upsert_identity: :unique_name,
        upsert_fields: [:description],
        return_records?: true
      )

    {year, levels, options, subjects}
  end
end
