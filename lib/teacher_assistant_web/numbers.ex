defmodule TeacherAssistantWeb.Numbers do
  @moduledoc """
  Numbers for screens, in the session locale: a decimal comma in French
  ("14,20", "0,92 h"), a point in English. Only for display — form `value`s keep
  the point that `<input type="number">` requires.
  """

  @doc """
  Formats a number. `places` rounds (default 2); `trim: true` drops trailing
  zeros ("0,92", "1", "4") — for hours and coefficients; averages keep them ("14,20").
  """
  def decimal(value, opts \\ [])
  def decimal(nil, _opts), do: "—"

  def decimal(value, opts) when is_integer(value), do: value |> Decimal.new() |> decimal(opts)

  def decimal(value, opts) when is_float(value),
    do: value |> Decimal.from_float() |> decimal(opts)

  def decimal(%Decimal{} = value, opts) do
    places = Keyword.get(opts, :places, 2)
    rounded = Decimal.round(value, places)

    string =
      if Keyword.get(opts, :trim, false),
        do: rounded |> Decimal.normalize() |> Decimal.to_string(:normal),
        else: Decimal.to_string(rounded, :normal)

    localize(string)
  end

  @doc "Hours with a unit: `0,92 h`."
  def hours(value), do: decimal(value, trim: true) <> " h"

  defp localize(string) do
    case Gettext.get_locale(TeacherAssistantWeb.Gettext) do
      "en" -> string
      _ -> String.replace(string, ".", ",")
    end
  end
end
