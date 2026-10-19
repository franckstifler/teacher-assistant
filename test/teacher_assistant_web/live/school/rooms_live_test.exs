defmodule TeacherAssistantWeb.School.RoomsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})
    %{scope: scope, a: a, b: b}
  end

  defp room(scope, name), do: scope |> Organization.list_rooms() |> Enum.find(&(&1.name == name))

  test "a plain teacher is redirected", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/settings/rooms")
  end

  test "add a room, edit its capacity, deactivate it", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/rooms")

    view
    |> form("#room-form", room: %{name: "Labo SVT", kind: "laboratory", capacity: "40"})
    |> render_submit()

    labo = room(scope, "Labo SVT")
    assert labo.kind == :laboratory and labo.capacity == 40
    assert has_element?(view, "#room-#{labo.id}", "Laboratoire")

    view |> element("#edit-room-#{labo.id}") |> render_click()

    view
    |> form("#room-form", room: %{name: "Labo SVT", kind: "laboratory", capacity: "45"})
    |> render_submit()

    assert room(scope, "Labo SVT").capacity == 45
    assert length(Organization.list_rooms(scope)) == 1

    view |> element("#deactivate-room-#{labo.id}") |> render_click()
    refute room(scope, "Labo SVT").active?
    assert has_element?(view, "#room-#{labo.id}", "Inactive")
  end

  test "a bad capacity shows an error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/rooms")

    view
    |> form("#room-form", room: %{name: "X", kind: "classroom", capacity: "0"})
    |> render_submit()

    assert has_element?(view, "#room-error")
  end

  test "delete is offered only for an unused room", %{conn: conn, scope: scope, a: a} do
    {:ok, used} = Organization.create_room(scope, %{name: "B12"})
    {:ok, free} = Organization.create_room(scope, %{name: "B13"})
    {:ok, _} = Enrollment.set_home_room(scope, a, used.id)

    {:ok, view, _} = live(conn, ~p"/school/settings/rooms")
    refute has_element?(view, "#delete-room-#{used.id}")
    view |> element("#delete-room-#{free.id}") |> render_click()
    refute has_element?(view, "#room-#{free.id}")
    assert room(scope, "B13") == nil
  end

  test "a class's home room is chosen and cleared; a shared home room shows « déjà : 6e Q »",
       %{conn: conn, scope: scope, a: a, b: b} do
    {:ok, b12} = Organization.create_room(scope, %{name: "B12"})
    {:ok, view, _} = live(conn, ~p"/school/settings/rooms")

    view
    |> form("#home-room-#{a.id}", %{class_id: a.id, room_id: b12.id})
    |> render_change()

    assert Ash.get!(TeacherAssistant.Academics.ClassGroup, a.id, scope: scope).home_room_id ==
             b12.id

    assert has_element?(view, "#home-room-#{b.id} option", "déjà : 6e Q")

    view
    |> form("#home-room-#{a.id}", %{class_id: a.id, room_id: ""})
    |> render_change()

    assert Ash.get!(TeacherAssistant.Academics.ClassGroup, a.id, scope: scope).home_room_id == nil
  end

  test "a crafted home-room event with another school's room id changes nothing",
       %{conn: conn, scope: scope, a: a} do
    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, foreign} = Organization.create_room(other, %{name: "Ailleurs"})
    {:ok, view, _} = live(conn, ~p"/school/settings/rooms")

    render_change(view, "set_home_room", %{"class_id" => a.id, "room_id" => foreign.id})
    assert Ash.get!(TeacherAssistant.Academics.ClassGroup, a.id, scope: scope).home_room_id == nil
  end

  test "the form is empty again after a room is added", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/rooms")
    params = %{room: %{name: "Atelier 1", kind: "workshop", capacity: "25"}}
    view |> form("#room-form", params) |> render_change()
    assert has_element?(view, "#room-form input[name='room[name]'][value='Atelier 1']")

    view |> form("#room-form", params) |> render_submit()
    assert room(scope, "Atelier 1")
    refute has_element?(view, "#room-form input[name='room[name]'][value='Atelier 1']")
    refute has_element?(view, "#room-form input[name='room[capacity]'][value='25']")
  end
end
