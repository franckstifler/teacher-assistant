defmodule TeacherAssistant.NotificationsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Notifications, TeacherFixtures}
  alias TeacherAssistant.Accounts.Notification

  setup do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    t = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})
    other = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})
    %{head: head, t: t, other: other}
  end

  defp remind(scope, ids, subject \\ "Maths") do
    Notifications.deliver(
      scope,
      :entry_reminder,
      ids,
      %{subject: subject, class: "3e A", sequence: 2},
      "/school/courses"
    )
  end

  test "deliver writes one row per recipient and only the recipient sees it", ctx do
    Notifications.subscribe(ctx.t.current_user.id)
    id = ctx.t.current_user.id
    assert :ok = remind(ctx.head, [id, id])
    assert_receive :notifications_changed

    assert %{unread: 1, latest: [n]} = Notifications.bell(ctx.t)
    assert n.kind == :entry_reminder
    assert n.params == %{"subject" => "Maths", "class" => "3e A", "sequence" => "2"}
    assert n.link == "/school/courses"
    assert n.read_at == nil

    assert %{unread: 0, latest: []} = Notifications.bell(ctx.other)
    assert %{unread: 0, latest: []} = Notifications.bell(ctx.head)
  end

  test "nobody creates a notification through the action", ctx do
    assert {:error, %Ash.Error.Forbidden{}} =
             Notification
             |> Ash.Changeset.for_create(
               :deliver,
               %{
                 recipient_user_id: ctx.t.current_user.id,
                 kind: :entry_reminder,
                 params: %{},
                 link: "/school"
               },
               scope: ctx.head
             )
             |> Ash.create()
  end

  test "a link must be a path of the app", ctx do
    for link <- ["https://evil.test", "//evil.test", "school"] do
      assert_raise ArgumentError, fn ->
        Notifications.deliver(ctx.head, :entry_reminder, [ctx.t.current_user.id], %{}, link)
      end
    end
  end

  test "open marks read and returns the link; another member's id does nothing", ctx do
    remind(ctx.head, [ctx.t.current_user.id])
    %{latest: [n]} = Notifications.bell(ctx.t)

    assert :error = Notifications.open(ctx.other, n.id)
    assert :error = Notifications.open(ctx.t, "not-a-uuid")
    assert %{unread: 1} = Notifications.bell(ctx.t)

    Notifications.subscribe(ctx.t.current_user.id)
    assert {:ok, "/school/courses"} = Notifications.open(ctx.t, n.id)
    assert_receive :notifications_changed
    assert %{unread: 0, latest: [%{read_at: %DateTime{} = read_at}]} = Notifications.bell(ctx.t)

    # Opening again keeps the first read time.
    assert {:ok, _} = Notifications.open(ctx.t, n.id)
    assert %{latest: [%{read_at: ^read_at}]} = Notifications.bell(ctx.t)
  end

  test "the inbox lists newest first; mark_all_read clears the count", ctx do
    for s <- ~w(Maths Anglais SVT), do: remind(ctx.head, [ctx.t.current_user.id], s)

    page = Notifications.inbox(ctx.t, 1)
    assert page.count == 3
    assert Enum.map(page.results, & &1.params["subject"]) == ~w(SVT Anglais Maths)
    assert Notifications.inbox(ctx.other, 1).count == 0

    assert :ok = Notifications.mark_all_read(ctx.t)
    assert %{unread: 0, latest: [_, _, _]} = Notifications.bell(ctx.t)
  end

  test "the bell keeps the 8 newest and counts them all", ctx do
    for n <- 1..9, do: remind(ctx.head, [ctx.t.current_user.id], "S#{n}")
    assert %{unread: 9, latest: latest} = Notifications.bell(ctx.t)
    assert length(latest) == 8
    assert hd(latest).params["subject"] == "S9"
  end

  test "a member of two schools sees each school's own notices", ctx do
    %{scope: head_b} = TeacherFixtures.setup_complete_school_fixture()

    %{scope: t_in_b} =
      TeacherFixtures.school_teacher_fixture(head_b, %{teacher: ctx.t.current_user})

    remind(ctx.head, [ctx.t.current_user.id])
    assert %{unread: 1} = Notifications.bell(ctx.t)
    assert %{unread: 0, latest: []} = Notifications.bell(t_in_b)
  end

  test "admin_ids are the active Proviseur and Censeur", ctx do
    censeur = TeacherFixtures.member_scope_fixture(ctx.head, %{roles: [:vice_principal]})

    assert Enum.sort(Notifications.admin_ids(ctx.t)) ==
             Enum.sort([ctx.head.current_user.id, censeur.current_user.id])
  end

  test "accepting an invitation notifies the admins, not the newcomer" do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    user = TeacherFixtures.user_fixture()

    {:ok, inv} =
      TeacherAssistant.Accounts.invite_member(head, %{
        email: to_string(user.email),
        roles: [:teacher]
      })

    {:ok, _} =
      TeacherAssistant.Accounts.accept_invitation(
        %TeacherAssistant.Scope{current_user: user},
        inv.token
      )

    assert [%{kind: :member_joined, link: "/school/members"} = n] =
             Notifications.inbox(head, 1).results

    assert n.params["roles"] == "Enseignant"
  end
end
