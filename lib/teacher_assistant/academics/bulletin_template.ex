defmodule TeacherAssistant.Academics.BulletinTemplate do
  @moduledoc """
  The printed report card's template (spec I5), pure: language, grading column,
  elements shown, grade scale and header, resolved from the school profile for one
  class. Publishing stores the resolved map in the snapshot.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.BulletinElement
  alias TeacherAssistant.Accounts.HeadTitle

  @doc "The common in-school scale, lowest band first. Remarks are English (anglophone cards)."
  def default_grade_scale do
    [
      {"0", "F", "Fail"},
      {"8", "E", "Weak"},
      {"10", "D", "Pass"},
      {"12", "C", "Good"},
      {"14", "B", "Very good"},
      {"16", "A", "Excellent"}
    ]
    |> Enum.map(fn {from, letter, remark} ->
      %{from: Decimal.new(from), letter: letter, remark: remark}
    end)
  end

  @doc "The elements shown: nil = defaults; a list (even empty) as chosen."
  def elements(nil), do: BulletinElement.defaults()
  def elements(list) when is_list(list), do: list

  @doc "The grade scale in force, as plain maps."
  def grade_scale(bands) when bands in [nil, []], do: default_grade_scale()

  def grade_scale(bands),
    do: Enum.map(bands, &%{from: &1.from, letter: &1.letter, remark: &1.remark})

  @doc "The template for `class_group`'s printed cards under `profile`; `head_name` is printed."
  def resolve(profile, school_name, class_group, head_name \\ nil) do
    anglophone? = class_group.subsystem == :anglophone

    %{
      language:
        cond do
          profile.bulletin_language == :bilingual -> :bilingual
          anglophone? -> :en
          true -> :fr
        end,
      grading: if(anglophone?, do: :grade, else: :appreciation),
      elements: elements(profile.bulletin_elements),
      grade_scale: grade_scale(profile.grade_scale),
      cote_codes: cote_codes(profile.appreciation_bands),
      header: %{
        name: school_name,
        address: profile.address,
        town: profile.town,
        phone: profile.phone,
        motto: profile.motto,
        registration_number: profile.registration_number,
        school_code: Map.get(profile, :school_code),
        name_en: Map.get(profile, :name_en),
        official_lines_en: Map.get(profile, :official_header_lines_en),
        head_title: %{
          fr: HeadTitle.title(Map.get(profile, :school_type), :fr),
          en: HeadTitle.title(Map.get(profile, :school_type), :en)
        },
        head_name: head_name,
        region: profile.region,
        department: profile.department,
        logo?: is_binary(profile.logo_path),
        official_lines: profile.official_header_lines,
        signature?: is_binary(profile.signature_path),
        stamp?: is_binary(profile.stamp_path)
      }
    }
  end

  def show?(%{elements: elements}, element), do: element in elements

  @doc "Spec bulletin v2 §5.4: the coded bands' « cotes », highest band first."
  def cote_codes(bands) do
    %TeacherAssistant.Academics.GradingRules{appreciation_bands: bands}
    |> TeacherAssistant.Academics.Appreciations.bands()
    |> Enum.map(& &1.code)
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
  end

  @doc "`%{letter, remark}` for `mark`, or nil when there is no mark."
  def grade(_scale, nil), do: nil

  def grade(scale, %Decimal{} = mark) do
    scale
    |> Enum.filter(&(Decimal.compare(mark, &1.from) != :lt))
    |> List.last()
    |> case do
      nil -> nil
      band -> %{letter: band.letter, remark: band.remark}
    end
  end

  @doc "The header's official lines: the school's own when saved (spec KLM6), else the generated ones."
  def official_lines(header) do
    case Map.get(header, :official_lines) do
      [_ | _] = lines -> lines
      _ -> generated_official_lines(header)
    end
  end

  @doc """
  Spec bulletin v2 §5.1: one column of the header, in `lang` — the school's own lines
  for that language when saved, else the generated ones (never the other language's).
  """
  def official_lines(header, lang) when lang in [:fr, :en] do
    key = if lang == :fr, do: :official_lines, else: :official_lines_en

    case Map.get(header, key) do
      [_ | _] = lines ->
        lines

      _ ->
        Gettext.with_locale(TeacherAssistantWeb.Gettext, Atom.to_string(lang), fn ->
          generated_official_lines(header)
        end)
    end
  end

  @doc "The national lines generated from the region and department, in the current locale."
  def generated_official_lines(header) do
    [
      gettext("République du Cameroun"),
      gettext("Paix – Travail – Patrie"),
      gettext("Ministère des Enseignements secondaires"),
      header.region && regional_delegation(header.region),
      present(header.department) &&
        gettext("Délégation départementale des Enseignements secondaires : %{department}",
          department: header.department
        )
    ]
    |> Enum.filter(& &1)
  end

  @doc "The school's own lines (name, address, phone, authorisation, motto), in the current locale."
  def school_lines(header) do
    address = [header.address, header.town] |> Enum.filter(&present/1) |> Enum.join(" · ")

    [
      header.name,
      present(address) && address,
      present(header.phone) && gettext("Tél. %{phone}", phone: header.phone),
      present(header.registration_number) &&
        gettext("Autorisation n° %{number}", number: header.registration_number),
      present(header.motto) && header.motto
    ]
    |> Enum.filter(& &1)
  end

  def regional_delegation(:adamawa),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Adamaoua")

  def regional_delegation(:centre),
    do: gettext("Délégation régionale des Enseignements secondaires du Centre")

  def regional_delegation(:east),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Est")

  def regional_delegation(:far_north),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Extrême-Nord")

  def regional_delegation(:littoral),
    do: gettext("Délégation régionale des Enseignements secondaires du Littoral")

  def regional_delegation(:north),
    do: gettext("Délégation régionale des Enseignements secondaires du Nord")

  def regional_delegation(:northwest),
    do: gettext("Délégation régionale des Enseignements secondaires du Nord-Ouest")

  def regional_delegation(:south),
    do: gettext("Délégation régionale des Enseignements secondaires du Sud")

  def regional_delegation(:southwest),
    do: gettext("Délégation régionale des Enseignements secondaires du Sud-Ouest")

  def regional_delegation(:west),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Ouest")

  defp present(text), do: is_binary(text) and String.trim(text) != ""
end
