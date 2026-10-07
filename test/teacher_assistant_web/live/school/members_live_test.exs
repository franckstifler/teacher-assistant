defmodule TeacherAssistantWeb.School.MembersLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  defp enter_school(conn, school) do
    get(conn, ~p"/workspaces/select/#{school.id}")
  end

  test "head sees members, can invite, and sees the pending invitation", %{
    conn: conn,
    actor: user
  } do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Membres"
      })

    scope = school_scope(user, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#school-members")
    assert has_element?(view, "#members-table")
    assert has_element?(view, "#invite-form")

    view
    |> form("#invite-form", %{
      "invite" => %{"email" => "prof@example.com", "roles" => ["teacher"]}
    })
    |> render_submit()

    assert has_element?(view, "#invitations-list", "prof@example.com")
  end

  test "a non-head member does not see the invite form", %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Gate"
      })

    scope = school_scope(head, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} =
      Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: member}, inv.token)

    conn = conn |> log_in_user(member) |> get(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#members-table")
    refute has_element?(view, "#invite-form")
    # colleagues' password state is for staff managers only
    refute has_element?(view, "#members-table th", "Compte")
    refute has_element?(view, "#members-table", "Mot de passe géré par la personne")
  end

  test "invite form includes the employment-type options", %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Emploi"
      })

    scope = school_scope(user, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    html = render(view)
    assert html =~ "Titulaire"
    assert html =~ "Contractuel"
    assert html =~ "Vacataire"
  end

  test "head can set a member's employment type", %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Statut"
      })

    scope = school_scope(head, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} =
      Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: member}, inv.token)

    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    membership =
      scope
      |> Accounts.list_members()
      |> Enum.find(&(&1.user_id == member.id))

    view
    |> element("#member-status-form-#{membership.id}")
    |> render_change(%{"status" => "titulaire"})

    assert has_element?(view, "#member-row-#{membership.id}", "Titulaire")

    reloaded =
      scope
      |> Accounts.list_members()
      |> Enum.find(&(&1.id == membership.id))

    assert reloaded.status == :titulaire
  end

  test "non-head cannot change employment type", %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Statut Gate"
      })

    scope = school_scope(head, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} =
      Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: member}, inv.token)

    conn = conn |> log_in_user(member) |> get(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    membership =
      scope
      |> Accounts.list_members()
      |> Enum.find(&(&1.user_id == member.id))

    refute has_element?(view, "#member-status-form-#{membership.id}")

    render_change(view, "set_status", %{"id" => membership.id, "status" => "titulaire"})

    reloaded =
      scope
      |> Accounts.list_members()
      |> Enum.find(&(&1.id == membership.id))

    assert reloaded.status == nil
  end

  test "the head sets a teacher's own weekly service (spec J2)", %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Service"
      })

    scope = school_scope(user, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    m = TeacherAssistant.TeacherFixtures.membership_fixture(scope)
    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    view |> form("#service-#{m.id}", %{service: "12"}) |> render_submit()
    assert Enum.find(Accounts.list_members(scope), &(&1.id == m.id)).statutory_hours == 12
  end

  describe "phone accounts" do
    defp member_for(scope, user_id),
      do: Enum.find(Accounts.list_members(scope), &(&1.user_id == user_id))

    defp set_user_columns!(user_id, sets) do
      {sql, values} =
        sets
        |> Enum.with_index(1)
        |> Enum.map_reduce([], fn {{col, val}, i}, acc -> {"#{col} = $#{i}", acc ++ [val]} end)

      TeacherAssistant.Repo.query!(
        "UPDATE users SET #{Enum.join(sql, ", ")} WHERE id = $#{length(values) + 1}",
        values ++ [Ecto.UUID.dump!(user_id)]
      )
    end

    test "head creates an account and sees the temporary password once", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _html} = live(conn, ~p"/school/members")

      view
      |> form("#create-account-form", %{
        "account" => %{"name" => "Awa Nji", "phone" => "6 77 12 34 56", "roles" => ["teacher"]}
      })
      |> render_submit()

      assert has_element?(view, "#temporary-password-dialog")
      assert has_element?(view, "#temporary-password-dialog", "Compte créé")
      assert has_element?(view, "#temporary-password-dialog", "6 77 12 34 56")
      assert view |> element("#temporary-password") |> render() =~ ~r/[a-z]{4}-[a-z]{4}-\d{4}/
      assert has_element?(view, "#members-table", "Awa Nji")
      assert has_element?(view, "#members-table", "6 77 12 34 56")
      # the drawer is closed on success
      refute has_element?(view, "#add-member-drawer[data-open]")
      assert_push_event(view, "js-exec", %{to: "#add-member-drawer", attr: "data-hide"})

      view |> element("#close-temporary-password") |> render_click()
      refute has_element?(view, "#temporary-password-dialog")
      assert Enum.any?(Accounts.list_members(scope), &(&1.user.name == "Awa Nji"))
    end

    test "invalid phone shows a field error and keeps the drawer open", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school/members")
      refute has_element?(view, "#add-member-drawer[data-open]")

      html =
        view
        |> form("#create-account-form", %{"account" => %{"name" => "X", "phone" => "12"}})
        |> render_submit()

      assert html =~ "numéro de téléphone"
      assert has_element?(view, "#add-member-drawer[data-open]")
      assert has_element?(view, "#add-member-drawer #create-account-form", "n'est pas valide")
      refute has_element?(view, "#temporary-password-dialog")
    end

    test "an already-member number shows the error inside the drawer", %{
      conn: conn,
      scope: scope
    } do
      {:ok, _} =
        Accounts.add_member_by_phone(scope, %{name: "Awa", phone: "677123456", roles: [:teacher]})

      {:ok, view, _html} = live(conn, ~p"/school/members")

      view
      |> form("#create-account-form", %{"account" => %{"name" => "Awa", "phone" => "677123456"}})
      |> render_submit()

      assert has_element?(view, "#add-member-drawer[data-open] #add-member-error", "Déjà membre")
      refute has_element?(view, "#temporary-password-dialog")
    end

    test "an existing account is linked without a password", %{conn: conn} do
      %{scope: other} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

      {:ok, _} =
        Accounts.add_member_by_phone(other, %{
          name: "Awa Nji",
          phone: "677123456",
          roles: [:teacher]
        })

      {:ok, view, _html} = live(conn, ~p"/school/members")

      html =
        view
        |> form("#create-account-form", %{
          "account" => %{"name" => "Autre", "phone" => "677123456"}
        })
        |> render_submit()

      assert html =~ "Awa Nji"
      assert html =~ "Compte existant ajouté"
      refute has_element?(view, "#temporary-password-dialog")
    end

    test "the Compte column shows each account's state", %{conn: conn, scope: scope} do
      {:ok, %{user: pending}} =
        Accounts.add_member_by_phone(scope, %{
          name: "Pending",
          phone: "677000011",
          roles: [:teacher]
        })

      {:ok, %{user: expired}} =
        Accounts.add_member_by_phone(scope, %{
          name: "Expired",
          phone: "677000012",
          roles: [:teacher]
        })

      {:ok, %{user: settled}} =
        Accounts.add_member_by_phone(scope, %{
          name: "Settled",
          phone: "677000013",
          roles: [:teacher]
        })

      %{scope: other} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

      {:ok, %{user: linked}} =
        Accounts.add_member_by_phone(other, %{
          name: "Linked",
          phone: "677000014",
          roles: [:teacher]
        })

      {:ok, _} =
        Accounts.add_member_by_phone(scope, %{
          name: "Linked",
          phone: "677000014",
          roles: [:teacher]
        })

      set_user_columns!(expired.id, temporary_password_expires_at: ~U[2020-01-01 00:00:00Z])
      set_user_columns!(settled.id, must_change_password: false)

      {:ok, view, _html} = live(conn, ~p"/school/members")

      row = fn user -> "#member-row-#{member_for(scope, user.id).id}" end

      assert has_element?(view, row.(pending), "Mot de passe temporaire")
      assert has_element?(view, row.(pending), "expire le")
      assert has_element?(view, row.(pending), "TÉL")
      assert has_element?(view, row.(expired), "Mot de passe expiré")
      assert has_element?(view, row.(settled), "Compte créé par l'établissement")
      assert has_element?(view, row.(linked), "Compte lié")
      assert has_element?(view, row.(scope.current_user), "Mot de passe géré par la personne")
    end

    test "reset button only for accounts this school created", %{conn: conn, scope: scope} do
      {:ok, %{user: own}} =
        Accounts.add_member_by_phone(scope, %{name: "Own", phone: "677000001", roles: [:teacher]})

      %{scope: other} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

      {:ok, %{user: linked}} =
        Accounts.add_member_by_phone(other, %{
          name: "Linked",
          phone: "677000002",
          roles: [:teacher]
        })

      {:ok, _} =
        Accounts.add_member_by_phone(scope, %{
          name: "Linked",
          phone: "677000002",
          roles: [:teacher]
        })

      {:ok, view, _html} = live(conn, ~p"/school/members")
      own_m = member_for(scope, own.id)
      linked_m = member_for(scope, linked.id)

      assert has_element?(view, "#reset-password-#{own_m.id}")
      refute has_element?(view, "#reset-password-#{linked_m.id}")

      view |> element("#reset-password-#{own_m.id}") |> render_click()
      view |> element("#confirm-reset") |> render_click()
      assert has_element?(view, "#temporary-password-dialog")
    end

    test "no reset for an account this school created that is active in another school", %{
      conn: conn,
      scope: scope
    } do
      {:ok, %{user: shared}} =
        Accounts.add_member_by_phone(scope, %{
          name: "Shared",
          phone: "677000005",
          roles: [:teacher]
        })

      %{scope: other} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

      {:ok, _} =
        Accounts.add_member_by_phone(other, %{
          name: "Shared",
          phone: "677000005",
          roles: [:teacher]
        })

      {:ok, view, _html} = live(conn, ~p"/school/members")
      shared_m = member_for(scope, shared.id)

      refute has_element?(view, "#reset-password-#{shared_m.id}")
      assert has_element?(view, "#member-row-#{shared_m.id}", "Mot de passe temporaire")

      assert has_element?(
               view,
               "#member-row-#{shared_m.id}",
               "aussi utilisé dans un autre établissement"
             )
    end

    test "reset asks for confirmation first", %{conn: conn, scope: scope} do
      {:ok, %{user: own, temporary_password: first}} =
        Accounts.add_member_by_phone(scope, %{name: "Own", phone: "677000003", roles: [:teacher]})

      own_m = member_for(scope, own.id)
      {:ok, view, _html} = live(conn, ~p"/school/members")

      view |> element("#reset-password-#{own_m.id}") |> render_click()
      assert has_element?(view, "#confirm-reset-dialog", "Nouveau mot de passe pour Own")
      refute has_element?(view, "#temporary-password-dialog")

      view |> element("#cancel-reset") |> render_click()
      refute has_element?(view, "#confirm-reset-dialog")

      view |> element("#reset-password-#{own_m.id}") |> render_click()
      view |> element("#confirm-reset") |> render_click()

      refute has_element?(view, "#confirm-reset-dialog")
      assert has_element?(view, "#temporary-password-dialog", "Mot de passe réinitialisé")
      new_password = view |> element("#temporary-password") |> render()
      assert new_password =~ ~r/[a-z]{4}-[a-z]{4}-\d{4}/
      refute new_password =~ first
    end
  end
end
