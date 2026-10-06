defmodule TeacherAssistantWeb.School.ClassSizeLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Accounts, Enrollment}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6ème A", level: "6ème"})
    {:ok, _} = Enrollment.create_class_group(scope, year, %{label: "6ème C", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    %{cg: cg}
  end

  defp limit(scope, max) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    {:ok, _} = Accounts.update_school_profile(profile, %{max_class_size: max}, scope: scope)
  end

  test "no limit: plain count; over the limit: « n / max » as a warning", %{conn: conn, scope: scope, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes")
    refute render(view) =~ "2 / "

    limit(scope, 1)
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#class-size-#{cg.id}.text-warning", "2 / 1")

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    assert has_element?(view, "#class-size", "2 / 1")
  end

  test "enrolling past the limit succeeds with the message", %{conn: conn, scope: scope, cg: cg} do
    limit(scope, 2)
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{"student" => %{"full_name" => "Zoé", "sex" => "f"}})
    |> render_submit()

    assert render(view) =~ "La classe dépasse l&#39;effectif maximum (2)"
    assert length(Enrollment.list_roster(scope, cg)) == 3
  end

  test "the add-class form proposes the next free label", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")

    view
    |> form("#class-form", %{"class_group" => %{"level" => "6ème", "label" => ""}})
    |> render_change()

    assert has_element?(view, "#class-form input[name='class_group[label]'][value='6ème B']")
  end

  test "settings holds the limit and the rule", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#school-profile-form", %{"profile" => %{"max_class_size" => "55", "class_suffix" => "numbers"}})
    |> render_submit()

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.max_class_size == 55
    assert profile.class_suffix == :numbers
  end
end
