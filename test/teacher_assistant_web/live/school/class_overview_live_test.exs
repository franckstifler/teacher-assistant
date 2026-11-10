defmodule TeacherAssistantWeb.School.ClassOverviewLiveTest do
  @moduledoc "The class's « Vue d'ensemble » tab at /school/classes/:id (UX refonte batch 5)."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    classes =
      scope
      |> Enrollment.list_class_groups(year)
      |> Enum.sort_by(&TeacherAssistant.Academics.SchoolTemplates.class_sort_key/1)

    [cg | _] = classes
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, repeater: true})
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Cléo", sex: :f})
    %{cg: cg, classes: classes}
  end

  test "the header: back, next class, summary line, tab counts, « Imprimer… »", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/classes/#{ctx.cg.id}")

    assert has_element?(view, "#class-tab-overview[aria-current=page]", "Vue d'ensemble")
    assert has_element?(view, "#class-back[href='/school/classes']")
    [_, next | _] = ctx.classes
    assert has_element?(view, "#class-next[href='/school/classes/#{next.id}']", next.label)
    refute has_element?(view, "#class-prev")

    summary = view |> element("#class-summary") |> render()
    assert summary =~ "3 élèves"
    assert summary =~ "2 filles, 1 garçon"
    assert summary =~ "1 redoublant"

    assert has_element?(
             view,
             "#class-tab-students[href='/school/classes/#{ctx.cg.id}/students']",
             "3"
           )

    assert view |> element("#class-tab-teachings") |> render() =~ ~r/\d+\/\d+/
    assert has_element?(view, "#class-print-menu", "Imprimer…")
    # on phones the actions sit at the right, so the menu (aligned on the button's
    # right edge) opens inside the screen
    assert has_element?(view, "#class-actions.justify-end #class-print-menu")

    assert has_element?(
             view,
             "#print-class-list[href='/school/classes/#{ctx.cg.id}/class-list/print']"
           )

    # the head prints the class's séquence marks for students to check
    assert has_element?(
             view,
             "#print-mark-sheet[href='/school/classes/#{ctx.cg.id}/mark-sheet/print']",
             "Relevé des notes"
           )
  end

  test "« À régler »: the form master is designated inline; contacts are counted", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, view, _} = live(ctx.conn, ~p"/school/classes/#{ctx.cg.id}")

    assert has_element?(view, "#class-todo", "À régler pour cette classe")
    assert has_element?(view, "#todo-contacts", "Aucun contact parent")
    assert has_element?(view, "#todo-contacts", "0 sur 3")

    assert has_element?(
             view,
             "#todo-contacts a[href='/school/students?class=#{ctx.cg.id}&no_contact=1']"
           )

    assert has_element?(view, "#pp-select option[value='#{teacher.current_user.id}']")
    view |> form("#pp-form", %{"user_id" => teacher.current_user.id}) |> render_change()

    {:ok, cg} = Enrollment.fetch_owned_class_group(ctx.scope, ctx.cg.id)
    assert cg.form_master_user_id == teacher.current_user.id
    refute has_element?(view, "#todo-form-master")
    assert has_element?(view, "#class-form-master")
  end

  test "the glance tiles link to their tabs", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/classes/#{ctx.cg.id}")

    assert has_element?(
             view,
             "#tile-notes[href='/school/classes/#{ctx.cg.id}/results']",
             "Notes Séq."
           )

    assert has_element?(view, "#tile-calls", "Appels aujourd'hui")
    assert has_element?(view, "#tile-absences", "0 h")
    assert has_element?(view, "#tile-timetable[href='/school/classes/#{ctx.cg.id}/timetable']")
  end

  test "the notes tile shows the entry rate with a single percent sign", ctx do
    TeacherFixtures.assigned_context_fixture(ctx.scope, ctx.year, %{class_group: ctx.cg})
    {:ok, view, _} = live(ctx.conn, ~p"/school/classes/#{ctx.cg.id}")

    # Gettext has no « %% » escape: « 0 % saisi », never « 0 %% saisi ».
    notes = view |> element("#tile-notes") |> render()
    assert notes =~ ~r/\d+ % saisi/
    refute notes =~ "%%"
  end

  test "the surveillant général lands on the register; a plain teacher is sent back", ctx do
    sg = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:discipline_master]})

    conn =
      build_conn()
      |> log_in_user(sg.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.workspace.id)

    register = ~p"/school/classes/#{ctx.cg.id}/register"

    assert {:error, {:live_redirect, %{to: ^register}}} =
             live(conn, ~p"/school/classes/#{ctx.cg.id}")

    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})

    conn =
      build_conn()
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{ctx.cg.id}")
  end

  test "the form master sees the overview without the PP select", ctx do
    fm = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)

    conn =
      build_conn()
      |> log_in_user(fm.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.workspace.id)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}")
    assert has_element?(view, "#class-tab-overview[aria-current=page]")
    refute has_element?(view, "#pp-select")
    # the neighbour classes are not theirs
    refute has_element?(view, "#class-next")
  end
end
