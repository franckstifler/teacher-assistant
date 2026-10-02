defmodule TeacherAssistant.Academics.RosterLine do
  @moduledoc """
  Spec KLM1: one pasted roster line per student,
  `nom;sexe;matricule;date de naissance;lieu de naissance;nom du parent;téléphone du parent`
  — every column after the name optional. Pure.
  """

  def parse(raw) do
    raw
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&(&1.full_name == ""))
  end

  defp parse_line(line) do
    [name, sex, matricule, birth_date, birth_place, parent_name, parent_phone] =
      line |> String.split(";") |> Enum.map(&String.trim/1) |> pad(7)

    %{
      full_name: name,
      sex: if(String.downcase(sex) == "m", do: :m, else: :f),
      matricule: blank_to_nil(matricule),
      repeater: false,
      birth_date: parse_date(birth_date),
      birth_place: blank_to_nil(birth_place),
      guardian: guardian(name, parent_name, parent_phone)
    }
  end

  defp pad(fields, n), do: Enum.take(fields ++ List.duplicate("", n), n)

  defp parse_date(value) do
    with [d, m, y] <- String.split(value, "/"),
         {d, ""} <- Integer.parse(d),
         {m, ""} <- Integer.parse(m),
         {y, ""} <- Integer.parse(y),
         {:ok, date} <- Date.new(y, m, d) do
      date
    else
      _ -> nil
    end
  end

  defp guardian(_student, _name, ""), do: nil
  defp guardian(student, "", phone), do: %{full_name: "Parent de #{student}", phone: phone}
  defp guardian(_student, name, phone), do: %{full_name: name, phone: phone}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
