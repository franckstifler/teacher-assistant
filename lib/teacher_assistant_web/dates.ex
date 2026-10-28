defmodule TeacherAssistantWeb.Dates do
  @moduledoc """
  Human dates for screens, in the session locale: "ven. 2 oct." (short),
  "jeudi 1 octobre" (long), "Aujourd'hui" / "hier" for the nearest days.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @doc ~S|"ven. 2 oct." / "Fri 2 Oct"|
  def short(%Date{} = date),
    do: "#{weekday_short(Date.day_of_week(date))} #{date.day} #{month_short(date.month)}"

  @doc ~S|"2 oct." / "2 Oct" (no weekday)|
  def day_month(%Date{} = date), do: "#{date.day} #{month_short(date.month)}"

  @doc ~S|"jeudi 1 octobre" / "Thursday 1 October"|
  def long(%Date{} = date),
    do: "#{weekday_long(Date.day_of_week(date))} #{date.day} #{month_long(date.month)}"

  @doc ~S|"lundi 15" / "Monday 15"|
  def weekday_day(%Date{} = date), do: "#{weekday_long(Date.day_of_week(date))} #{date.day}"

  @doc ~S|"ven. 2 oct. 14:05" / "Fri 2 Oct 14:05", in Cameroon time (UTC+1).|
  def short_datetime(%DateTime{} = at) do
    local = DateTime.add(at, 3600)
    "#{short(DateTime.to_date(local))} #{Calendar.strftime(local, "%H:%M")}"
  end

  @doc ~S|"Aujourd'hui", "hier", else `short/1`.|
  def relative(%Date{} = date, %Date{} = today) do
    case Date.diff(today, date) do
      0 -> gettext("Aujourd'hui")
      1 -> gettext("hier")
      _ -> short(date)
    end
  end

  defp weekday_short(1), do: gettext("lun.")
  defp weekday_short(2), do: gettext("mar.")
  defp weekday_short(3), do: gettext("mer.")
  defp weekday_short(4), do: gettext("jeu.")
  defp weekday_short(5), do: gettext("ven.")
  defp weekday_short(6), do: gettext("sam.")
  defp weekday_short(7), do: gettext("dim.")

  defp weekday_long(1), do: gettext("lundi")
  defp weekday_long(2), do: gettext("mardi")
  defp weekday_long(3), do: gettext("mercredi")
  defp weekday_long(4), do: gettext("jeudi")
  defp weekday_long(5), do: gettext("vendredi")
  defp weekday_long(6), do: gettext("samedi")
  defp weekday_long(7), do: gettext("dimanche")

  defp month_short(1), do: gettext("janv.")
  defp month_short(2), do: gettext("févr.")
  defp month_short(3), do: gettext("mars")
  defp month_short(4), do: gettext("avr.")
  defp month_short(5), do: gettext("mai")
  defp month_short(6), do: gettext("juin")
  defp month_short(7), do: gettext("juil.")
  defp month_short(8), do: gettext("août")
  defp month_short(9), do: gettext("sept.")
  defp month_short(10), do: gettext("oct.")
  defp month_short(11), do: gettext("nov.")
  defp month_short(12), do: gettext("déc.")

  defp month_long(1), do: gettext("janvier")
  defp month_long(2), do: gettext("février")
  defp month_long(3), do: gettext("mars")
  defp month_long(4), do: gettext("avril")
  defp month_long(5), do: gettext("mai")
  defp month_long(6), do: gettext("juin")
  defp month_long(7), do: gettext("juillet")
  defp month_long(8), do: gettext("août")
  defp month_long(9), do: gettext("septembre")
  defp month_long(10), do: gettext("octobre")
  defp month_long(11), do: gettext("novembre")
  defp month_long(12), do: gettext("décembre")
end
