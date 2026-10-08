defmodule TeacherAssistantWeb.School.ClassLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée D"})

    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, cg2: cg2, user: user, scope: scope}
  end

  test "shows the roster with status and repeater", %{conn: conn, cg: cg, scope: scope} do
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, repeater: true})
    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}")
    assert html =~ "Awa"
    # The sex in words, not the stored code.
    assert view |> element("tr", "Awa") |> render() =~ "Féminin"
  end

  test "enrolls a new student (inscription) from the drawer", %{conn: conn, cg: cg, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#enroll-button") |> render_click()

    view
    |> form("#enroll-form", %{
      "enroll" => %{
        "full_name" => "Bi",
        "sex" => "m",
        "matricule" => "M-3",
        "birth_date" => "2014-03-02",
        "birth_place" => "Yaoundé"
      }
    })
    |> render_submit()

    assert [%{student: %{full_name: "Bi", birth_place: "Yaoundé", birth_date: ~D[2014-03-02]}}] =
             Enrollment.list_roster(scope, cg)

    refute has_element?(view, "#enroll-drawer")
  end

  test "enrolling with a new parent records them as the main contact", ctx do
    %{conn: conn, cg: cg, scope: scope} = ctx
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#enroll-button") |> render_click()

    params = %{
      "full_name" => "Bi",
      "sex" => "m",
      "parent_phone" => "677 12 34 56",
      "parent_name" => "Jean Bi",
      "parent_relationship" => "pere"
    }

    view |> form("#enroll-form", %{"enroll" => params}) |> render_change()
    view |> form("#enroll-form", %{"enroll" => params}) |> render_submit()

    [%{student: student}] = Enrollment.list_roster(scope, cg)
    assert [%{guardian: %{full_name: "Jean Bi"}}] = Enrollment.list_guardian_links(scope, student)
    assert has_element?(view, "tr", "Jean Bi")
  end

  test "a parent already on file is found by phone and linked", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx
    {:ok, %{student: sibling}} = Enrollment.enroll_new(scope, cg2, %{full_name: "Awa", sex: :f})

    {:ok, mum} =
      Enrollment.add_guardian(scope, sibling, %{
        full_name: "Marie Bi",
        relationship: :mere,
        phone: "699112233"
      })

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#enroll-button") |> render_click()

    view
    |> form("#enroll-form", %{
      "enroll" => %{"full_name" => "Bi", "parent_phone" => "699 11 22 33"}
    })
    |> render_change()

    assert has_element?(view, "#enroll-parent-matches", "Marie Bi")
    assert has_element?(view, "#enroll-parent-matches", "Mère de 1 élève")
    refute has_element?(view, "#enroll-parent-name")

    view
    |> form("#enroll-form", %{
      "enroll" => %{"full_name" => "Bi", "parent_phone" => "699 11 22 33"}
    })
    |> render_submit()

    [%{student: student}] = Enrollment.list_roster(scope, cg)
    assert [%{guardian_id: id}] = Enrollment.list_guardian_links(scope, student)
    assert id == mum.id
  end

  test "with several parents on file for a phone, one must be picked", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx
    {:ok, %{student: a}} = Enrollment.enroll_new(scope, cg2, %{full_name: "Awa", sex: :f})
    {:ok, %{student: b}} = Enrollment.enroll_new(scope, cg2, %{full_name: "Ali", sex: :m})

    for {student, name} <- [{a, "Marie Bi"}, {b, "Paul Bi"}] do
      {:ok, _} =
        Enrollment.add_guardian(scope, student, %{
          full_name: name,
          relationship: :autre,
          phone: "699112233"
        })
    end

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#enroll-button") |> render_click()
    params = %{"enroll" => %{"full_name" => "Bi", "parent_phone" => "699112233"}}
    view |> form("#enroll-form", params) |> render_change()
    view |> form("#enroll-form", params) |> render_submit()

    assert has_element?(view, "#enroll-error", "Choisissez le parent")
    assert Enrollment.list_roster(scope, cg) == []
  end

  test "the drawer's footer gives the size after this enrolment, in warning past the maximum",
       ctx do
    %{conn: conn, cg: cg, scope: scope} = ctx
    {:ok, cg} = Enrollment.set_class_max_size(scope, cg, 1)
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#enroll-button") |> render_click()

    assert has_element?(view, "#enroll-after.text-warning", "2 / 1 élèves après cet ajout")
  end

  test "« Inscrire et en ajouter un autre » keeps the drawer open and empty", ctx do
    %{conn: conn, cg: cg, scope: scope} = ctx
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#enroll-button") |> render_click()

    view
    |> form("#enroll-form", %{"enroll" => %{"full_name" => "Bi"}})
    |> render_submit(%{"then" => "another"})

    assert [_] = Enrollment.list_roster(scope, cg)
    assert has_element?(view, "#enroll-drawer #enroll-full-name")
    refute has_element?(view, "#enroll-full-name[value='Bi']")
  end

  test "duplicate matricule surfaces a friendly error", %{conn: conn, cg: cg, scope: scope} do
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view |> element("#enroll-button") |> render_click()

    view
    |> form("#enroll-form", %{
      "enroll" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-1"}
    })
    |> render_submit()

    assert length(Enrollment.list_roster(scope, cg)) == 1
    assert has_element?(view, "#enroll-error", "matricule")
  end

  test "search finds an existing student and re-enrolls (réinscription)", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx

    {:ok, %{student: s, enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa Zang", sex: :f, matricule: "M-1"})

    :ok = Enrollment.withdraw(scope, e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}")
    view |> element("#enroll-button") |> render_click()
    view |> element("#enroll-mode-existing") |> render_click()
    view |> form("#enroll-search-form", %{"q" => "M-1"}) |> render_change()
    assert render(view) =~ "Awa Zang"
    view |> element("#search-enroll-#{s.id}") |> render_click()

    assert [%{enrollment: %{status: :reinscription}}] = Enrollment.list_roster(scope, cg2)
  end

  test "the search shows each student's last class and who is already enrolled this year",
       ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx

    {:ok, past} =
      Organization.create_academic_year(scope, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: false
      })

    {:ok, old_cg} = Enrollment.create_class_group(scope, past, %{label: "CM2", level: "6ème"})

    {:ok, %{student: former}} =
      Enrollment.enroll_new(scope, old_cg, %{full_name: "Zang Eto", sex: :f})

    {:ok, %{student: current}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Zang Abi", sex: :f})

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}")
    view |> element("#enroll-button") |> render_click()
    view |> element("#enroll-mode-existing") |> render_click()
    view |> form("#enroll-search-form", %{"q" => "Zang"}) |> render_change()

    assert has_element?(view, "#search-results li", "CM2 · 2024-2025")
    assert has_element?(view, "#search-enroll-#{former.id}")
    assert has_element?(view, "#search-enrolled-#{current.id}[disabled]")
    refute has_element?(view, "#search-enroll-#{current.id}")

    # A class of a past year offers no transfer: transfers stay within a year.
    {:ok, old_view, _} = live(conn, ~p"/school/classes/#{old_cg.id}")

    assert has_element?(
             old_view,
             "#withdraw-#{hd(Enrollment.list_roster(scope, old_cg)).enrollment.id}"
           )

    refute has_element?(old_view, "[id^='transfer-']")
  end

  test "transfer moves a student to another class", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view |> element("#transfer-#{e.id}-#{cg2.id}") |> render_click()

    assert [] = Enrollment.list_roster(scope, cg)
    assert [_] = Enrollment.list_roster(scope, cg2)
  end

  test "withdraw removes the enrollment", %{conn: conn, cg: cg, scope: scope} do
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#withdraw-#{e.id}") |> render_click()
    assert [] = Enrollment.list_roster(scope, cg)
  end

  test "cross-school class id is not found", %{conn: conn, actor: user} do
    other_head = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, other_school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: other_head}, %{
        name: "Autre"
      })

    other_scope = school_scope(other_head, other_school)

    {:ok, oy} =
      Organization.create_academic_year(other_scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} =
      Enrollment.create_class_group(other_scope, oy, %{label: "6e Z", level: "6ème"})

    _ = user

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}")
  end

  test "non-admin non-form-master member is redirected", ctx do
    %{school: school, cg: cg, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}")
  end

  test "the roster filters by sex and repeaters, and searches by name", ctx do
    %{conn: conn, cg: cg, scope: scope} = ctx
    {:ok, %{enrollment: a}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, %{enrollment: b}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Bob", sex: :m, repeater: true})

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    assert has_element?(view, "#roster-summary", "1 F · 1 G · 1 redoublant")

    view |> element("#roster-filter-f") |> render_click()
    assert has_element?(view, "#roster-row-#{a.id}")
    refute has_element?(view, "#roster-row-#{b.id}")

    view |> element("#roster-filter-repeaters") |> render_click()
    assert has_element?(view, "#roster-row-#{b.id}")
    refute has_element?(view, "#roster-row-#{a.id}")

    view |> element("#roster-filter-all") |> render_click()
    view |> form("#roster-search", %{"rq" => "aw"}) |> render_change()
    assert has_element?(view, "#roster-row-#{a.id}")
    refute has_element?(view, "#roster-row-#{b.id}")
  end

  test "the class menu sets the class's maximum and deletes an empty class", ctx do
    %{conn: conn, cg: cg, scope: scope, year: year} = ctx
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view |> element("#open-class-settings") |> render_click()
    view |> form("#class-settings-form", %{"max_size" => "30"}) |> render_submit()
    assert has_element?(view, "#class-size", "0 / 30")

    {:error, {:live_redirect, %{to: "/school/classes"}}} =
      view |> element("#delete-class") |> render_click()

    refute Enum.any?(Enrollment.list_class_groups(scope, year), &(&1.id == cg.id))
  end

  test "a refused maximum or delete says why", ctx do
    %{conn: conn, cg: cg, scope: scope, year: year} = ctx
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view |> element("#open-class-settings") |> render_click()
    view |> form("#class-settings-form", %{"max_size" => "500"}) |> render_submit()
    assert render(view) =~ "Entrez un nombre entre 1 et 200."

    TeacherAssistant.TeacherFixtures.close_year!(scope, year)

    view |> form("#class-settings-form", %{"max_size" => "30"}) |> render_submit()
    assert render(view) =~ "L&#39;année 2025-2026 est clôturée."

    view |> element("#delete-class") |> render_click()
    assert render(view) =~ "L&#39;année 2025-2026 est clôturée."
    assert Enum.any?(Enrollment.list_class_groups(scope, year), &(&1.id == cg.id))
  end

  test "delete is refused while the class has students", %{conn: conn, cg: cg, scope: scope} do
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#delete-class") |> render_click()
    assert render(view) =~ "retirez-les"
  end

  test "the class page has no fees link (fees deferred)", %{conn: conn, cg: cg} do
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}")
    refute has_element?(view, "#go-to-fees")
  end

  describe "form master access" do
    setup ctx do
      %{school: school, cg: cg, user: head, scope: scope} = ctx
      fm = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(school_scope(head, school), %{
          email: to_string(fm.email),
          roles: [:teacher]
        })

      {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: fm}, inv.token)
      {:ok, _} = TeacherAssistant.Enrollment.set_form_master(scope, cg, fm.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, fm.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      %{fm_conn: conn, fm: fm}
    end

    test "form master reaches the class and can enroll", %{fm_conn: conn, cg: cg, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      view |> element("#enroll-button") |> render_click()
      # a teacher who is form master records no parent (guardians are admin / conduct)
      refute has_element?(view, "#enroll-parent")
      refute has_element?(view, "#class-menu")

      view
      |> form("#enroll-form", %{"enroll" => %{"full_name" => "Zoe", "sex" => "f"}})
      |> render_submit()

      assert Enum.any?(Enrollment.list_roster(scope, cg), &(&1.student.full_name == "Zoe"))
    end

    test "a form master of another class is redirected", ctx do
      %{cg2: cg2, fm_conn: conn} = ctx
      # fm is form master of cg, not cg2
      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn, ~p"/school/classes/#{cg2.id}")
    end
  end
end
