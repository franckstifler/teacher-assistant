defmodule TeacherAssistantWeb.School.MembersLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  defp enter_school(conn, school) do
    post(conn, ~p"/workspaces/select/#{school.id}")
  end

  defp open_add(view, method \\ :phone) do
    view |> element("#open-add-member") |> render_click()
    if method == :email, do: view |> element("#method-email") |> render_click()
    view
  end

  defp open_member(view, membership_id) do
    view |> element("#member-row-#{membership_id}") |> render_click()
    view
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
    assert has_element?(view, "#members-list")
    refute has_element?(view, "#add-member-drawer")

    open_add(view, :email)
    assert has_element?(view, "#method-email[aria-checked=true]")
    refute has_element?(view, "#create-account-form")

    view
    |> form("#invite-form", %{
      "invite" => %{"email" => "prof@example.com", "roles" => ["teacher"]}
    })
    |> render_submit()

    assert has_element?(view, "#invitations-list", "prof@example.com")
    refute has_element?(view, "#add-member-drawer")
    assert render(view) =~ "1 invitation en attente"
  end

  test "an invitation whose email is refused says so and is not kept", %{
    conn: conn,
    actor: user
  } do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Courriel"
      })

    scope = school_scope(user, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    open_add(view, :email)

    html =
      view
      |> form("#invite-form", %{
        "invite" => %{"email" => "prof@undeliverable.test", "roles" => ["teacher"]}
      })
      |> render_submit()

    assert has_element?(view, "#add-member-error", "pas pu être envoyé")
    refute html =~ "Invitation envoyée"
    assert Accounts.list_pending_invitations(scope) == []
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

    conn = conn |> log_in_user(member) |> post(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#members-list")
    refute has_element?(view, "#open-add-member")
    # a read-only list: no row opens an editor
    refute has_element?(view, "button[id^='member-row-']")
    render_click(view, "open_add", %{})
    refute has_element?(view, "#add-member-drawer")
    # colleagues' password state is for staff managers only
    refute has_element?(view, "#members-list", "Actif")
    refute has_element?(view, "#members-list", "Mot de passe")
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

    html = view |> open_add() |> render()
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
    |> open_member(membership.id)
    |> form("#member-form", %{"member" => %{"status" => "titulaire"}})
    |> render_submit()

    refute has_element?(view, "#member-drawer")
    assert has_element?(view, "#member-row-#{membership.id}", "Titulaire")
    # the roles were left as they were
    assert Enum.find(Accounts.list_members(scope), &(&1.id == membership.id)).roles == [:teacher]

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

    conn = conn |> log_in_user(member) |> post(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    membership =
      scope
      |> Accounts.list_members()
      |> Enum.find(&(&1.user_id == member.id))

    render_click(view, "edit_member", %{"id" => membership.id})
    refute has_element?(view, "#member-form")

    render_submit(view, "save_member", %{
      "member_id" => membership.id,
      "member" => %{"status" => "titulaire"}
    })

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

    view
    |> open_member(m.id)
    |> form("#member-form", %{"member" => %{"service" => "12"}})
    |> render_submit()

    assert Enum.find(Accounts.list_members(scope), &(&1.id == m.id)).statutory_hours == 12
    assert has_element?(view, "#member-row-#{m.id}", "h/sem.")
  end

  test "an out-of-range service keeps the drawer open with the error", %{conn: conn, scope: scope} do
    m = TeacherAssistant.TeacherFixtures.membership_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    view
    |> open_member(m.id)
    |> form("#member-form", %{"member" => %{"service" => "50"}})
    |> render_submit()

    assert has_element?(view, "#member-drawer #member-service-error", "entre 1 et 40")
    assert has_element?(view, "#member-service[value='50']")
    assert Enum.find(Accounts.list_members(scope), &(&1.id == m.id)).statutory_hours == nil
  end

  describe "the member drawer" do
    test "the head changes roles with one save", %{conn: conn, scope: scope} do
      m = TeacherAssistant.TeacherFixtures.membership_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/school/members")

      view
      |> open_member(m.id)
      |> form("#member-form", %{"member" => %{"roles" => ["", "teacher", "hod"]}})
      |> render_submit()

      reloaded = Enum.find(Accounts.list_members(scope), &(&1.id == m.id))
      assert Enum.sort(reloaded.roles) == Enum.sort([:teacher, :hod])
      assert has_element?(view, "#member-row-#{m.id}", "Animateur péd.")
    end

    test "removing the last head's role is refused inside the drawer", %{
      conn: conn,
      scope: scope
    } do
      me = Enum.find(Accounts.list_members(scope), &(&1.user_id == scope.current_user.id))
      {:ok, view, _html} = live(conn, ~p"/school/members")

      view
      |> open_member(me.id)
      |> form("#member-form", %{"member" => %{"roles" => ["", "teacher"]}})
      |> render_submit()

      assert has_element?(view, "#member-drawer #member-error", "dernier chef")
      assert :head in Enum.find(Accounts.list_members(scope), &(&1.id == me.id)).roles
    end

    test "deactivating a member asks for confirmation and closes the drawer", %{
      conn: conn,
      scope: scope
    } do
      m = TeacherAssistant.TeacherFixtures.membership_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/school/members")

      open_member(view, m.id)
      assert has_element?(view, "#member-deactivate-#{m.id}[data-confirm]")
      view |> element("#member-deactivate-#{m.id}") |> render_click()

      refute has_element?(view, "#member-drawer")
      refute has_element?(view, "#member-row-#{m.id}")
      refute Enum.any?(Accounts.list_members(scope), &(&1.id == m.id))
    end

    test "Fermer closes the drawer without saving", %{conn: conn, scope: scope} do
      m = TeacherAssistant.TeacherFixtures.membership_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/school/members")

      open_member(view, m.id)
      assert has_element?(view, "#member-drawer")
      view |> element("#member-drawer footer button", "Fermer") |> render_click()
      refute has_element?(view, "#member-drawer")
    end
  end

  describe "search and role filter" do
    setup %{scope: scope} do
      {:ok, %{user: awa}} =
        Accounts.add_member_by_phone(scope, %{
          name: "Éloïse Awa",
          phone: "677445566",
          roles: [:bursar]
        })

      {:ok, %{user: ngo}} =
        Accounts.add_member_by_phone(scope, %{
          name: "Ngo Bilong",
          phone: "699112233",
          roles: [:teacher]
        })

      %{awa: awa, ngo: ngo}
    end

    test "search by name (accents ignored) and by phone digits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school/members")
      assert has_element?(view, "#members-list", "Éloïse Awa")
      assert has_element?(view, "#members-list", "Ngo Bilong")

      view |> form("#members-filter", %{"q" => "eloise"}) |> render_change()
      assert has_element?(view, "#members-list", "Éloïse Awa")
      refute has_element?(view, "#members-list", "Ngo Bilong")

      view |> form("#members-filter", %{"q" => "699 11"}) |> render_change()
      assert has_element?(view, "#members-list", "Ngo Bilong")
      refute has_element?(view, "#members-list", "Éloïse Awa")

      view |> form("#members-filter", %{"q" => "zzz"}) |> render_change()
      refute has_element?(view, "#members-list")
      assert render(view) =~ "Aucun membre ne correspond"
    end

    test "filter by role", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school/members")

      view |> form("#members-filter", %{"role" => "bursar"}) |> render_change()
      assert has_element?(view, "#members-list", "Éloïse Awa")
      refute has_element?(view, "#members-list", "Ngo Bilong")
    end

    test "the header counts members and accounts not yet used", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/school/members")
      assert html =~ "3 membres"
      assert html =~ "2 comptes en attente de première connexion"
    end
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
      |> open_add()
      |> form("#create-account-form", %{
        "account" => %{"name" => "Awa Nji", "phone" => "6 77 12 34 56", "roles" => ["teacher"]}
      })
      |> render_submit()

      assert has_element?(view, "#temporary-password-dialog")
      assert has_element?(view, "#temporary-password-dialog", "Compte créé")
      assert has_element?(view, "#temporary-password-dialog", "6 77 12 34 56")
      assert view |> element("#temporary-password") |> render() =~ ~r/[a-z]{4}-[a-z]{4}-\d{4}/
      assert has_element?(view, "#members-list", "Awa Nji")
      assert has_element?(view, "#members-list", "6 77 12 34 56")
      # the drawer is closed on success
      refute has_element?(view, "#add-member-drawer")

      view |> element("#close-temporary-password") |> render_click()
      refute has_element?(view, "#temporary-password-dialog")
      assert Enum.any?(Accounts.list_members(scope), &(&1.user.name == "Awa Nji"))
    end

    test "invalid phone shows a field error and keeps the drawer open", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school/members")
      refute has_element?(view, "#add-member-drawer")

      html =
        view
        |> open_add()
        |> form("#create-account-form", %{"account" => %{"name" => "X", "phone" => "12"}})
        |> render_submit()

      assert html =~ "numéro de téléphone"
      assert has_element?(view, "#add-member-drawer")
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
      |> open_add()
      |> form("#create-account-form", %{"account" => %{"name" => "Awa", "phone" => "677123456"}})
      |> render_submit()

      assert has_element?(view, "#add-member-drawer #add-member-error", "Déjà membre")
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
        |> open_add()
        |> form("#create-account-form", %{
          "account" => %{"name" => "Autre", "phone" => "677123456"}
        })
        |> render_submit()

      assert html =~ "Awa Nji"
      assert html =~ "Compte existant ajouté"
      refute has_element?(view, "#temporary-password-dialog")
    end

    test "each row shows the account state; the drawer explains it", %{
      conn: conn,
      scope: scope
    } do
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

      id = fn user -> member_for(scope, user.id).id end
      row = fn user -> "#member-row-#{id.(user)}" end

      assert has_element?(view, row.(pending), "Mot de passe temporaire")
      assert has_element?(view, row.(pending), "TÉL")
      assert has_element?(view, row.(expired), "Mot de passe expiré")
      assert has_element?(view, row.(settled), "Actif")
      assert has_element?(view, row.(linked), "Compte lié")
      assert has_element?(view, row.(scope.current_user), "Actif")

      note = fn user ->
        open_member(view, id.(user))
        view |> element("#member-account") |> render()
      end

      assert note.(pending) =~ "expire le"
      assert note.(expired) =~ "donnez-en un nouveau"
      assert note.(settled) =~ "Compte créé par l&#39;établissement"
      assert note.(linked) =~ "Créé par un autre établissement"
      assert note.(scope.current_user) =~ "Mot de passe géré par la personne"
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

      open_member(view, linked_m.id)
      refute has_element?(view, "#reset-password-#{linked_m.id}")

      open_member(view, own_m.id)
      assert has_element?(view, "#reset-password-#{own_m.id}")

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

      assert has_element?(view, "#member-row-#{shared_m.id}", "Mot de passe temporaire")

      open_member(view, shared_m.id)
      refute has_element?(view, "#reset-password-#{shared_m.id}")

      assert has_element?(
               view,
               "#member-account",
               "aussi utilisé dans un autre établissement"
             )
    end

    test "reset asks for confirmation first", %{conn: conn, scope: scope} do
      {:ok, %{user: own, temporary_password: first}} =
        Accounts.add_member_by_phone(scope, %{name: "Own", phone: "677000003", roles: [:teacher]})

      own_m = member_for(scope, own.id)
      {:ok, view, _html} = live(conn, ~p"/school/members")

      open_member(view, own_m.id)
      view |> element("#reset-password-#{own_m.id}") |> render_click()
      assert has_element?(view, "#confirm-reset-dialog", "Nouveau mot de passe pour Own")
      refute has_element?(view, "#temporary-password-dialog")

      # a real modal, named by its title; Escape backs out
      assert has_element?(
               view,
               ~s(#confirm-reset-dialog[role="dialog"][aria-modal="true"][aria-labelledby="confirm-reset-dialog-title"])
             )

      view |> element("#confirm-reset-dialog-box") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#confirm-reset-dialog")

      view |> element("#reset-password-#{own_m.id}") |> render_click()
      view |> element("#cancel-reset") |> render_click()
      refute has_element?(view, "#confirm-reset-dialog")

      view |> element("#reset-password-#{own_m.id}") |> render_click()
      view |> element("#confirm-reset") |> render_click()

      refute has_element?(view, "#confirm-reset-dialog")
      assert has_element?(view, "#temporary-password-dialog", "Mot de passe réinitialisé")
      # shown once: no Escape or backdrop, only « C'est noté » closes it
      refute has_element?(view, "#temporary-password-dialog-box[phx-window-keydown]")
      new_password = view |> element("#temporary-password") |> render()
      assert new_password =~ ~r/[a-z]{4}-[a-z]{4}-\d{4}/
      refute new_password =~ first
    end
  end

  describe "account status after the operator console's reset rules" do
    defp membership_of(scope, user_id),
      do: Enum.find(Accounts.list_members(scope), &(&1.user_id == user_id))

    test "a co-head is not said to use another school", %{conn: conn, scope: scope} do
      {:ok, %{user: co_head}} =
        Accounts.add_member_by_phone(scope, %{name: "Co", phone: "677000009", roles: [:head]})

      {:ok, view, _html} = live(conn, ~p"/school/members")
      m = membership_of(scope, co_head.id)
      open_member(view, m.id)

      refute view |> element("#member-account") |> render() =~ "autre établissement"
      refute has_element?(view, "#reset-password-#{m.id}")
    end

    test "an invited member reset by the head shows the temporary password",
         %{conn: conn, scope: scope} do
      invited = TeacherAssistant.TeacherFixtures.user_fixture()

      m =
        TeacherAssistant.TeacherFixtures.membership_fixture(scope, %{
          user: invited,
          roles: [:teacher]
        })

      {:ok, view, _html} = live(conn, ~p"/school/members")
      open_member(view, m.id)
      refute view |> element("#member-account") |> render() =~ "géré par la personne"

      view |> element("#reset-password-#{m.id}") |> render_click()
      view |> element("#confirm-reset") |> render_click()

      assert has_element?(view, "#member-row-#{m.id}", "Mot de passe temporaire")
    end
  end
end
