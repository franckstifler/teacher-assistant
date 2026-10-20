defmodule TeacherAssistantWeb.AmountInWords do
  @moduledoc """
  A whole FCFA amount in French words, for receipts (Fees 1): « vingt-cinq mille cinq
  cents ». Traditional spelling: « vingt et un », « soixante et onze », « quatre-vingts »
  and « deux cents » take an s only at the end of the number or before « million(s) » /
  « milliard(s) »; « mille » never does.
  """

  @units ~w(zéro un deux trois quatre cinq six sept huit neuf dix onze douze treize quatorze
            quinze seize)
  @tens %{2 => "vingt", 3 => "trente", 4 => "quarante", 5 => "cinquante", 6 => "soixante"}

  def fr(0), do: "zéro"

  def fr(n) when is_integer(n) and n > 0 and n < 1_000_000_000_000 do
    milliards = div(n, 1_000_000_000)
    millions = n |> div(1_000_000) |> rem(1_000)
    thousands = n |> div(1_000) |> rem(1_000)
    rest = rem(n, 1_000)

    [
      big(milliards, "milliard"),
      big(millions, "million"),
      thousands_words(thousands),
      rest > 0 && below_1000(rest, true)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  defp big(0, _noun), do: nil
  defp big(1, noun), do: "un " <> noun
  defp big(n, noun), do: below_1000(n, true) <> " " <> noun <> "s"

  defp thousands_words(0), do: nil
  defp thousands_words(1), do: "mille"
  defp thousands_words(n), do: below_1000(n, false) <> " mille"

  # `final?`: the chunk ends the number (or precedes a noun), so « cents » / « vingts » keep their s.
  defp below_1000(n, final?) do
    hundreds = div(n, 100)
    rest = rem(n, 100)

    head =
      case hundreds do
        0 -> nil
        1 -> "cent"
        h when rest == 0 and final? -> Enum.at(@units, h) <> " cents"
        h -> Enum.at(@units, h) <> " cent"
      end

    tail = if rest > 0, do: below_100(rest, final?)
    [head, tail] |> Enum.filter(& &1) |> Enum.join(" ")
  end

  defp below_100(n, _final?) when n <= 16, do: Enum.at(@units, n)
  defp below_100(n, _final?) when n < 20, do: "dix-" <> Enum.at(@units, n - 10)
  defp below_100(80, true), do: "quatre-vingts"
  defp below_100(80, false), do: "quatre-vingt"
  defp below_100(n, _final?) when n > 80, do: "quatre-vingt-" <> below_100(n - 80, false)

  defp below_100(n, final?) when n >= 70 do
    case n - 60 do
      11 -> "soixante et onze"
      r -> "soixante-" <> below_100(r, final?)
    end
  end

  defp below_100(n, _final?) do
    ten = @tens[div(n, 10)]

    case rem(n, 10) do
      0 -> ten
      1 -> ten <> " et un"
      u -> ten <> "-" <> Enum.at(@units, u)
    end
  end
end
