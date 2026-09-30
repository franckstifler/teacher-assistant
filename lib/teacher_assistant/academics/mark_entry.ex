defmodule TeacherAssistant.Academics.MarkEntry do
  @moduledoc """
  A mark as typed and shown: a number (French comma accepted), `abs`, `abj`, or blank
  ("not entered").
  """
  alias TeacherAssistant.Academics.MarkStatus

  @doc """
  Parses a raw mark field: a number, `a`/`abs` (absent), `abj` (justified absence), or
  blank. Anything else is :error, so a typo never becomes a silent absence.
  """
  def parse(nil), do: {:ok, :blank}

  def parse(raw) when is_binary(raw) do
    case raw |> String.trim() |> String.downcase() |> String.replace(",", ".") do
      "" ->
        {:ok, :blank}

      code when code in ["a", "abs"] ->
        {:ok, :absent}

      "abj" ->
        {:ok, :excused}

      normalized ->
        case Decimal.parse(normalized) do
          {d, ""} -> {:ok, {:graded, d}}
          _ -> :error
        end
    end
  end

  @doc "A stored value for display: `12,5`, `abs`, `abj`, or `—` for blank."
  def format(nil, _score), do: "—"

  def format(:graded, %Decimal{} = score),
    do: score |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  def format(status, _score), do: MarkStatus.code(status)
end
