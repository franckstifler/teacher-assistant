# KLM8 — Staff in-app notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In-app notifications for staff: correction requests reach the Proviseur and Censeur, decisions
reach the requesting teacher, and « Relancer » on the séquence tracking grid reminds a late teacher; a live
bell in the app shell and a `/school/notifications` page show them.

**Architecture:** One tenant-scoped `Accounts.Notification` resource holding `kind` + short string `params`
(the text is built at display time, so it follows the reader's language). `TeacherAssistant.Notifications`
is the only writer (`deliver/5`, `authorize?: false` inside, like `Mark.Journal.record!/2`) and broadcasts
`:notifications_changed` on `"notifications:<user_id>"`. Triggers live in the `Assessment` domain functions,
after the action commits. An `Academics.EntryReminder` log (unique per course × séquence × school day) backs
« Relancer ». A LiveView `on_mount` hook (`NotificationHooks`) puts the bell data into
`current_scope.capabilities.notifications`, subscribes, and handles the bell's two events, so no existing
LiveView changes to get the bell.

**Tech Stack:** Phoenix 1.8 LiveView (on_mount hooks, `attach_hook`), Phoenix.PubSub, Ash 3 (policies,
offset pagination, bulk create/update, identities), AshPostgres, Gettext.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"KLM8 — Staff in-app notifications".

## Global Constraints

- Worktree `.claude/worktrees/klm8`, branch `klm8-notifications`, `MIX_TEST_PARTITION=8` for every
  `mix test` (the user runs parallel sessions). Stage explicit paths only — never `git commit -a`.
- Migrations: `mix ash.codegen --dev` while iterating; one named `mix ash.codegen klm8_notifications` in
  Task 7; read it (two new tables only); `mix ash.codegen --check` clean at the end. Never write a
  migration by hand.
- **In-app only, staff only**; no parent messages, e-mail, SMS, templates or preferences.
- `Notification` (Accounts domain, tenant-scoped): `recipient_user_id`, `kind` enum
  `:correction_requested | :correction_decided | :entry_reminder`, `params` (map of short strings), `link`
  (an app path), `read_at`, timestamps. Read and mark-read by the recipient only; created only through
  `Notifications.deliver/5`. (The spec writes `deliver(kind, recipients, params, link)`; the scope is added
  first because the row needs the school as tenant.)
- `EntryReminder`: course (teaching context), séquence, sent by, `sent_on` (school-local day),
  `inserted_at`; at most one per course × séquence × day (identity).
- Triggers: a correction request notifies every member holding `:head` or `:vice_principal`; a decision
  notifies the requesting teacher, with the decision. Nobody is notified of their own action.
- Reminder text: « Saisie en retard : <matière> · <classe> · <séquence> ». A second reminder the same day is
  refused quietly (no error shown, no second notification).
- Bell: unread count (live via PubSub), menu with the 8 newest, « Tout voir » → `/school/notifications`
  (all members): newest first, unread in bold, « Tout marquer comme lu »; opening one marks it read and
  follows its link.
- Strings through gettext; after `mix gettext.extract --merge`, fill every new `en` msgstr and clear new
  fuzzy flags.
- `mix precommit` before the last commit (it does **not** gate on warnings — also run
  `mix compile --warnings-as-errors`; its format step rewrites files, stage them).

## Review Focus

1. A teacher who is a member of two schools gets a notice in school A, then switches to school B — B's bell
   shows nothing from A (test in Task 1).
2. A crafted « open » event carrying someone else's notification id — nothing happens, the owner's notice
   stays unread (test in Task 1).
3. An approval that fails because the request is stale — the teacher gets no « décidée » notice (test in
   Task 2).
4. Two admins (or a double click) remind the same course the same day — one reminder row, one notification;
   « Relancer tous les retards » run twice sends nothing the second time (tests in Task 3 and Task 6).
5. An admin who teaches requests a correction on their own course — the other admins are notified, they are
   not (test in Task 2).

---

### Task 0: Worktree

- [ ] **Step 1**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/klm8 -b klm8-notifications main
cd .claude/worktrees/klm8 && mix deps.get
MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs
```

Expected: 0 failures. Every later command runs inside `.claude/worktrees/klm8`.

---

### Task 1: `Notification` resource and the `Notifications` module

**Files:**
- Create: `lib/teacher_assistant/accounts/notification_kind.ex`
- Create: `lib/teacher_assistant/accounts/notification.ex`
- Create: `lib/teacher_assistant/notifications.ex`
- Modify: `lib/teacher_assistant/accounts.ex` (register the resource)
- Test: `test/teacher_assistant/notifications_test.exs`

**Interfaces:**
- Produces:
  - `TeacherAssistant.Notifications.deliver(%Scope{}, kind :: atom, recipient_ids :: [uuid], params :: map, link :: String.t()) :: :ok`
    (raises `ArgumentError` when `link` is not an app path such as `"/school/…"`)
  - `Notifications.subscribe(user_id) :: :ok` — messages arrive as the bare atom `:notifications_changed`
  - `Notifications.bell(%Scope{}) :: %{unread: non_neg_integer, latest: [%Notification{}]}` (8 newest)
  - `Notifications.inbox(%Scope{}, page :: pos_integer) :: %Ash.Page.Offset{results, count}` (30 per page)
  - `Notifications.page_size() :: 30`
  - `Notifications.open(%Scope{}, id) :: {:ok, link} | :error` (marks read)
  - `Notifications.mark_all_read(%Scope{}) :: :ok`
  - `Notifications.admin_ids(%Scope{}) :: [uuid]` — active members holding `:head` or `:vice_principal`
  - `%Notification{kind, params (string keys and string values), link, read_at, inserted_at}`

- [ ] **Step 1: Write the failing test**

```elixir
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
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_TEST_PARTITION=8 mix test test/teacher_assistant/notifications_test.exs`
Expected: compile error — `TeacherAssistant.Notifications` / `Accounts.Notification` undefined.

- [ ] **Step 3: Write the enum, the resource and the module**

`lib/teacher_assistant/accounts/notification_kind.ex`:

```elixir
defmodule TeacherAssistant.Accounts.NotificationKind do
  @moduledoc "Spec KLM8: what a staff notification is about."
  use Ash.Type.Enum, values: [:correction_requested, :correction_decided, :entry_reminder]
end
```

`lib/teacher_assistant/accounts/notification.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Notification do
  @moduledoc """
  Spec KLM8: one in-app notice to one staff member. The text is not stored: it is
  built at display time from `kind` and `params` (short strings), so it follows the
  reader's language. Rows are written only by `TeacherAssistant.Notifications.deliver/5`;
  the recipient alone reads them and marks them read.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "notifications"
    repo TeacherAssistant.Repo

    custom_indexes do
      # The bell and the inbox: one member's notices, newest first.
      index [:recipient_user_id, :inserted_at]
    end

    references do
      reference :recipient, on_delete: :delete
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    read :inbox do
      pagination offset?: true, countable: true, required?: false, default_limit: 30
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :deliver do
      accept [:recipient_user_id, :kind, :params, :link]
    end

    update :mark_read do
      change set_attribute(:read_at, expr(now()))
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if expr(recipient_user_id == ^actor(:id))
    end

    policy action(:mark_read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if expr(recipient_user_id == ^actor(:id))
    end

    # Written only by `Notifications.deliver/5`, which bypasses this (`authorize?: false`).
    policy action(:deliver) do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, TeacherAssistant.Accounts.NotificationKind,
      allow_nil?: false,
      public?: true

    # Short strings for the text (student, subject, class, …), string keys.
    attribute :params, :map, allow_nil?: false, default: %{}, public?: true
    # An app path, followed when the notice is opened.
    attribute :link, :string, allow_nil?: false, public?: true
    attribute :read_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :recipient, TeacherAssistant.Accounts.User do
      source_attribute :recipient_user_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
```

In `lib/teacher_assistant/accounts.ex`, inside `resources do`, after `resource SchoolMembership`:

```elixir
    resource TeacherAssistant.Accounts.Notification
```

`lib/teacher_assistant/notifications.ex`:

```elixir
defmodule TeacherAssistant.Notifications do
  @moduledoc """
  Spec KLM8: staff in-app notifications. `deliver/5` is the only way one is created —
  and the single place a future e-mail or SMS channel plugs into. The recipient reads
  them and marks them read. Every change is broadcast to the recipient on
  `"notifications:<user_id>"` as `:notifications_changed`.
  """
  require Ash.Query

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.{Notification, SchoolRole}
  alias TeacherAssistant.Scope

  @pubsub TeacherAssistant.PubSub
  @page_size 30
  @bell_size 8

  def page_size, do: @page_size

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(user_id))

  @doc """
  One notification per recipient (duplicates dropped) in the scope's school, then a
  broadcast to each. `params` values become strings; `link` must be an app path.
  Callers pass recipients already without the acting user.
  """
  def deliver(%Scope{current_workspace: %{id: workspace_id}}, kind, recipient_ids, params, link) do
    link = app_path!(link)
    params = Map.new(params, fn {key, value} -> {to_string(key), to_string(value)} end)

    case Enum.uniq(recipient_ids) do
      [] ->
        :ok

      ids ->
        # The sanctioned bypass of `:deliver`'s forbid-all policy.
        %Ash.BulkResult{status: :success} =
          ids
          |> Enum.map(&%{recipient_user_id: &1, kind: kind, params: params, link: link})
          |> Ash.bulk_create(Notification, :deliver,
            tenant: workspace_id,
            authorize?: false,
            return_errors?: true
          )

        Enum.each(ids, &broadcast/1)
    end
  end

  @doc "The header bell: unread count and the newest notices."
  def bell(%Scope{} = scope) do
    latest =
      Notification
      |> Ash.Query.for_read(:inbox, %{}, scope: scope)
      |> Ash.Query.limit(@bell_size)
      |> Ash.read!()

    %{unread: unread_count(scope), latest: latest}
  end

  @doc "One page (from 1) of the scope's notices, newest first, with the total count."
  def inbox(%Scope{} = scope, page) when is_integer(page) and page > 0 do
    Notification
    |> Ash.Query.for_read(:inbox, %{}, scope: scope)
    |> Ash.read!(page: [limit: @page_size, offset: (page - 1) * @page_size, count: true])
  end

  @doc "Marks the scope's notice `id` read and returns its link; `:error` when not theirs."
  def open(%Scope{} = scope, id) do
    with {:ok, %Notification{} = n} <- Ash.get(Notification, id, scope: scope),
         {:ok, n} <- mark_read(scope, n) do
      {:ok, n.link}
    else
      _ -> :error
    end
  end

  def mark_all_read(%Scope{current_user: %{id: user_id}} = scope) do
    Notification
    |> Ash.Query.filter(recipient_user_id == ^user_id and is_nil(read_at))
    |> Ash.bulk_update!(:mark_read, %{}, scope: scope, strategy: [:atomic, :stream])

    broadcast(user_id)
  end

  @doc "The active members who decide corrections (Proviseur, Censeur)."
  def admin_ids(%Scope{} = scope) do
    admin = SchoolRole.axis(:admin)
    for m <- Accounts.list_members(scope), Enum.any?(m.roles, &(&1 in admin)), do: m.user_id
  end

  defp unread_count(scope),
    do: Notification |> Ash.Query.filter(is_nil(read_at)) |> Ash.count!(scope: scope)

  # The first read time is kept.
  defp mark_read(_scope, %Notification{read_at: %DateTime{}} = n), do: {:ok, n}

  defp mark_read(scope, n) do
    with {:ok, n} <- n |> Ash.Changeset.for_update(:mark_read, %{}, scope: scope) |> Ash.update() do
      broadcast(n.recipient_user_id)
      {:ok, n}
    end
  end

  defp topic(user_id), do: "notifications:#{user_id}"

  defp broadcast(user_id),
    do: Phoenix.PubSub.broadcast(@pubsub, topic(user_id), :notifications_changed)

  defp app_path!("//" <> _ = link), do: raise(ArgumentError, "not an app path: #{inspect(link)}")
  defp app_path!("/" <> _ = link), do: link
  defp app_path!(link), do: raise(ArgumentError, "not an app path: #{inspect(link)}")
end
```

- [ ] **Step 4: Generate the dev migration and run the test**

```bash
mix ash.codegen --dev
MIX_TEST_PARTITION=8 mix test test/teacher_assistant/notifications_test.exs
```

Expected: PASS (8 tests). If `Ash.read!` on `:inbox` without `page:` complains about pagination, the
`required?: false` option is missing — fix the resource, not the call.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/accounts/notification_kind.ex lib/teacher_assistant/accounts/notification.ex \
  lib/teacher_assistant/notifications.ex lib/teacher_assistant/accounts.ex \
  test/teacher_assistant/notifications_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: staff notifications — recipient-only notices, delivered and broadcast in one place"
```

---

### Task 2: Correction requests and decisions notify

**Files:**
- Modify: `lib/teacher_assistant/assessment.ex` (`request_correction/2`, `decide_correction/3`, two private
  notifiers, `alias TeacherAssistant.Notifications`)
- Test: `test/teacher_assistant/academics/mark_correction_notifications_test.exs`

**Interfaces:**
- Consumes: `Notifications.deliver/5`, `Notifications.admin_ids/1`, `Notifications.bell/1` (Task 1).
- Produces: notices with these params (string keys):
  - `:correction_requested` → `teacher`, `student`, `subject`, `class`, `assessment`; link
    `/school/corrections/review`
  - `:correction_decided` → `decision` (`"approved"` | `"refused"`), `student`, `subject`, `class`,
    `assessment`; link `/school/corrections`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.MarkCorrectionNotificationsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Notifications, TeacherFixtures}
  alias TeacherAssistant.Academics.Reference
  import TeacherAssistant.MarksFixtures, only: [lock!: 2]

  setup do
    world = TeacherAssistant.MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    censeur = TeacherFixtures.member_scope_fixture(world.head, %{roles: [:vice_principal]})
    Map.put(world, :censeur, censeur)
  end

  defp lock(ctx), do: lock!(ctx, Date.add(Reference.today(), -1))
  defp unlock(ctx), do: lock!(ctx, Date.add(Reference.today(), 30))

  defp request(ctx, scope \\ nil, assessment \\ nil) do
    Assessment.request_correction(scope || ctx.t, %{
      assessment_id: (assessment || ctx.a).id,
      student_id: ctx.s1.id,
      requested_status: :graded,
      requested_score: Decimal.new(14),
      motive: :erreur_saisie
    })
  end

  test "a request notifies the Proviseur and the Censeur, not the teacher", ctx do
    lock(ctx)
    {:ok, _} = request(ctx)

    assert %{unread: 1, latest: [n]} = Notifications.bell(ctx.censeur)
    assert n.kind == :correction_requested
    assert n.link == "/school/corrections/review"
    teacher = ctx.t.current_user

    assert n.params == %{
             "teacher" => to_string(teacher.name || teacher.email),
             "student" => "Awa",
             "subject" => "Maths",
             "class" => ctx.cg.label,
             "assessment" => "Devoir 1"
           }

    assert %{unread: 1} = Notifications.bell(ctx.head)
    assert %{unread: 0} = Notifications.bell(ctx.t)
  end

  test "approving and refusing notify the requesting teacher with the decision", ctx do
    lock(ctx)
    {:ok, c} = request(ctx)
    {:ok, _} = Assessment.approve_correction(ctx.censeur, c)

    assert %{latest: [n]} = Notifications.bell(ctx.t)
    assert n.kind == :correction_decided
    assert n.link == "/school/corrections"
    assert %{"decision" => "approved", "student" => "Awa", "assessment" => "Devoir 1"} = n.params

    {:ok, c2} =
      Assessment.request_correction(ctx.t, %{
        assessment_id: ctx.a.id,
        student_id: ctx.s1.id,
        requested_status: :graded,
        requested_score: Decimal.new(15),
        motive: :erreur_saisie
      })

    {:ok, _} = Assessment.refuse_correction(ctx.head, c2)
    assert %{unread: 2, latest: [%{params: %{"decision" => "refused"}} | _]} = Notifications.bell(ctx.t)
    # The deciders are not notified of their own decision.
    assert %{unread: 2} = Notifications.bell(ctx.censeur)
  end

  test "a stale approval notifies nobody", ctx do
    lock(ctx)
    {:ok, c} = request(ctx)
    unlock(ctx)
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(9)}])
    lock(ctx)

    assert {:error, _} = Assessment.approve_correction(ctx.censeur, c)
    assert %{unread: 0} = Notifications.bell(ctx.t)
  end

  test "an admin who requests on their own course is not notified of it", ctx do
    {:ok, tc} =
      Curriculum.assign_teacher(ctx.head, ctx.cg, ctx.head.current_user, %{subject: "SVT"})

    {:ok, a} = Assessment.create_assessment(ctx.head, tc, ctx.seq, %{label: "Interro SVT"})
    :ok = Assessment.upsert_marks(ctx.head, a, [%{student_id: ctx.s1.id, score: Decimal.new(9)}])
    lock(ctx)

    {:ok, _} = request(ctx, ctx.head, a)
    assert %{unread: 0} = Notifications.bell(ctx.head)
    assert %{unread: 1} = Notifications.bell(ctx.censeur)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_TEST_PARTITION=8 mix test test/teacher_assistant/academics/mark_correction_notifications_test.exs`
Expected: FAIL — `unread: 0` where 1 is expected (no trigger yet).

- [ ] **Step 3: Implement**

In `lib/teacher_assistant/assessment.ex`, add `alias TeacherAssistant.Notifications` after
`alias TeacherAssistant.Scope`, then replace `request_correction/2` and `decide_correction/3`:

```elixir
  @doc "Asks to change a locked mark (the course's teacher only); notifies the deciders."
  def request_correction(%Scope{} = scope, attrs) do
    with {:ok, correction} <-
           MarkCorrection
           |> Ash.Changeset.for_create(:request, attrs, scope: scope)
           |> Ash.create(load: @correction_loads) do
      Notifications.deliver(
        scope,
        :correction_requested,
        others(scope, Notifications.admin_ids(scope)),
        Map.put(correction_params(correction), :teacher, user_name(correction.requester)),
        "/school/corrections/review"
      )

      {:ok, correction}
    end
  end
```

```elixir
  defp decide_correction(scope, correction, action) do
    with {:ok, decided} <-
           correction
           |> Ash.Changeset.for_update(action, %{}, scope: scope)
           |> Ash.update(load: @correction_loads) do
      Notifications.deliver(
        scope,
        :correction_decided,
        others(scope, [decided.requester_user_id]),
        Map.put(correction_params(decided), :decision, decided.status),
        "/school/corrections"
      )

      {:ok, decided}
    end
  end

  # Spec KLM8: the short strings a correction notice shows.
  defp correction_params(%MarkCorrection{student: student, assessment: assessment}) do
    tc = assessment.teaching_context

    %{
      student: student.full_name,
      subject: tc.subject,
      class: tc.class_group && tc.class_group.label,
      assessment: assessment.label
    }
  end

  # Nobody is notified of their own action; a requester gone from the school (nil) is skipped.
  defp others(%Scope{current_user: %{id: actor_id}}, ids),
    do: Enum.reject(ids, &(is_nil(&1) or &1 == actor_id))

  defp user_name(nil), do: ""
  defp user_name(user), do: to_string(user.name || user.email)
```

- [ ] **Step 4: Run the tests**

```bash
MIX_TEST_PARTITION=8 mix test test/teacher_assistant/academics/mark_correction_notifications_test.exs \
  test/teacher_assistant/academics/mark_correction_test.exs \
  test/teacher_assistant_web/live/school/correction_review_live_test.exs \
  test/teacher_assistant_web/live/school/corrections_live_test.exs
```

Expected: PASS, nothing else changed.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/assessment.ex \
  test/teacher_assistant/academics/mark_correction_notifications_test.exs
git commit -m "feat: correction requests notify the Proviseur and Censeur; decisions notify the teacher"
```

---

### Task 3: `EntryReminder` log and the reminder functions

**Files:**
- Create: `lib/teacher_assistant/academics/entry_reminder.ex`
- Modify: `lib/teacher_assistant/assessment.ex` (register the resource; `remind_entry/3`, `remind_late/3`,
  `reminder_dates/2`; alias `EntryReminder`)
- Test: `test/teacher_assistant/academics/entry_reminder_test.exs`

**Interfaces:**
- Consumes: `Notifications.deliver/5`, `Notifications.bell/1` (Task 1); `sequence_entry_grid/3`
  (existing; cells are `%{pct: integer | nil, teaching_context: %TeachingContext{}}` or nil).
- Produces:
  - `Assessment.remind_entry(%Scope{}, %Sequence{}, teaching_context_id) :: {:ok, %EntryReminder{}} | {:error, :already_reminded} | {:error, term}`
  - `Assessment.remind_late(%Scope{}, %AcademicYear{}, %Sequence{}) :: {:ok, sent :: non_neg_integer}` —
    every course of the séquence with nothing entered (`pct == 0`)
  - `Assessment.reminder_dates(%Scope{}, %Sequence{}) :: %{teaching_context_id => %Date{}}` (latest)
  - `:entry_reminder` params: `subject`, `class`, `sequence` (the séquence number); link `/school/courses`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.EntryReminderTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Notifications, Organization}
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Academics.Reference

  setup do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    [seq | _] = Organization.list_sequences(head, year)
    {:ok, cg} = Enrollment.create_class_group(head, year, %{label: "3e Z", level: "3ème"})
    {:ok, s1} = Enrollment.add_student(head, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(head, cg, %{full_name: "Bob", sex: :m})

    maths = TeacherFixtures.member_scope_fixture(head)
    english = TeacherFixtures.member_scope_fixture(head)
    censeur = TeacherFixtures.member_scope_fixture(head, %{roles: [:vice_principal]})

    {:ok, tc_maths} = Curriculum.assign_teacher(head, cg, maths.current_user, %{subject: "Maths"})

    {:ok, tc_en} =
      Curriculum.assign_teacher(head, cg, english.current_user, %{subject: "Anglais"})

    # Maths 50 %, Anglais 0 % (nothing entered).
    {:ok, a} = Assessment.create_assessment(head, tc_maths, seq, %{label: "Interro 1"})
    :ok = Assessment.upsert_marks(head, a, [%{student_id: s1.id, score: Decimal.new(10)}])

    %{
      head: head,
      year: year,
      seq: seq,
      maths: maths,
      english: english,
      censeur: censeur,
      tc_maths: tc_maths,
      tc_en: tc_en
    }
  end

  test "« Relancer » notifies the course's teacher and logs the day", ctx do
    assert {:ok, r} = Assessment.remind_entry(ctx.head, ctx.seq, ctx.tc_en.id)
    assert r.sent_on == Reference.today()
    assert r.sent_by_user_id == ctx.head.current_user.id

    assert %{unread: 1, latest: [n]} = Notifications.bell(ctx.english)
    assert n.kind == :entry_reminder
    assert n.link == "/school/courses"

    assert n.params == %{
             "subject" => "Anglais",
             "class" => "3e Z",
             "sequence" => to_string(ctx.seq.number)
           }

    assert Assessment.reminder_dates(ctx.head, ctx.seq) == %{ctx.tc_en.id => Reference.today()}
  end

  test "a second reminder the same day is refused quietly, whoever sends it", ctx do
    {:ok, _} = Assessment.remind_entry(ctx.head, ctx.seq, ctx.tc_en.id)
    assert {:error, :already_reminded} = Assessment.remind_entry(ctx.censeur, ctx.seq, ctx.tc_en.id)
    assert {:error, :already_reminded} = Assessment.remind_entry(ctx.head, ctx.seq, ctx.tc_en.id)
    assert %{unread: 1} = Notifications.bell(ctx.english)
  end

  test "a teacher cannot remind", ctx do
    assert {:error, %Ash.Error.Forbidden{}} =
             Assessment.remind_entry(ctx.maths, ctx.seq, ctx.tc_en.id)

    assert %{unread: 0} = Notifications.bell(ctx.english)
  end

  test "« Relancer tous les retards » reminds every course with nothing entered, once", ctx do
    assert {:ok, 1} = Assessment.remind_late(ctx.head, ctx.year, ctx.seq)
    assert %{unread: 1} = Notifications.bell(ctx.english)
    # Maths has marks: not late.
    assert %{unread: 0} = Notifications.bell(ctx.maths)

    assert {:ok, 0} = Assessment.remind_late(ctx.censeur, ctx.year, ctx.seq)
    assert %{unread: 1} = Notifications.bell(ctx.english)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_TEST_PARTITION=8 mix test test/teacher_assistant/academics/entry_reminder_test.exs`
Expected: FAIL — `Assessment.remind_entry/3` undefined.

- [ ] **Step 3: Write the resource**

`lib/teacher_assistant/academics/entry_reminder.ex`:

```elixir
defmodule TeacherAssistant.Academics.EntryReminder do
  @moduledoc """
  Spec KLM8 (N06): a « Relancer » sent to a course's teacher for one séquence. At most
  one per course, séquence and school day (`sent_on`, the school-local date).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.Reference

  postgres do
    table "entry_reminders"
    repo TeacherAssistant.Repo

    references do
      reference :teaching_context,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :sequence,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :sent_by, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:teaching_context_id, :sequence_id]
      change set_attribute(:sent_by_user_id, actor(:id))
      change set_attribute(:sent_on, &Reference.today/0)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    policy action(:create) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :sent_on, :date, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? false
      public? true
    end

    belongs_to :sent_by, TeacherAssistant.Accounts.User do
      source_attribute :sent_by_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :once_a_day, [:teaching_context_id, :sequence_id, :sent_on]
  end
end
```

- [ ] **Step 4: Register it and add the functions**

In `lib/teacher_assistant/assessment.ex`: add `EntryReminder,` to the `TeacherAssistant.Academics.{…}`
alias list (alphabetical, after `CouncilDecision,`), and `resource EntryReminder` at the end of
`resources do`. Then, after `default_sequence/2`:

```elixir
  # --- Entry reminders (spec KLM8, N06) ------------------------------------------

  @doc """
  « Relancer »: logs a reminder for the course and séquence and notifies the course's
  teacher. Once per course, séquence and school day: a second one is
  `{:error, :already_reminded}` and notifies nobody.
  """
  def remind_entry(%Scope{} = scope, %Sequence{} = seq, teaching_context_id) do
    with {:ok, tc} <-
           Ash.get(TeachingContext, teaching_context_id,
             scope: scope,
             load: [:class_group, :catalog_subject]
           ),
         {:ok, reminder} <- create_reminder(scope, seq, tc) do
      Notifications.deliver(
        scope,
        :entry_reminder,
        others(scope, [tc.teacher_user_id]),
        %{
          subject: (tc.catalog_subject && tc.catalog_subject.name) || tc.subject,
          class: tc.class_group && tc.class_group.label,
          sequence: seq.number
        },
        "/school/courses"
      )

      {:ok, reminder}
    end
  end

  @doc "« Relancer tous les retards »: reminds every course with nothing entered; the count sent."
  def remind_late(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq) do
    tc_ids =
      for row <- sequence_entry_grid(scope, year, seq).rows,
          %{pct: 0, teaching_context: tc} <- Map.values(row.cells),
          do: tc.id

    {:ok, Enum.count(tc_ids, &match?({:ok, _}, remind_entry(scope, seq, &1)))}
  end

  @doc "The latest reminder day of each course reminded for the séquence."
  def reminder_dates(%Scope{} = scope, %Sequence{id: seq_id}) do
    EntryReminder
    |> Ash.Query.filter(sequence_id == ^seq_id)
    |> Ash.read!(scope: scope)
    |> Enum.group_by(& &1.teaching_context_id, & &1.sent_on)
    |> Map.new(fn {tc_id, days} -> {tc_id, Enum.max(days, Date)} end)
  end

  defp create_reminder(scope, seq, tc) do
    EntryReminder
    |> Ash.Changeset.for_create(
      :create,
      %{teaching_context_id: tc.id, sequence_id: seq.id},
      scope: scope
    )
    |> Ash.create()
    |> case do
      {:error, error} ->
        if reminded_today?(error), do: {:error, :already_reminded}, else: {:error, error}

      ok ->
        ok
    end
  end

  defp reminded_today?(%Ash.Error.Invalid{errors: errors}), do: Enum.any?(errors, &reminded_today?/1)

  defp reminded_today?(%Ash.Error.Changes.InvalidAttribute{private_vars: vars}) do
    constraint = vars[:constraint]
    is_binary(constraint) and String.contains?(constraint, "once_a_day")
  end

  defp reminded_today?(_error), do: false
```

(`others/2` is the private helper added in Task 2.)

- [ ] **Step 5: Dev migration and tests**

```bash
mix ash.codegen --dev
MIX_TEST_PARTITION=8 mix test test/teacher_assistant/academics/entry_reminder_test.exs \
  test/teacher_assistant/composite_fk_test.exs
```

Expected: PASS. If the duplicate is not recognised as `:already_reminded`, print `error` once and match the
constraint name actually reported (it contains the identity name `once_a_day`).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/entry_reminder.ex lib/teacher_assistant/assessment.ex \
  test/teacher_assistant/academics/entry_reminder_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: entry reminders — one per course, séquence and day, notifying the teacher"
```

---

### Task 4: Notification text, the bell hook and the bell in the shell

**Files:**
- Create: `lib/teacher_assistant_web/notification_text.ex`
- Create: `lib/teacher_assistant_web/notification_hooks.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (hook in the `:teaching` and `:school_workspace` live sessions;
  route `/school/notifications` is added in Task 5)
- Modify: `lib/teacher_assistant_web/components/layouts.ex` (bell in the rail and in the mobile header)
- Test: `test/teacher_assistant_web/notification_bell_test.exs`

**Interfaces:**
- Consumes: `Notifications.subscribe/1`, `bell/1`, `open/2`, `mark_all_read/1` (Task 1).
- Produces:
  - `TeacherAssistantWeb.NotificationText.text(%Notification{}) :: String.t()`
  - `NotificationText.when_text(%Notification{}) :: String.t()` (« Aujourd'hui · 14:05 »)
  - `current_scope.capabilities.notifications :: %{unread, latest}` on every school LiveView
  - LiveView events handled by the hook on every school page: `"notification:open"` (`%{"id" => id}`),
    `"notification:read_all"`
  - DOM ids: `#notification-bell`, `#notification-bell-count`, `#bell-item-<id>`, `#bell-read-all`,
    `#bell-see-all`, `#notification-bell-mobile`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.NotificationBellTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Notifications

  setup :register_and_log_in_user

  defp remind(scope, user, subject \\ "Maths") do
    Notifications.deliver(
      scope,
      :entry_reminder,
      [user.id],
      %{subject: subject, class: "3e A", sequence: 2},
      "/school/settings"
    )
  end

  test "the bell counts unread notices and updates live", %{conn: conn, scope: scope, actor: head} do
    {:ok, view, _} = live(conn, ~p"/school")
    assert has_element?(view, "#notification-bell")
    refute has_element?(view, "#notification-bell-count")

    remind(scope, head)

    assert has_element?(view, "#notification-bell-count", "1")
    assert has_element?(view, "#notification-bell-mobile .badge", "1")

    assert has_element?(
             view,
             "#notification-bell li",
             "Saisie en retard : Maths · 3e A · Séquence 2"
           )

    assert has_element?(view, ~s|#bell-see-all[href="/school/notifications"]|)
  end

  test "opening a notice from the bell marks it read and follows its link",
       %{conn: conn, scope: scope, actor: head} do
    remind(scope, head)
    [n] = Notifications.bell(scope).latest
    {:ok, view, _} = live(conn, ~p"/school")

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             view |> element("#bell-item-#{n.id}") |> render_click()

    assert %{unread: 0} = Notifications.bell(scope)
  end

  test "« Tout marquer comme lu » clears the count", %{conn: conn, scope: scope, actor: head} do
    remind(scope, head, "Maths")
    remind(scope, head, "SVT")
    {:ok, view, _} = live(conn, ~p"/school")
    assert has_element?(view, "#notification-bell-count", "2")

    view |> element("#bell-read-all") |> render_click()
    refute has_element?(view, "#notification-bell-count")
    assert %{unread: 0} = Notifications.bell(scope)
  end

  test "a forged open event for someone else's notice changes nothing",
       %{conn: conn, scope: scope} do
    other = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope)
    remind(scope, other.current_user)
    [n] = Notifications.bell(other).latest
    {:ok, view, _} = live(conn, ~p"/school")

    render_hook(view, "notification:open", %{"id" => n.id})
    assert %{unread: 1} = Notifications.bell(other)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/notification_bell_test.exs`
Expected: FAIL — `#notification-bell` not found.

- [ ] **Step 3: The text module**

`lib/teacher_assistant_web/notification_text.ex`:

```elixir
defmodule TeacherAssistantWeb.NotificationText do
  @moduledoc """
  Spec KLM8: a notification's words, built at display time from its `kind` and
  `params`, so they follow the reader's language.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Dates

  def text(%{kind: :correction_requested, params: p}) do
    gettext("%{teacher} demande une correction : %{student} · %{subject} · %{class}",
      teacher: get(p, "teacher"),
      student: get(p, "student"),
      subject: get(p, "subject"),
      class: get(p, "class")
    )
  end

  def text(%{kind: :correction_decided, params: %{"decision" => "approved"} = p}) do
    gettext("Correction approuvée : %{student} · %{assessment} · %{class}",
      student: get(p, "student"),
      assessment: get(p, "assessment"),
      class: get(p, "class")
    )
  end

  def text(%{kind: :correction_decided, params: p}) do
    gettext("Correction refusée : %{student} · %{assessment} · %{class}",
      student: get(p, "student"),
      assessment: get(p, "assessment"),
      class: get(p, "class")
    )
  end

  def text(%{kind: :entry_reminder, params: p}) do
    gettext("Saisie en retard : %{subject} · %{class} · %{sequence}",
      subject: get(p, "subject"),
      class: get(p, "class"),
      sequence: gettext("Séquence %{n}", n: get(p, "sequence"))
    )
  end

  @doc "« Aujourd'hui · 14:05 », « hier · 09:12 », else « ven. 2 oct. · 16:40 » (school time)."
  def when_text(%{inserted_at: %DateTime{} = at}) do
    local = Reference.now(at)

    "#{Dates.relative(NaiveDateTime.to_date(local), Reference.today())} · " <>
      Calendar.strftime(local, "%H:%M")
  end

  defp get(params, key) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> "—"
      value -> value
    end
  end
end
```

- [ ] **Step 4: The hook**

`lib/teacher_assistant_web/notification_hooks.ex`:

```elixir
defmodule TeacherAssistantWeb.NotificationHooks do
  @moduledoc """
  Spec KLM8: the header bell on every school LiveView. On mount it puts the bell
  (`Notifications.bell/1`) into `current_scope.capabilities.notifications` for the
  layout and subscribes to the member's topic; it refreshes the bell on
  `:notifications_changed` and handles the bell's own events, so pages need no code
  for it. Navigation data only — reading and marking stay under the resource policies.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_navigate: 2]

  alias TeacherAssistant.Notifications

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns.current_scope do
      %{current_workspace: %{}, current_user: %{id: user_id}} ->
        if connected?(socket), do: Notifications.subscribe(user_id)

        {:cont,
         socket
         |> put_bell()
         |> attach_hook(:notification_info, :handle_info, &handle_info/2)
         |> attach_hook(:notification_events, :handle_event, &handle_event/3)}

      _ ->
        {:cont, socket}
    end
  end

  defp handle_info(:notifications_changed, socket), do: {:halt, put_bell(socket)}
  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("notification:open", %{"id" => id}, socket) do
    case Notifications.open(socket.assigns.current_scope, id) do
      {:ok, link} -> {:halt, push_navigate(socket, to: link)}
      :error -> {:halt, socket}
    end
  end

  defp handle_event("notification:read_all", _params, socket) do
    :ok = Notifications.mark_all_read(socket.assigns.current_scope)
    {:halt, put_bell(socket)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp put_bell(socket) do
    scope = socket.assigns.current_scope
    bell = Notifications.bell(scope)
    scope = %{scope | capabilities: Map.put(scope.capabilities || %{}, :notifications, bell)}

    socket |> assign(:current_scope, scope) |> assign(:scope, scope)
  end
end
```

- [ ] **Step 5: Mount it**

In `lib/teacher_assistant_web/router.ex`, in both `ash_authentication_live_session :teaching` and
`:school_workspace`, add right after `{TeacherAssistantWeb.LiveUserAuth, :assign_space},`:

```elixir
        {TeacherAssistantWeb.NotificationHooks, :default},
```

- [ ] **Step 6: The bell in the layout**

In `lib/teacher_assistant_web/components/layouts.ex`:

1. Add `alias TeacherAssistantWeb.NotificationText` under `alias TeacherAssistant.Organization`.
2. In `app/1`, add to the assigns pipeline (after `:current_context`):

```elixir
      |> assign(
        :bell,
        current_scope && (current_scope.capabilities || %{})[:notifications]
      )
```

3. Mobile header: after the workspace-name `<span>` inside the `lg:hidden` header, add:

```heex
            <.link
              :if={@bell}
              id="notification-bell-mobile"
              navigate={~p"/school/notifications"}
              aria-label={gettext("Notifications")}
              class="btn btn-ghost btn-sm btn-square relative ml-auto"
            >
              <.icon name="hero-bell" class="size-5" />
              <span
                :if={@bell.unread > 0}
                class="badge badge-error badge-xs ta-num absolute -right-1 -top-1"
              >
                {@bell.unread}
              </span>
            </.link>
```

4. Rail: wrap the existing `<div id="workspace-switcher" class="dropdown w-full">…</div>` in a row and put
   the bell beside it — change its class to `dropdown min-w-0 flex-1` and surround it:

```heex
            <div class="flex items-start gap-1">
              <div id="workspace-switcher" class="dropdown min-w-0 flex-1">
                … unchanged …
              </div>
              <.notification_bell :if={@bell} bell={@bell} />
            </div>
```

5. Add the component next to `rail_link`:

```elixir
  attr :bell, :map, required: true

  defp notification_bell(assigns) do
    ~H"""
    <div id="notification-bell" class="dropdown dropdown-bottom">
      <div
        tabindex="0"
        role="button"
        aria-label={gettext("Notifications")}
        class="relative grid size-9 place-items-center rounded-lg text-[color:var(--ta-rail-muted)] transition-colors hover:bg-[color:var(--ta-rail-hover)] hover:text-[color:var(--ta-rail-fg)]"
      >
        <.icon name="hero-bell" class="size-5" />
        <span
          :if={@bell.unread > 0}
          id="notification-bell-count"
          class="badge badge-error badge-xs ta-num absolute -right-0.5 -top-0.5"
        >
          {@bell.unread}
        </span>
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-50 mt-1 w-80 rounded-box border border-base-300 bg-base-100 p-2 text-base-content shadow-lg"
      >
        <div class="flex items-center justify-between gap-2 px-2 pb-2">
          <span class="ta-eyebrow">{gettext("Notifications")}</span>
          <button
            :if={@bell.unread > 0}
            id="bell-read-all"
            type="button"
            phx-click="notification:read_all"
            class="text-xs font-semibold text-primary hover:underline"
          >
            {gettext("Tout marquer comme lu")}
          </button>
        </div>
        <p :if={@bell.latest == []} class="px-2 py-3 text-sm text-base-content/60">
          {gettext("Aucune notification.")}
        </p>
        <ul class="flex flex-col gap-0.5">
          <li :for={n <- @bell.latest}>
            <button
              type="button"
              id={"bell-item-#{n.id}"}
              phx-click="notification:open"
              phx-value-id={n.id}
              class={[
                "flex w-full items-start gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition-colors hover:bg-base-200",
                is_nil(n.read_at) && "font-semibold"
              ]}
            >
              <span class={[
                "mt-1.5 size-2 shrink-0 rounded-full",
                if(is_nil(n.read_at), do: "bg-primary", else: "bg-transparent")
              ]}>
              </span>
              <span class="min-w-0 flex-1">
                <span class="block">{NotificationText.text(n)}</span>
                <span class="ta-num block text-[0.7rem] font-normal text-base-content/50">
                  {NotificationText.when_text(n)}
                </span>
              </span>
            </button>
          </li>
        </ul>
        <.link
          id="bell-see-all"
          navigate={~p"/school/notifications"}
          class="mt-1 block rounded-lg px-2 py-1.5 text-center text-xs font-semibold text-primary transition-colors hover:bg-base-200"
        >
          {gettext("Tout voir")}
        </.link>
      </div>
    </div>
    """
  end
```

(`~p"/school/notifications"` will warn until Task 5 adds the route; the tests here still pass.)

- [ ] **Step 7: Run the tests**

```bash
MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/notification_bell_test.exs \
  test/teacher_assistant_web/live/school/dashboard_live_test.exs \
  test/teacher_assistant_web/live/school/correction_review_live_test.exs
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant_web/notification_text.ex lib/teacher_assistant_web/notification_hooks.ex \
  lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/components/layouts.ex \
  test/teacher_assistant_web/notification_bell_test.exs
git commit -m "feat: live notification bell in the app shell"
```

---

### Task 5: The « Notifications » page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/notifications_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route in `:school_workspace`)
- Test: `test/teacher_assistant_web/live/school/notifications_live_test.exs`

**Interfaces:**
- Consumes: `Notifications.inbox/2`, `page_size/0`, `open/2`, `mark_all_read/1` (Task 1);
  `NotificationText.text/1`, `when_text/1` (Task 4).
- Produces: route `/school/notifications` (all members, `?page=n`); DOM ids `#notifications`,
  `#notification-<id>` (with `data-unread` when unread), `#read-all`, `#notifications-empty`,
  `#notifications-pager`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.School.NotificationsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Notifications, TeacherFixtures}

  setup :register_and_log_in_user

  defp remind(scope, user, subject) do
    Notifications.deliver(
      scope,
      :entry_reminder,
      [user.id],
      %{subject: subject, class: "3e A", sequence: 1},
      "/school/settings"
    )
  end

  test "newest first, unread marked; opening one follows its link",
       %{conn: conn, scope: scope, actor: head} do
    remind(scope, head, "Maths")
    remind(scope, head, "SVT")
    [svt, maths] = Notifications.inbox(scope, 1).results
    {:ok, _} = Notifications.open(scope, maths.id)

    {:ok, view, html} = live(conn, ~p"/school/notifications")
    assert html =~ "Notifications"
    assert has_element?(view, "#notification-#{svt.id}[data-unread]", "SVT")
    assert has_element?(view, "#notification-#{maths.id}", "Maths")
    refute has_element?(view, "#notification-#{maths.id}[data-unread]")
    assert html =~ ~r/SVT.*Maths/s

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             view |> element("#notification-#{svt.id}") |> render_click()

    assert %{unread: 0} = Notifications.bell(scope)
  end

  test "« Tout marquer comme lu » clears every unread mark", %{conn: conn, scope: scope, actor: head} do
    remind(scope, head, "Maths")
    remind(scope, head, "SVT")
    {:ok, view, _} = live(conn, ~p"/school/notifications")

    view |> element("#read-all") |> render_click()
    refute has_element?(view, "[data-unread]")
    refute has_element?(view, "#notification-bell-count")
  end

  test "a teacher sees only their own notices", %{conn: conn, scope: scope, actor: head, workspace: ws} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    remind(scope, head, "Maths")
    remind(scope, teacher.current_user, "Anglais")

    conn =
      conn
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    {:ok, view, _} = live(conn, ~p"/school/notifications")
    assert render(view) =~ "Anglais"
    refute render(view) =~ "Maths"
  end

  test "an empty inbox says so; more than a page shows the pager",
       %{conn: conn, scope: scope, actor: head} do
    {:ok, view, _} = live(conn, ~p"/school/notifications")
    assert has_element?(view, "#notifications-empty")

    for n <- 1..(Notifications.page_size() + 1), do: remind(scope, head, "S#{n}")
    {:ok, view, _} = live(conn, ~p"/school/notifications?page=2")
    assert has_element?(view, "#notifications-pager")
    assert render(view) =~ "S1 ·"
    refute render(view) =~ "S31 ·"
  end
end
```

(`log_in_user/2` is the ConnCase helper the correction-review test already uses.)

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/live/school/notifications_live_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Route**

In `lib/teacher_assistant_web/router.ex`, in `:school_workspace`, after
`live "/school/corrections/review", …`:

```elixir
      live "/school/notifications", School.NotificationsLive, :index
```

- [ ] **Step 4: The page**

`lib/teacher_assistant_web/live/school/notifications_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.NotificationsLive do
  @moduledoc """
  Spec KLM8: every notice of the signed-in member in this school, newest first,
  unread in bold. Opening one marks it read and follows its link. The bell in the
  shell (`NotificationHooks`) shows the 8 newest and links here.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Notifications
  alias TeacherAssistantWeb.NotificationText

  def mount(_params, _session, socket) do
    if socket.assigns.current_scope.current_workspace,
      do: {:ok, assign(socket, page: nil, page_number: 1)},
      else: {:ok, push_navigate(socket, to: ~p"/school")}
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, load(socket, parse_page(params["page"]))}

  def handle_event("open", %{"id" => id}, socket) do
    case Notifications.open(socket.assigns.current_scope, id) do
      {:ok, link} -> {:noreply, push_navigate(socket, to: link)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("read-all", _params, socket) do
    :ok = Notifications.mark_all_read(socket.assigns.current_scope)
    {:noreply, load(socket, socket.assigns.page_number)}
  end

  defp load(socket, n),
    do:
      assign(socket,
        page: Notifications.inbox(socket.assigns.current_scope, n),
        page_number: n
      )

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp pages(count), do: div(count + Notifications.page_size() - 1, Notifications.page_size())

  defp unread?(page), do: Enum.any?(page.results, &is_nil(&1.read_at))

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="notifications" class="mx-auto flex w-full max-w-2xl flex-col gap-4">
        <.page_header eyebrow={gettext("Messagerie")} title={gettext("Notifications")}>
          <:actions :if={unread?(@page)}>
            <button id="read-all" type="button" phx-click="read-all" class="btn btn-ghost btn-sm">
              <.icon name="hero-check" class="size-4" />
              {gettext("Tout marquer comme lu")}
            </button>
          </:actions>
        </.page_header>

        <div class="ta-panel flex flex-col gap-0.5 !p-1.5">
          <p
            :if={@page.results == []}
            id="notifications-empty"
            class="flex items-center gap-2 p-5 text-sm text-base-content/60"
          >
            <.icon name="hero-bell-slash" class="size-5 text-base-content/40" />
            {gettext("Aucune notification pour l'instant.")}
          </p>
          <button
            :for={n <- @page.results}
            id={"notification-#{n.id}"}
            type="button"
            phx-click="open"
            phx-value-id={n.id}
            data-unread={is_nil(n.read_at)}
            class={[
              "flex w-full items-start gap-3 rounded-lg px-3 py-2.5 text-left transition-colors hover:bg-base-200",
              is_nil(n.read_at) && "font-semibold"
            ]}
          >
            <span class={[
              "mt-2 size-2 shrink-0 rounded-full",
              if(is_nil(n.read_at), do: "bg-primary", else: "bg-transparent")
            ]}>
            </span>
            <span class="min-w-0 flex-1">
              <span class="block text-[0.92rem]">{NotificationText.text(n)}</span>
              <span class="ta-num block text-xs font-normal text-base-content/55">
                {NotificationText.when_text(n)}
              </span>
            </span>
            <.icon name="hero-chevron-right" class="mt-1 size-4 shrink-0 text-base-content/30" />
          </button>
        </div>

        <nav
          :if={(@page.count || 0) > Notifications.page_size()}
          id="notifications-pager"
          aria-label={gettext("Pages")}
          class="flex flex-wrap gap-1"
        >
          <.link
            :for={p <- 1..pages(@page.count)}
            patch={~p"/school/notifications?page=#{p}"}
            aria-current={p == @page_number && "page"}
            class={[
              "ta-num rounded-full border px-3 py-1 text-xs font-semibold transition-colors hover:border-primary",
              if(p == @page_number,
                do: "border-primary bg-primary/15 text-primary",
                else: "border-base-300 text-base-content/70"
              )
            ]}
          >
            {p}
          </.link>
        </nav>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 5: Run the tests**

```bash
MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/live/school/notifications_live_test.exs \
  test/teacher_assistant_web/notification_bell_test.exs
mix compile --warnings-as-errors
```

Expected: PASS; no warnings (the Task 4 `~p` warning is gone).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/notifications_live.ex lib/teacher_assistant_web/router.ex \
  test/teacher_assistant_web/live/school/notifications_live_test.exs
git commit -m "feat: « Notifications » page — newest first, open to follow, mark all read"
```

---

### Task 6: « Relancer » on the séquence tracking page

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/sequence_tracking_live.ex`
- Test: `test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs` (append)

**Interfaces:**
- Consumes: `Assessment.remind_entry/3`, `remind_late/3`, `reminder_dates/2` (Task 3);
  `Notifications.bell/1` (Task 1).
- Produces: DOM ids `#remind-course` (detail panel, lagging course not yet reminded today),
  `#reminded-on` (detail panel, when reminded), `#remind-late` (« À relancer » panel), grid cells carry
  `data-reminded` once reminded.

- [ ] **Step 1: Write the failing tests** (append inside the existing module; add
  `alias TeacherAssistant.Notifications` to its aliases)

```elixir
  defp english_scope(ctx), do: TeacherAssistant.DataCase.school_scope(ctx.english, ctx.workspace)

  test "« Relancer » notifies the course's teacher once a day and marks the cell",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
    cell = col(view, ctx.cg, "Anglais")
    view |> element(cell) |> render_click()

    html = view |> element("#remind-course") |> render_click()
    assert html =~ "Relance envoyée"
    assert %{unread: 1, latest: [%{kind: :entry_reminder}]} = Notifications.bell(english_scope(ctx))

    assert has_element?(view, "#{cell}[data-reminded]")
    assert has_element?(view, "#reminded-on")
    refute has_element?(view, "#remind-course")

    # A forged second click the same day is refused quietly.
    render_click(view, "remind", %{"tc" => tc_id_of(view, cell)})
    assert %{unread: 1} = Notifications.bell(english_scope(ctx))
    refute render(view) =~ "n'a pas pu"
  end

  test "« Relancer tous les retards » reminds each course with nothing entered, once",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{ctx.seq.id}")

    html = view |> element("#remind-late") |> render_click()
    # Anglais 3e A and Anglais 4e B.
    assert html =~ "2 relances envoyées"
    assert %{unread: 2} = Notifications.bell(english_scope(ctx))

    html = view |> element("#remind-late") |> render_click()
    assert html =~ "Aucune nouvelle relance"
    assert %{unread: 2} = Notifications.bell(english_scope(ctx))
  end

  defp tc_id_of(view, cell) do
    view
    |> element(cell)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-tc")
    |> hd()
  end
```

`ctx.workspace` comes from `register_and_log_in_user`; `ctx.english` is the English teacher (a user) from the
existing setup.

- [ ] **Step 2: Run tests to verify they fail**

Run: `MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs`
Expected: the three new tests FAIL (`#remind-course` / `#remind-late` not found).

- [ ] **Step 3: Implement**

In `lib/teacher_assistant_web/live/school/sequence_tracking_live.ex`:

1. `mount/3`: add `reminders: %{}` to the `assign(socket, …)` of the `true ->` branch.

2. `handle_params/3`: in the `seq ->` branch, also assign
   `reminders: Assessment.reminder_dates(scope, seq)`; in the `nil ->` branch add `reminders: %{}`.

3. Events (after the `"select"` clause):

```elixir
  def handle_event("remind", %{"tc" => tc_id}, socket) do
    %{grid: grid, seq: seq, current_scope: scope} = socket.assigns

    # Only a lagging course of the grid on screen can be reminded.
    case lagging_cell(grid, tc_id) do
      nil ->
        {:noreply, socket}

      cell ->
        case Assessment.remind_entry(scope, seq, tc_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Relance envoyée à %{name}.", name: teacher_name(cell.teacher)))
             |> assign(:reminders, Assessment.reminder_dates(scope, seq))}

          {:error, :already_reminded} ->
            {:noreply, assign(socket, :reminders, Assessment.reminder_dates(scope, seq))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("La relance n'a pas pu être envoyée."))}
        end
    end
  end

  def handle_event("remind-late", _params, socket) do
    %{year: year, seq: seq, current_scope: scope} = socket.assigns
    {:ok, sent} = Assessment.remind_late(scope, year, seq)

    message =
      if sent == 0,
        do: gettext("Aucune nouvelle relance : chaque retard a déjà été relancé aujourd'hui."),
        else:
          ngettext("%{count} relance envoyée.", "%{count} relances envoyées.", sent)

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> assign(:reminders, Assessment.reminder_dates(scope, seq))}
  end

  defp lagging_cell(grid, tc_id) do
    grid.rows
    |> Enum.flat_map(&Map.values(&1.cells))
    |> Enum.find(fn
      %{pct: pct, teaching_context: %{id: ^tc_id}} when is_integer(pct) and pct < 100 -> true
      _ -> false
    end)
  end
```

4. Grid cells: pass `reminded={@reminders[row.cells[subject.key] && row.cells[subject.key].teaching_context.id]}`
   to `<.grid_cell …>`; in the third `grid_cell/1` clause (the `<button>`), add `attr :reminded, :any,
   default: nil` to the attr list above the clauses, then on the button:

```heex
      data-tc={@cell.teaching_context.id}
      data-reminded={@reminded != nil}
      title={
        @title <> " · " <> teacher_name(@cell.teacher) <>
          if(@reminded, do: " · " <> gettext("relancé le %{date}", date: Dates.short(@reminded)), else: "")
      }
```

   and inside the button, after `{@cell.pct}%`:

```heex
      <.icon :if={@reminded} name="hero-bell-alert" class="ml-0.5 size-3 align-[-1px] text-base-content/70" />
```

5. Detail panel (`#cell-detail`), after the « Dernière saisie » line:

```heex
                <.detail_line
                  :if={@reminders[@selected.cell.teaching_context.id]}
                  id="reminded-on"
                  label={gettext("Relancé")}
                  value={Dates.short(@reminders[@selected.cell.teaching_context.id])}
                />
                <button
                  :if={
                    @selected.cell.pct < 100 and
                      @reminders[@selected.cell.teaching_context.id] != Reference.today()
                  }
                  id="remind-course"
                  type="button"
                  phx-click="remind"
                  phx-value-tc={@selected.cell.teaching_context.id}
                  phx-disable-with={gettext("Envoi…")}
                  class="btn btn-warning btn-sm mt-1"
                >
                  <.icon name="hero-bell-alert" class="size-4" />
                  {gettext("Relancer")}
                </button>
```

   Give `detail_line/1` an `attr :id, :string, default: nil` and put `id={@id}` on its root `<div>`.

6. « À relancer » panel: replace the closing hint paragraph (« Les relances arrivent avec les
   notifications. ») with:

```heex
                <button
                  :if={@grid.late != []}
                  id="remind-late"
                  type="button"
                  phx-click="remind-late"
                  phx-disable-with={gettext("Envoi…")}
                  class="btn btn-outline btn-warning btn-sm mt-2"
                >
                  <.icon name="hero-bell-alert" class="size-4" />
                  {gettext("Relancer tous les retards")}
                </button>
```

- [ ] **Step 4: Run the tests**

```bash
MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs
mix compile --warnings-as-errors
```

Expected: PASS, no warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/sequence_tracking_live.ex \
  test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs
git commit -m "feat: « Relancer » a late course or every late course from the séquence tracking"
```

---

### Task 7: Named migration, translations, English text, status, full checks

**Files:**
- Create: `priv/repo/migrations/*_klm8_notifications.exs` (generated), snapshots
- Modify: `priv/gettext/**`, `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`
- Test: `test/teacher_assistant_web/notification_text_test.exs`

- [ ] **Step 1: Named migration** — as in KLM4–7, the named run replaces the `--dev` migrations of
  Tasks 1 and 3:

```bash
mix ash.codegen klm8_notifications
MIX_TEST_PARTITION=8 MIX_ENV=test mix ecto.drop && MIX_TEST_PARTITION=8 MIX_ENV=test mix ecto.create
MIX_TEST_PARTITION=8 MIX_ENV=test mix ash.migrate
mix ash.codegen --check
```

Expected: one migration creating `notifications` and `entry_reminders` (with the
`(workspace_id, recipient_user_id, inserted_at)` index and the `once_a_day` unique index); nothing else;
`--check` clean.

- [ ] **Step 2: Translations** — `mix gettext.extract --merge`; fill every new `en` msgstr (e.g.
  « Saisie en retard : %{subject} · %{class} · %{sequence} » → "Late mark entry: %{subject} · %{class} ·
  %{sequence}", « Séquence %{n} » → "Sequence %{n}", « %{teacher} demande une correction : … » → "%{teacher}
  asks for a correction: …", « Correction approuvée : … » → "Correction approved: …", « Correction refusée :
  … » → "Correction refused: …", « Tout marquer comme lu » → "Mark all as read", « Tout voir » → "See all",
  « Relancer » → "Send a reminder", « Relancer tous les retards » → "Remind everyone late"); clear new fuzzy
  flags in both locales; `grep -c "#, fuzzy" priv/gettext/*/LC_MESSAGES/default.po` prints 0 for both.

- [ ] **Step 3: English text test**

```elixir
defmodule TeacherAssistantWeb.NotificationTextTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.Notification
  alias TeacherAssistantWeb.NotificationText

  defp n(kind, params), do: %Notification{kind: kind, params: params}

  test "the text follows the reader's language" do
    reminder = n(:entry_reminder, %{"subject" => "Maths", "class" => "3e A", "sequence" => "2"})
    assert NotificationText.text(reminder) == "Saisie en retard : Maths · 3e A · Séquence 2"

    Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
      assert NotificationText.text(reminder) == "Late mark entry: Maths · 3e A · Sequence 2"

      assert NotificationText.text(
               n(:correction_decided, %{
                 "decision" => "refused",
                 "student" => "Awa",
                 "assessment" => "Devoir 1",
                 "class" => "3e A"
               })
             ) == "Correction refused: Awa · Devoir 1 · 3e A"
    end)
  end

  test "a missing value shows a dash" do
    assert NotificationText.text(n(:entry_reminder, %{"sequence" => "1"})) ==
             "Saisie en retard : — · — · Séquence 1"
  end
end
```

Run: `MIX_TEST_PARTITION=8 mix test test/teacher_assistant_web/notification_text_test.exs` — PASS (adjust
the expected English to the msgstr you wrote in Step 2, keeping them identical).

- [ ] **Step 4: Roadmap status** — under `## KLM8 — Staff in-app notifications (spec)` add
  `Status: implemented 2026-10-06 (branch \`klm8-notifications\`, plan
  \`docs/superpowers/plans/2026-10-06-klm8-staff-notifications.md\`); no visual check done.`

- [ ] **Step 5: Full checks** — `mix compile --warnings-as-errors` then `MIX_TEST_PARTITION=8 mix precommit`;
  both exit 0; stage what `format` rewrote.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations priv/resource_snapshots priv/gettext \
  docs/superpowers/specs/2026-09-27-mockups-roadmap.md \
  test/teacher_assistant_web/notification_text_test.exs
git add -u lib test
git commit -m "chore: KLM8 migration, translations and status"
```
