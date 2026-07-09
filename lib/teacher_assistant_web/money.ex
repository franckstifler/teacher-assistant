defmodule TeacherAssistantWeb.Money do
  @moduledoc """
  Shared money formatting helpers for FCFA amounts (integers), used by the
  fees LiveViews and the printable bulletin HTML.
  """

  @doc """
  Formats an integer FCFA amount with a thousands separator (a regular
  space) and an " FCFA" suffix.

      iex> TeacherAssistantWeb.Money.format_fcfa(25000)
      "25 000 FCFA"

      iex> TeacherAssistantWeb.Money.format_fcfa(0)
      "0 FCFA"

      iex> TeacherAssistantWeb.Money.format_fcfa(-1000)
      "-1 000 FCFA"
  """
  def format_fcfa(amount) when is_integer(amount) do
    sign = if amount < 0, do: "-", else: ""

    grouped =
      amount
      |> abs()
      |> Integer.to_string()
      |> String.reverse()
      |> String.codepoints()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(" ")
      |> String.reverse()

    sign <> grouped <> " FCFA"
  end
end
