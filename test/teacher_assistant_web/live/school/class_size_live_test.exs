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

  test "no limit: plain count; over the limit: « n / max » as a warning", %{
    conn: conn,
    scope: scope,
    cg: cg
  } do
    {:ok, view, _} = live(conn, ~p"/school/classes")
    refute render(view) =~ "2 / "

    limit(scope, 1)
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#class-size-#{cg.id}.text-error", "2 / 1")

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    assert has_element?(view, "#class-size", "2 / 1")
  end

  test "enrolling past the limit succeeds with the message", %{conn: conn, scope: scope, cg: cg} do
    limit(scope, 2)
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#enroll-button") |> render_click()

    view
    |> form("#enroll-form", %{"enroll" => %{"full_name" => "Zoé", "sex" => "f"}})
    |> render_submit()

    assert render(view) =~ "La classe dépasse l&#39;effectif maximum (2)"
    assert length(Enrollment.list_roster(scope, cg)) == 3
  end

  test "the drawer proposes the next free suffix", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#new-class-button") |> render_click()
    view |> form("#class-form", %{"nc" => %{"level" => "6ème"}}) |> render_change()

    assert has_element?(view, "#nc-suffix[value='B']")
    assert has_element?(view, "#nc-preview", "6ème B")
  end

  test "a class's own maximum overrides the school's on its card", %{
    conn: conn,
    scope: scope,
    cg: cg
  } do
    limit(scope, 40)
    {:ok, _} = Ash.update(cg, %{max_size: 2}, scope: scope)
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#class-size-#{cg.id}.text-warning", "2 / 2")
  end

  test "a class with grid subjects still unassigned is marked « À compléter »", %{
    conn: conn,
    scope: scope,
    cg: cg
  } do
    n = length(TeacherAssistant.Curriculum.unassigned_subjects_by_class(scope, [cg])[cg.id])
    assert n > 0
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#class-card-#{cg.id} [title='À compléter']")

    assert has_element?(
             view,
             "#class-unassigned-#{cg.id}.text-error",
             "#{n} matières sans enseignant"
           )
  end

  test "settings holds the limit and the rule", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/profile")

    view
    |> form("#school-profile-form", %{
      "profile" => %{"max_class_size" => "55", "class_suffix" => "numbers"}
    })
    |> render_submit()

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.max_class_size == 55
    assert profile.class_suffix == :numbers
  end

  test "a suffix the admin typed survives other edits", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#new-class-button") |> render_click()
    view |> form("#class-form", %{"nc" => %{"level" => "6ème"}}) |> render_change()

    view
    |> form("#class-form", %{"nc" => %{"level" => "6ème", "suffix" => "Bilingue"}})
    |> render_change()

    view
    |> form("#class-form", %{
      "nc" => %{"level" => "6ème", "suffix" => "Bilingue"},
      "class_group" => %{"max_size" => "50"}
    })
    |> render_change()

    assert has_element?(view, "#nc-preview", "6ème Bilingue")
  end
end
