defmodule TeacherAssistant.Academics.RosterLine do
  @moduledoc """
  Élèves redesign (2026-10-08): one pasted roster line per student,
  `nom ; sexe ; matricule ; date de naissance ; téléphone du parent`, split on
  tabs when the line has one, else on semicolons. Name and sex are required;
  an unknown sex leaves `sex: nil` for the preview to reject. Pure.
  """

  @boys ~w(m g garçon garcon b boy male)
  @girls ~w(f fille girl female)

  def parse(raw) do
    raw
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&(&1.full_name == ""))
  end

  defp parse_line(line) do
    separator = if String.contains?(line, "\t"), do: "\t", else: ";"

    [name, sex, matricule, birth_date, phone] =
      line |> String.split(separator) |> Enum.map(&String.trim/1) |> pad(5)

    %{
      full_name: name,
      sex: sex(String.downcase(sex)),
      matricule: blank_to_nil(matricule),
      repeater: false,
      birth_date: parse_date(birth_date),
      guardian: guardian(name, phone)
    }
  end

  defp pad(fields, n), do: Enum.take(fields ++ List.duplicate("", n), n)

  defp sex(value) when value in @boys, do: :m
  defp sex(value) when value in @girls, do: :f
  defp sex(_value), do: nil

  defp parse_date(value) do
    with [d, m, y] <- String.split(value, "/"),
         {d, ""} <- Integer.parse(d),
         {m, ""} <- Integer.parse(m),
         {y, ""} <- Integer.parse(y),
         {:ok, date} <- Date.new(y, m, d),
         # A future date is a typo (2030 for 2003): dropped, like an impossible one.
         false <- Date.after?(date, Date.utc_today()) do
      date
    else
      _ -> nil
    end
  end

  defp guardian(_student, ""), do: nil
  defp guardian(student, phone), do: %{full_name: "Parent de #{student}", phone: phone}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
