defmodule TeacherAssistant.Seed do
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
  end

  def seed_default_data(school) do
    year =
      Ash.Seed.upsert!(
        TeacherAssistant.Academics.AcademicYear,
        %{
          name: "2025-2026",
          active: true,
          start_date: Date.utc_today(),
          end_date: Date.utc_today() |> Date.add(270)
        },
        identity: :unique_name,
        tenant: school.id
      )

    terms_input = [
      %{
        name: "1er Trimestre",
        start_date: Date.utc_today(),
        end_date: Date.utc_today() |> Date.add(90),
        position: 1,
        academic_year_id: year.id
      },
      %{
        name: "2eme Trimestre",
        start_date: Date.utc_today() |> Date.add(91),
        end_date: Date.utc_today() |> Date.add(180),
        position: 2,
        academic_year_id: year.id
      },
      %{
        name: "3eme Trimestre",
        start_date: Date.utc_today() |> Date.add(181),
        end_date: Date.utc_today() |> Date.add(270),
        position: 3,
        academic_year_id: year.id
      }
    ]

    terms =
      Ash.Seed.upsert!(
        TeacherAssistant.Academics.Term,
        terms_input,
        identity: :unique_name,
        tenant: school.id
      )

    levels_input =
      Map.get(@levels, school.type)
      |> Map.get(school.sub_system)
      |> Enum.map(fn level ->
        %{name: level}
      end)

    levels =
      Ash.Seed.upsert!(
        TeacherAssistant.Academics.Level,
        levels_input,
        tenant: school.id,
        identity: :unique_name
      )

    options_input =
      Map.get(@options, school.type)
      |> Enum.map(fn option ->
        %{name: option}
      end)

    options =
      Ash.Seed.upsert!(
        TeacherAssistant.Academics.Option,
        options_input,
        tenant: school.id,
        identity: :unique_name
      )

    subjects_input =
      @subjects
      |> Enum.map(fn subject ->
        %{name: subject}
      end)

    subjects =
      Ash.Seed.upsert!(
        TeacherAssistant.Academics.Subject,
        subjects_input,
        identitty: :unique_name,
        tenant: school.id
      )

    {year, terms, levels, options, subjects}
  end
end
