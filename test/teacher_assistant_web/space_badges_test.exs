defmodule TeacherAssistantWeb.SpaceBadgesTest do
  @moduledoc """
  The Proviseur's « Suivi des séquences » badge reads the séquence's assessments and
  marks for the whole school: it is computed only where a menu is drawn, once.
  """
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistantWeb.Spaces

  setup :register_and_log_in_user

  # Tables read by this process (LiveView test renders and controller calls run here).
  defp sources_read(fun) do
    test_pid = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:teacher_assistant, :repo, :query],
      fn _event, _measurements, %{source: source}, _ ->
        if self() == test_pid, do: send(test_pid, {:read, source})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(id)
    end

    collect([])
  end

  defp collect(acc) do
    receive do
      {:read, source} -> collect([source | acc])
    after
      0 -> acc
    end
  end

  test "the probe sees the badge's reads when badges are counted", %{scope: scope} do
    assert "assessments" in sources_read(fn -> Spaces.put_space(scope, nil) end)
    refute "assessments" in sources_read(fn -> Spaces.put_space(scope, nil, counts?: false) end)
  end

  test "a controller request (the school logo) counts no badge", %{conn: conn} do
    refute "assessments" in sources_read(fn -> get(conn, ~p"/school/logo") end)
  end

  test "a LiveView's first HTTP render counts no badge; the connected page has the menu",
       %{conn: conn} do
    refute "assessments" in sources_read(fn ->
             conn |> get(~p"/school/settings") |> html_response(200)
           end)

    {:ok, view, _html} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#nav-school-sequences")
  end
end
