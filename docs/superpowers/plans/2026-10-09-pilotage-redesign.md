# Pilotage Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the eight Pilotage screens (Proviseur dashboard, séquence tracking, bulletins list, single bulletin, councils list, council, correction review, notifications) to the « Pilotage » mockup, with council scheduling, four new notification kinds and a configurable report card.

**Architecture:** Every screen keeps its LiveView, route and rights. New data: `ClassCouncil.starts_at`, four `NotificationKind` values, seven `BulletinElement` values. Shared reads move to the module that owns their data (`SchoolLife`, `EntryProgress`, `Councils`, `ReportCards`). Two Oban cron workers (the app's first) send the scheduled notices. The on-screen bulletin embeds the existing print document.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Ash 3 + AshPostgres, Oban 2.22 (Cron plugin), daisyUI/Tailwind v4, Gettext (FR source, EN translations).

**Spec:** `docs/superpowers/specs/2026-10-09-pilotage-redesign-design.md`

## Global Constraints

- Work in a worktree: move `.claude/worktrees/enseignant` to `.claude/worktrees/pilotage` (`git worktree move`), then `git switch -c feat/pilotage-redesign main` inside it. Run tests with `MIX_TEST_PARTITION=7`. Never `git commit -a`; stage explicit paths (the user runs parallel sessions).
- Migrations only via `mix ash.codegen --dev <name>`; the final named migration is produced in the last task (`mix ash.codegen pilotage_redesign`).
- Never bare `:atom` attributes — use `Ash.Type.Enum`.
- Routes, live_session membership, rights and menu entries unchanged for all eight screens. Dashboard Proviseur-only; Censeur home stays `/school/sequences`.
- Desktop and 390 px (no horizontal page scroll); FR source strings in `gettext`, EN translated in `priv/gettext/en/LC_MESSAGES/default.po`, no new fuzzy entries in EN or FR (a guard test exists; new FR entries get an empty msgstr).
- Numbers with a decimal comma (`String.replace(".", ",")`).
- daisyUI tokens: green = `primary`, amber = `warning`, red = `error`, blue « Planifié » = `info`, muted = `base-content/70`; existing `ta-leaf` (cards with the margin rule — never override its padding; use `ta-panel` for plain/padded containers), `ta-eyebrow`, `ta-num`, `<.page_header>`.
- No SMS anywhere (in-app notifications only). Out of scope: global search, « Synchronisé », correction explanation text, fees KPI, séquence publishing, multiple distinctions.
- `mix precommit` at the end (it does not fail on warnings in tests — check `mix compile` output for warnings in `lib/` yourself).

## Review Focus

1. A council created early by a decision save (term default date, no time) must show « À planifier », not « Planifié » — test in Task 1.
2. The missed-roll-call digest must not send on a holiday / day off, nor twice for the same half-day if the job is retried — test in Task 4.
3. The expired-password job must never report an account whose temporary password was used (`must_change_password` false) — test in Task 4.
4. A school that saved its bulletin elements before this cycle must not suddenly print the new elements — test in Task 11.
5. A bulletin published before this cycle (snapshot without `teachers`) must still print — test in Task 11.

---

### Task 1: Council scheduling and derived status (domain)

**Files:**
- Modify: `lib/teacher_assistant/academics/class_council.ex` (attribute `starts_at`, `:schedule` action, `:edit` accepts `starts_at`)
- Modify: `lib/teacher_assistant/councils.ex` (`schedule/5`, `status/2`, `save_header/4` accepts `starts_at`)
- Test: `test/teacher_assistant/councils_test.exs`

**Interfaces:**
- Produces: `Councils.schedule(scope, cg, period, %Date{}, %Time{}) :: {:ok, %ClassCouncil{}} | {:error, :locked | term}`; `Councils.status(council_or_nil, published?) :: :to_plan | :planned | :held | :closed`; `ClassCouncil.starts_at :: Time.t() | nil`.

- [ ] **Step 1: Failing tests** (append to `councils_test.exs`, reuse its setup: a class `cg`, a trimester period `period`, head scope `head`, teacher scope)

```elixir
test "schedule sets date and time, creating the council", ctx do
  {:ok, c} = Councils.schedule(ctx.head, ctx.cg, ctx.period, ~D[2025-10-14], ~T[14:00:00])
  assert c.held_on == ~D[2025-10-14] and c.starts_at == ~T[14:00:00]
  assert Councils.status(c, false) == :planned
end

test "a council created by a decision save is still to plan", ctx do
  [s | _] = ctx.students
  {:ok, _} = Councils.set_decision(ctx.head, ctx.cg, ctx.period, s.id, %{"distinction_choice" => ""})
  stored = Councils.council(ctx.head, ctx.cg, ctx.period)
  assert stored.held_on != nil and stored.starts_at == nil
  assert Councils.status(stored, false) == :to_plan
end

test "status: no council, held, held + published" do
  assert Councils.status(nil, false) == :to_plan
  held = %TeacherAssistant.Academics.ClassCouncil{status: :held, starts_at: ~T[14:00:00]}
  assert Councils.status(held, false) == :held
  assert Councils.status(held, true) == :closed
end

test "a teacher cannot schedule", ctx do
  assert {:error, _} = Councils.schedule(ctx.teacher, ctx.cg, ctx.period, ~D[2025-10-14], ~T[14:00:00])
end
```
(If the setup has no `students`/`teacher`, add them with `Enrollment.add_student/3` and `TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})`.)

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=7 mix test test/teacher_assistant/councils_test.exs` — FAIL (`schedule/5` undefined).

- [ ] **Step 3: Implement**
  - `class_council.ex`: `attribute :starts_at, :time, public?: true`; `:open` and `:edit` accept `:starts_at`; new `update :schedule do accept [:held_on, :starts_at] end` (policy `action_type([:create, :update])` already covers it).
  - `councils.ex`:
    ```elixir
    @doc "Plans the council on `date` at `time` (creating it if needed)."
    def schedule(%Scope{} = scope, %ClassGroup{} = cg, period, %Date{} = date, %Time{} = time) do
      with :ok <- unlocked(scope, cg, period),
           {:ok, council} <- ensure(scope, cg, period) do
        council
        |> Ash.Changeset.for_update(:schedule, %{held_on: date, starts_at: time}, scope: scope)
        |> Ash.update()
      end
    end

    @doc """
    The council's state for the lists (spec 2026-10-09 §1.1): to plan until a time is
    set, planned while open, held, closed once the period's bulletins are published.
    """
    def status(nil, _published?), do: :to_plan
    def status(%ClassCouncil{status: :held}, true), do: :closed
    def status(%ClassCouncil{status: :held}, false), do: :held
    def status(%ClassCouncil{starts_at: nil}, _published?), do: :to_plan
    def status(%ClassCouncil{}, _published?), do: :planned
    ```
  - `save_header/4`: `Map.take(params, ~w(held_on starts_at chair attendees observations))`.
- [ ] **Step 4:** `mix ash.codegen --dev council_starts_at`; run the file — PASS; run `test/teacher_assistant_web/live/school/councils_live_test.exs` (still green).
- [ ] **Step 5: Commit** `git add lib/teacher_assistant/academics/class_council.ex lib/teacher_assistant/councils.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant/councils_test.exs` — `feat: council scheduling and derived status`.

---

### Task 2: Two-line notification texts, notifications page and bell

**Files:**
- Modify: `lib/teacher_assistant_web/notification_text.ex` (`title/1`, `detail/1` replace `text/1`)
- Modify: `lib/teacher_assistant_web/live/school/notifications_live.ex`, `lib/teacher_assistant_web/components/layouts.ex:~400` (bell)
- Test: `test/teacher_assistant_web/notification_text_test.exs`, `test/teacher_assistant_web/live/school/notifications_live_test.exs`, `test/teacher_assistant_web/notification_bell_test.exs`

**Interfaces:**
- Produces: `NotificationText.title(notification) :: String.t()`, `NotificationText.detail(notification) :: String.t() | nil`, `when_text/1` unchanged. Task 3 and 4 add clauses for their kinds.

- [ ] **Step 1: Failing tests** — rewrite `notification_text_test.exs` cases to the pair, e.g.

```elixir
test "correction requested: who asks, then what" do
  n = %{kind: :correction_requested, params: %{"teacher" => "Awa Nji", "student" => "Nkoulou Brice",
        "class" => "6e A", "subject" => "SVT", "change" => "08 → 13"}}
  assert NotificationText.title(n) == "Awa Nji demande une correction de note"
  assert NotificationText.detail(n) == "Nkoulou Brice · 6e A · SVT · 08 → 13"
end
```
Same for `:correction_decided` (title « Correction acceptée » / « Correction refusée », detail « <élève> · <évaluation> · <classe> »), `:entry_reminder` (title « Saisie en retard », detail « <matière> · <classe> · Séquence N »), `:roll_call_reminder` (title « Appel non fait », detail « <classe> · <heure> · <matière> »). A missing param still renders « — ». In `notifications_live_test.exs`: `assert has_element?(view, "#notification-#{n.id} [data-role='detail']", "…")` and the unread row has `data-unread`.
  The `"change"` param is new for `:correction_requested`: where `Assessment.request_correction/2` delivers its notice, add `change: "#{MarkEntry.format(current_status, current_score)} → #{MarkEntry.format(requested_status, requested_score)}"`. `detail/1` joins the present segments (student, class, subject, then change only when the param exists), so notices stored before this cycle show « Nkoulou Brice · 6e A · SVT » without a dangling « · ». Add a test for that old-notice case.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** `title/1` + `detail/1` per kind (FR source strings via `gettext`), delete `text/1`, update the bell (`layouts.ex`: title line `font-semibold` when unread, detail `text-xs text-base-content/70`, time) and `NotificationsLive` rows: `<li id={"notification-#{n.id}"} data-unread={is_nil(n.read_at) && "true"} class={["flex items-start gap-3 rounded-box px-3 py-2.5", is_nil(n.read_at) && "bg-warning/5"]}>` with an amber dot `size-2 rounded-full bg-warning` when unread (transparent otherwise), a two-line block (`title` bold when unread, `<p data-role="detail">`), time right-aligned (`ta-num text-xs text-base-content/70 whitespace-nowrap`). Header unchanged (« Messagerie », « Notifications », « Tout marquer comme lu »).
- [ ] **Step 4: Run** the three files plus `test/teacher_assistant/academics/mark_correction_notifications_test.exs` — PASS. Commit `feat: two-line notifications`.

---

### Task 3: Event notifications — bulletins publiés, nouveau membre

**Files:**
- Modify: `lib/teacher_assistant/accounts/notification_kind.ex` (add `:bulletins_published, :missed_roll_calls, :temporary_password_expired, :member_joined` — all four now, Task 4 uses the other two)
- Modify: `lib/teacher_assistant/report_cards.ex:93-128` (`publish/3` notifies)
- Modify: `lib/teacher_assistant/accounts.ex:226-240` (`accept_invitation/2` notifies)
- Modify: `lib/teacher_assistant_web/notification_text.ex` (clauses for the four kinds)
- Test: `test/teacher_assistant/report_cards_test.exs`, `test/teacher_assistant/notifications_test.exs`, `test/teacher_assistant_web/notification_text_test.exs`

**Interfaces:**
- Consumes: `Notifications.deliver/5`, `Notifications.admin_ids/1`, `NotificationText.title/1`, `detail/1` (Task 2).
- Produces: params — `bulletins_published`: `%{class, period, by}`, link `/school/bulletins?class=<cg_id>&period=<period_param>`; `member_joined`: `%{name, roles}` (roles = comma-joined `SchoolRole.label/1`), link `/school/members`; `missed_roll_calls`: `%{half: "morning"|"afternoon", count, list}`, link `/school/day`; `temporary_password_expired`: `%{name, expired_on}` (dd/mm/yyyy), link `/school/members`.

- [ ] **Step 1: Failing tests**

```elixir
# report_cards_test.exs — reuse the publish setup (held council, class with form master fm and a course teacher t)
test "publishing notifies the form master and the class's teachers, not the publisher", ctx do
  {:ok, _} = ReportCards.publish(ctx.head, ctx.cg, ctx.period)
  kinds = fn scope -> scope |> Notifications.inbox(1) |> Map.get(:results) |> Enum.map(& &1.kind) end
  assert :bulletins_published in kinds.(ctx.fm)
  assert :bulletins_published in kinds.(ctx.t)
  refute :bulletins_published in kinds.(ctx.head)
end
```
```elixir
# notifications_test.exs
test "accepting an invitation notifies the admins, not the newcomer" do
  %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
  user = TeacherFixtures.user_fixture()
  {:ok, inv} = Accounts.invite_member(head, %{email: to_string(user.email), roles: [:teacher]})
  {:ok, _} = Accounts.accept_invitation(%Scope{current_user: user}, inv.token)
  assert [%{kind: :member_joined}] = Notifications.inbox(head, 1).results
end
```
Plus text tests: `bulletins_published` → title « Bulletins Trimestre 1 publiés », detail « 6e A · par Marie Ekotto »; `member_joined` → « Grace Ayuk a rejoint l'établissement » / « Compte lié · Enseignant »; `missed_roll_calls` → « 2 appels non faits ce matin » (ngettext, « cet après-midi » for afternoon) / the list; `temporary_password_expired` → « Samuel Fotso n'a pas utilisé son mot de passe temporaire » / « Expiré le 07/10/2025 ».
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**
  - `publish/3`: on `{:ok, pub}` call a private `notify_published(scope, cg, period)` then return `{:ok, pub}`. Recipients: `cg.form_master_user_id` + teachers of the class's teaching contexts this year (`Curriculum` read of `TeachingContext` filtered by `class_group_id`, `teacher_user_id` not nil), minus the actor (reuse the `others/2` idea: reject nil and `scope.current_user.id`). Period label: `Organization.period_label(period)` if it exists (grep); else « Trimestre N » / « Année ».
  - `accept_invitation/2`: after `{:ok, _}` build the newcomer's school scope (`TeacherAssistant.Accounts.Workspaces.scope_for(user, inv.workspace_id)`) and `Notifications.deliver(new_scope, :member_joined, Notifications.admin_ids(new_scope) -- [user.id], %{name: User.display_name(user), roles: …}, "/school/members")`. A failure to notify must not fail the acceptance (`_ = deliver(...)`).
  - Text clauses for all four kinds.
- [ ] **Step 4: Run** the three files plus `test/teacher_assistant_web/live/school/bulletins_live_test.exs` — PASS. Commit `feat: notifications for published bulletins and new members`.

---

### Task 4: Scheduled notifications (Oban) and shared roll-call counts

**Files:**
- Modify: `lib/teacher_assistant/application.ex` (start Oban)
- Modify: `config/config.exs` (crontab)
- Modify: `lib/teacher_assistant/academics/school_life.ex` (`roll_call_counts/3`), `lib/teacher_assistant/attendance.ex` (defdelegate)
- Modify: `lib/teacher_assistant_web/live/school/day_live.ex` (use `roll_call_counts/3`)
- Modify: `lib/teacher_assistant/accounts/workspaces.ex` (`job_scopes/0`)
- Create: `lib/teacher_assistant/workers/missed_roll_calls.ex`, `lib/teacher_assistant/workers/expired_temporary_passwords.ex`
- Test: `test/teacher_assistant/academics/school_life_test.exs`, `test/teacher_assistant/workers/missed_roll_calls_test.exs`, `test/teacher_assistant/workers/expired_temporary_passwords_test.exs`

**Interfaces:**
- Consumes: kinds and params from Task 3.
- Produces: `Attendance.roll_call_counts(scope, date, now) :: %{done: non_neg_integer, expected: non_neg_integer, missed: [cell]}` (expected = done + missed, as `/school/day` shows); `Workspaces.job_scopes() :: [Scope.t()]` — for every school workspace with an active `:head` member, that head's `scope_for/2` scope.

- [ ] **Step 1: Failing tests**

```elixir
# school_life_test.exs — reuse the school_day setup (one done roll call, one missed)
test "roll_call_counts matches the day grid", ctx do
  day = Attendance.school_day(ctx.scope, ctx.date, ctx.now)
  counts = Attendance.roll_call_counts(ctx.scope, ctx.date, ctx.now)
  assert counts.missed == day.missed
  assert counts.expected == counts.done + length(day.missed)
end
```
```elixir
# workers/missed_roll_calls_test.exs
use TeacherAssistant.DataCase, async: false
use Oban.Testing, repo: TeacherAssistant.Repo
# setup: verified school, a lesson slot at 08:25 today (Monday 2025-09-15, the frozen test clock) with no roll call,
# a discipline master member `sg`; set :school_clock_now to 2025-09-15 11:30Z (12:30 school time) in the test
# (Application.put_env + on_exit restore — see how other tests freeze it: grep school_clock_now test/).
test "one notice per school listing the missed calls", ctx do
  assert :ok = perform_job(MissedRollCalls, %{})
  assert [%{kind: :missed_roll_calls, params: %{"count" => "1", "half" => "morning"}}] =
           Notifications.inbox(ctx.sg, 1).results
  assert :ok = perform_job(MissedRollCalls, %{})        # retried: no duplicate
  assert length(Notifications.inbox(ctx.sg, 1).results) == 1
end

test "nothing when every call is done", ctx do … record the roll call, perform, assert inbox empty end
test "nothing on a holiday", ctx do … Attendance/Organization holiday on today, perform, assert empty end
```
```elixir
# workers/expired_temporary_passwords_test.exs
test "reports an account expired in the last 24 hours once, never a used one", ctx do
  # member a: must_change_password true, temporary_password_expires_at = now - 2h
  # member b: must_change_password false, expires_at = now - 2h
  # member c: must_change_password true, expires_at = now - 3 days
  assert :ok = perform_job(ExpiredTemporaryPasswords, %{})
  assert [%{params: %{"name" => name}}] = Notifications.inbox(ctx.head, 1).results
  assert name == User.display_name(ctx.a)
end
```
(Set the user fields with `Ash.Changeset.for_update` on the user's existing admin/temporary-password action — grep `temporary_password_expires_at` in `lib/teacher_assistant/accounts/user.ex` for the action that sets it; `authorize?: false` in the fixture.)
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**
  - `application.ex`: add `{Oban, Application.fetch_env!(:teacher_assistant, Oban)}` to children after the Repo.
  - `config.exs`: `plugins: [{Oban.Plugins.Cron, crontab: [{"30 11 * * 1-6", TeacherAssistant.Workers.MissedRollCalls, args: %{"half" => "morning"}}, {"30 16 * * 1-6", TeacherAssistant.Workers.MissedRollCalls, args: %{"half" => "afternoon"}}, {"10 6 * * *", TeacherAssistant.Workers.ExpiredTemporaryPasswords}]}]` (UTC; school time is UTC+1). Tests run with `testing: :manual` (already set).
  - `SchoolLife.roll_call_counts/3`: from `school_day/3` (`done` = count of `:done` cells over `rows`, the logic of `DayLive.count_status/2`); `DayLive` uses it for `@done`.
  - `Workspaces.job_scopes/0`: read every `SchoolMembership` with role `:head` and `active` (authorize?: false, no tenant — use the existing global read used for "a user's schools", grep `list_workspaces_for`), dedupe by workspace, `scope_for(user, ws_id)` and keep `{:ok, scope}` results.
  - `MissedRollCalls.perform/1` (`use Oban.Worker, queue: :default, unique: [period: 3600]`): for each job scope with `Scope.school_verified?`, `today = Reference.today()`, skip when `Attendance.day_off(scope, today)` is not nil; `half` from args (default by `Reference.now().hour < 13`); missed = `roll_call_counts(...).missed` filtered to the half (`period.start_time.hour < 13` for morning); none → skip. Dedup: skip when a `:missed_roll_calls` notification with the same `half` param exists for that school today (one read on `Accounts.Notification`, tenant = workspace, authorize?: false). Recipients: active members with `:head` or `:discipline_master`. Params: `count`, `half`, `list` = `Enum.map_join(missed, " · ", &"#{&1.class_group.label} #{hm(&1.period.start_time)} (#{teacher_name})")`.
  - `ExpiredTemporaryPasswords.perform/1`: for each job scope, members whose user has `must_change_password == true` and `temporary_password_expires_at` in `[now - 24h, now]`; one `:temporary_password_expired` notice per account to `Notifications.admin_ids(scope)`.
- [ ] **Step 4: Run** the three test files plus `test/teacher_assistant_web/live/school/day_live_test.exs` (grep the day test file name) — PASS. Commit `feat: scheduled notices for missed roll calls and unused temporary passwords`.

---

### Task 5: « À relancer » — every lagging course, per teacher

**Files:**
- Modify: `lib/teacher_assistant/academics/entry_progress.ex:~290-310` (`late/2`)
- Modify: `lib/teacher_assistant/assessment.ex:182-189` (`remind_late/3`), add `remind_teacher/4`
- Test: `test/teacher_assistant/academics/entry_progress_test.exs:135-150`, `test/teacher_assistant/academics/entry_reminder_test.exs`

**Interfaces:**
- Produces: `grid.late :: [%{teacher: user | nil, teacher_id: id | nil, courses: [%{tc_id, subject, class, pct}]}]` sorted by teacher name; `grid.late_teacher_count == length(grid.late)`; `Assessment.remind_teacher(scope, year, seq, teacher_id) :: {:ok, sent_count}`; `remind_late/3` reminds every course in `grid.late`.

- [ ] **Step 1: Failing tests** — replace the `grid.late` assertion at `entry_progress_test.exs:148`:

```elixir
english = ctx.english_teacher.id
head_id = ctx.head.current_user.id
assert [%{teacher_id: ^english, courses: en}, %{teacher_id: ^head_id, courses: mine}] =
         Enum.sort_by(grid.late, &(&1.teacher_id != english))
assert Enum.map(en, &{&1.class, &1.pct}) == [{"4e B", 0}, {"3e A", 0}]
assert [%{subject: "Maths", class: "3e A", pct: 50}] = mine
assert grid.late_teacher_count == 2
```
In `entry_reminder_test.exs`: `remind_late` now also reminds the 50 % course (adjust the expected count), and

```elixir
test "remind_teacher reminds each of the teacher's lagging courses once a day", ctx do
  assert {:ok, n} = Assessment.remind_teacher(ctx.head, ctx.year, ctx.seq, ctx.teacher_id)
  assert n >= 1
  assert {:ok, 0} = Assessment.remind_teacher(ctx.head, ctx.year, ctx.seq, ctx.teacher_id)
end
```
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** `late/2`: for each row, cells with integer `pct < 100` → `{teacher_user_id, %{tc_id, subject: subject label, class: cg.label, pct}}`; group by teacher id; `teacher` from the cell; sort courses by row order, teachers by `teacher_name/1`. `remind_late/3` = `tc_ids` from `grid.late`; `remind_teacher/4` = the same filtered to `teacher_id`. Update `sequence_tracking_live.ex` only enough to compile (Task 6 restyles it): the « À relancer » list iterates `late.courses`.
- [ ] **Step 4: Run** both files plus `test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs` (adjust assertions that expected only 0 % courses) — PASS. Commit `feat: late list covers every lagging course, per teacher`.

---

### Task 6: Suivi des séquences screen

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/sequence_tracking_live.ex`
- Test: `test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs`

**Interfaces:**
- Consumes: `grid.late` shape and `Assessment.remind_teacher/4` (Task 5).

- [ ] **Step 1: Failing tests**

```elixir
test "séquence tabs name their state", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
  assert has_element?(view, "#seq-tab-#{ctx.seq.id}", "en cours")
end

test "a complete cell shows ✓ and partial courses are listed per teacher", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/sequences?seq=#{ctx.seq.id}")
  assert has_element?(view, "#late-#{ctx.teacher_id}", "(50 %)")   # a teacher with a half-entered course
  view |> element("#remind-teacher-#{ctx.teacher_id}") |> render_click()
  assert has_element?(view, "#remind-teacher-#{ctx.teacher_id}", "Relancé")
end

test "no KPI row", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/sequences")
  refute has_element?(view, "#tracking-kpis")
end
```
(Use the file's setup; add a 50 % course if absent. Replace tests asserting removed KPI ids.)
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**
  - Header: eyebrow `gettext("Séquence %{n} · saisie jusqu'au %{date} (J-%{d})", …)` (reuse `deadline_text`), title « Suivi de la saisie des notes ».
  - Tabs `<nav id="seq-tabs">`: `<.link patch id={"seq-tab-#{s.id}"}>` labelled « Séq. N · close » (`Lock.locked?(s)`), « Séq. N · en cours » (started, not locked), « Séq. N » (future); active `bg-primary text-primary-content`.
  - Grid: cell text « ✓ » at 100, « N % » otherwise, « · » not taught; colours `bg-primary/20 text-primary` / `bg-warning/20 text-warning` / `bg-error/20 text-error`; legend line. Cell click keeps opening the detail panel.
  - Remove the KPI tiles (`#tracking-kpis` / their ids).
  - « À relancer · N » `ta-panel`: one `<li id={"late-#{teacher_id}"}>` per teacher: name, « <subject> · <class> (<pct> %), … » grouped by subject, button `id={"remind-teacher-#{teacher_id}"}` `phx-click="remind-teacher"` → label « Relancé ✓ » when every course of the teacher has a reminder dated today in `@reminders`; « Relancer tous » keeps `remind-late`. Flash `ngettext("%{count} rappel envoyé.", "%{count} rappels envoyés.", n)`.
  - `handle_event("remind-teacher", %{"teacher" => id})`: only a teacher present in `@grid.late`.
- [ ] **Step 4: Run** — PASS. Commit `feat: séquence tracking follows the mockup`.

---

### Task 7: Corrections review — cards, required refusal reason

**Files:**
- Modify: `lib/teacher_assistant/academics/mark_correction.ex` (`:refuse` requires the note)
- Modify: `lib/teacher_assistant_web/live/school/correction_review_live.ex`
- Test: `test/teacher_assistant/academics/mark_correction_test.exs`, `test/teacher_assistant_web/live/school/correction_review_live_test.exs`, `test/teacher_assistant_web/live/school/corrections_live_test.exs` (its refuse calls now pass a note)

- [ ] **Step 1: Failing tests**

```elixir
# mark_correction_test.exs (in the "decision note and motives" describe)
test "refusing without a note is rejected", ctx do
  {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
  assert {:error, _} = Assessment.refuse_correction(ctx.censeur, c, "   ")
  assert {:error, _} = Assessment.refuse_correction(ctx.censeur, c)
end
```
```elixir
# correction_review_live_test.exs
test "pending requests are cards; refusing asks a reason first", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
  assert has_element?(view, "#correction-card-#{ctx.c.id}", "12 → 14")
  view |> element("#refuse-#{ctx.c.id}") |> render_click()
  assert has_element?(view, "#refuse-form-#{ctx.c.id}")
  html = view |> form("#refuse-form-#{ctx.c.id}", %{"refusal" => %{"note" => ""}}) |> render_submit()
  assert html =~ "Indiquez le motif du refus."
  view |> form("#refuse-form-#{ctx.c.id}", %{"refusal" => %{"note" => "Copie absente"}}) |> render_submit()
  assert [%{status: :refused, decision_note: "Copie absente"}] = Assessment.list_corrections(ctx.censeur, :decided)
end

test "the journal is on the same page under the cards", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
  assert has_element?(view, "#journal")
end
```
Update existing tests that clicked `#pending-…` rows / `#approve-correction` / `#refuse-correction` / `#decision-form` to the card ids (`#accept-#{id}`, note field `#accept-form-#{id}`), and every `Assessment.refuse_correction(…, c)` call in other tests to pass a note.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**
  - `mark_correction.ex` `update :refuse`: `validate present(:decision_note), message: "a refusal needs a note"` placed after the argument is copied — simplest: in `Decide` for `decision: :refused`, add an error when the trimmed argument is nil/"" (keep `:approve` unaffected).
  - Review page: drop the `select` panel. Header eyebrow « Censorat · intégrité des notes », title « Corrections de notes », subtitle `ngettext("%{count} demande en attente", …) <> " · " <> gettext("une note ne change qu'après votre décision")`. Tabs « En attente » / « Traitées » kept; « Journal » tab removed — the journal table (`#journal`, heading « Journal des notes », lead « Toute modification après verrouillage est tracée. ») renders under the cards on the pending tab.
  - Card `<article id={"correction-card-#{c.id}"} class="ta-leaf space-y-3">`: student (font-semibold), « <classe> · <matière> · Séquence N · <évaluation> », `ta-num text-3xl` « 08 → 13 », « Moyenne de séquence : a → b » (`Assessment.correction_averages/2`, computed for all pending cards at load), motive chip (`badge badge-outline`), « Demandée par <nom> · <Dates.relative> <HH:MM> ». Actions: `<.form id={"accept-form-#{c.id}"} phx-submit="accept">` with an optional note input + « Accepter » (primary); « Refuser » button `id={"refuse-#{c.id}"}` `phx-click="start-refuse"` sets `@refusing = c.id`, which reveals `<.form id={"refuse-form-#{c.id}"} for={@refuse_form} phx-submit="refuse">` with a required textarea (« Motif du refus ») and « Confirmer le refus » (error style) + « Annuler ». Empty reason → form error « Indiquez le motif du refus. » (no call). Note > 500 chars → « La note dépasse 500 caractères. ». Flash after accept `gettext("Correction acceptée : %{student} %{change}. Bulletin recalculé.", …)`, after refuse « Demande refusée. L'enseignant est prévenu. ». Empty: « Aucune demande en attente. ».
- [ ] **Step 4: Run** the three files plus `test/teacher_assistant/academics/mark_correction_notifications_test.exs` — PASS. Commit `feat: correction review cards with a required refusal reason`.

---

### Task 8: Proviseur dashboard

**Files:**
- Modify: `lib/teacher_assistant/academics/school_life.ex` (`absences_to_justify/2`), `lib/teacher_assistant/attendance.ex` (defdelegate), `lib/teacher_assistant_web/spaces.ex:95-116` (use it)
- Create: `lib/teacher_assistant/pilotage.ex` (`todo/1`: the dashboard's to-do facts)
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex`
- Test: `test/teacher_assistant/academics/school_life_test.exs`, `test/teacher_assistant/pilotage_test.exs`, `test/teacher_assistant_web/live/school/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `Attendance.roll_call_counts/3` (Task 4), `grid.late_teacher_count` (Task 5), `Councils.status/2` (Task 1).
- Produces: `Attendance.absences_to_justify(scope, today) :: %{count: integer, flagged_students: integer, alert_hours: integer}`; `Pilotage.todo(scope) :: %{classes_without_pp: [cg], unassigned: [%{class: label, subject: name}], pending_accounts: %{count, expired}, councils_to_plan: integer, oldest_correction: Date.t() | nil}`.

- [ ] **Step 1: Failing tests**

```elixir
# school_life_test.exs — reuse the absences setup
test "absences_to_justify counts unjustified rows and flagged students", ctx do
  r = Attendance.absences_to_justify(ctx.scope, ctx.today)
  rows = Attendance.absence_days(ctx.scope, ctx.first, ctx.last, ctx.today)
  assert r.count == Enum.count(rows, &(not &1.justified?))
  assert r.flagged_students == rows |> Enum.filter(&(&1.flagged? and not &1.justified?)) |> Enum.uniq_by(& &1.enrollment.id) |> length()
end
```
```elixir
# pilotage_test.exs
test "to-do facts" do
  %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
  {:ok, cg} = Enrollment.create_class_group(head, year, %{label: "6e Z", level: "6ème"})
  todo = Pilotage.todo(%{head | current_academic_year: year})
  assert Enum.any?(todo.classes_without_pp, &(&1.id == cg.id))
  assert todo.pending_accounts.count >= 0
end
```
```elixir
# dashboard_live_test.exs (head, complete verified school)
test "KPI cards link to their screens", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school")
  assert has_element?(view, "#dashboard h1", "Bonjour")
  for {id, href} <- [{"kpi-entry", "/school/sequences"}, {"kpi-calls", "/school/day"},
                     {"kpi-absences", "/school/absences"}, {"kpi-corrections", "/school/corrections/review"}],
      do: assert has_element?(view, "##{id}[href='#{href}']")
end

test "to-do rows appear only when their condition holds", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school")
  assert has_element?(view, "#todo-no-pp")            # the fixture's classes have no form master
  refute has_element?(view, "#todo-corrections")      # no pending correction
end

test "the setup checklist is hidden once setup is complete", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school")
  refute has_element?(view, "#setup-checklist")
end

test "entry bars per class", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school")
  assert has_element?(view, "#entry-bars [data-class]")
end
```
Adjust existing dashboard tests that asserted the three stats (`Classes`/`Élèves`/`Enseignants` counts) — they move out; keep checklist/verification tests for incomplete/unverified schools.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**
  - `absences_to_justify/2`: `current_sequence_range` + `absence_days`, count unjustified, flagged unique enrollments; `alert_hours` from `school_life_rules`. `Spaces.counts(:surveillant)` uses `.count`.
  - `Pilotage.todo/1`: classes of the current year with `form_master_user_id == nil`; `Curriculum.assignment_overview(scope).cells` of kind `:to_assign` mapped to `%{class, subject}`; members whose user has `must_change_password` (count, and expired = `temporary_password_expires_at` in the past); councils to plan = classes of the current term (`Councils.default_term/2`) whose `Councils.status(for_period[cg.id], published?)` is `:to_plan`; oldest pending correction `inserted_at` date (`Assessment.list_corrections(scope, :pending)` is oldest first).
  - Dashboard render (keep the non-workspace / no-year branches as today):
    - Header eyebrow « <Dates.long(today)> · Séquence N · J-n » (current séquence via `Assessment.default_sequence`; parts omitted when absent), title `gettext("Bonjour, %{name}", name: User.display_name(user))`.
    - KPI row `grid gap-3 sm:grid-cols-2 lg:grid-cols-4`, each an `<.link navigate id=…>` `ta-leaf` card with label, `ta-num text-3xl` value, sub-line: `kpi-entry` (overall % of `Assessment.sequence_entry_grid`; red < 60, amber < 100, green 100; « N enseignants à relancer »), `kpi-calls` (« done / expected », « N non faits »), `kpi-absences` (count, « N élèves au-delà de X h »), `kpi-corrections` (pending count, « en attente de décision »).
    - « À traiter · N » `ta-panel` list, rows `todo-corrections` (« N corrections de notes à décider », « La plus ancienne date du <day_month> », Décider → review), `todo-late` (« N enseignants en retard de saisie », « Séquence N · clôture le … », Relancer → sequences), `todo-no-pp` (« <classe> sans professeur principal », « N élèves · bulletins bloqués sans PP » — one row per class, max 3 then « + N autres »; Désigner → `/school/classes/:id`), `todo-unassigned` (« N matières sans enseignant », list of « matière (classe) », Affecter → `/school/settings/assignments` — grep the assignments route), `todo-accounts` (« N comptes en attente de première connexion », « Dont N mot de passe temporaire expiré », Voir → `/school/members`), `todo-councils` (« N conseils de classe à planifier », « Trimestre N », Planifier → `/school/councils`). Coloured left mark per row (`bg-warning`/`bg-error`/`bg-info`). Empty: « Rien à traiter ».
    - `#entry-bars` « Saisie Séquence N par classe » with « Détail → »: per grid row a `<div data-class={label}>` label + bar `width: pct%` (`bg-primary` ≥ 90, `bg-warning` ≥ 60, `bg-error` below) + « N % ».
    - Below: verification callout and `#setup-checklist` only when `not Scope.setup_complete?(scope)` or unverified; « Mes cours » / « Mes classes » only when present. Remove the three stats.
- [ ] **Step 4: Run** the three files plus `test/teacher_assistant_web/spaces_test.exs` — PASS. Commit `feat: Proviseur dashboard follows the mockup`.

---

### Task 9: Conseils de classe list

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/councils_live.ex`
- Test: `test/teacher_assistant_web/live/school/councils_live_test.exs`

**Interfaces:**
- Consumes: `Councils.schedule/5`, `Councils.status/2` (Task 1); `Discipline.class_discipline/3` for conduct readiness.

- [ ] **Step 1: Failing tests**

```elixir
test "summary, statuses and CTAs", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/councils")
  assert has_element?(view, "#councils-summary", "à planifier")
  assert has_element?(view, "#council-row-#{ctx.cg.id} [data-status='to_plan']", "À planifier")
  assert has_element?(view, "#plan-#{ctx.cg.id}")
end

test "« Planifier » saves date and time inline", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/councils")
  view |> element("#plan-#{ctx.cg.id}") |> render_click()
  view |> form("#plan-form-#{ctx.cg.id}", %{"plan" => %{"date" => "2025-10-14", "time" => "14:00"}}) |> render_submit()
  assert has_element?(view, "#council-row-#{ctx.cg.id} [data-status='planned']", "Planifié")
  assert has_element?(view, "#council-row-#{ctx.cg.id}", "14:00")
end

test "a held council links to its PV", ctx do
  {:ok, _} = Councils.hold(ctx.head, ctx.cg, ctx.period)
  {:ok, view, _} = live(ctx.conn, ~p"/school/councils")
  assert has_element?(view, "#council-row-#{ctx.cg.id} a[href^='/school/councils/#{ctx.cg.id}/print']", "Voir le PV")
end
```
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**: eyebrow « Trimestre N » / « Année », title « Conseils de classe », `#councils-summary` « N classes · N tenus · N planifiés · N à planifier » (held + closed count as « tenus »). Table rows `id={"council-row-#{cg.id}"}`: Classe (link), Date (« Mar 14 oct. · 14:00 » — `Dates.short(held_on) <> " · " <> HH:MM`; date only when no time and status held; « — » to plan), Préparation (« Notes N % » + « · conduite à saisir » when any enrollment has `note_de_conduite == nil` in `class_discipline`, else « Prêt » when entry 100 % and conduct complete), Statut pill `data-status` (to_plan `bg-warning/20 text-warning`, planned `bg-info/20 text-info`, held/closed `bg-primary/20 text-primary`; labels À planifier / Planifié / Tenu / Clôturé), CTA: to_plan → button `id={"plan-#{cg.id}"}` toggling an inline `<.form id={"plan-form-#{cg.id}"} for={@plan_form} phx-submit="plan">` (date pre-filled with the term council date, time input, Enregistrer/Annuler); planned → « Préparer » link to the council; held/closed → « Voir le PV » link to `/school/councils/:id/print?period=…` (reuse the existing PV link format). Errors from `schedule` (locked) flash « Conseil verrouillé : bulletins publiés. ». Term/year tabs kept.
- [ ] **Step 4: Run** — PASS. Commit `feat: councils list with planning`.

---

### Task 10: Conseil de classe page

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/council_live.ex`
- Test: the council LiveView test (grep `CouncilLive` in `test/` — likely `councils_live_test.exs` or `council_live_test.exs`)

**Interfaces:**
- Consumes: `ClassCouncil.starts_at`, `Councils.save_header/4` accepting `starts_at` (Task 1).

- [ ] **Step 1: Failing tests**

```elixir
test "decision chips save one choice and lock after « Clôturer »", ctx do
  {:ok, view, _} = live(ctx.conn, council_path(ctx))
  [s | _] = ctx.students
  view |> element("#decision-#{s.id}-tableau_honneur") |> render_click()     # use a real CouncilDistinctionChoice value
  assert has_element?(view, "#decision-#{s.id}-tableau_honneur[aria-pressed='true']")
  view |> element("#close-council") |> render_click()
  assert has_element?(view, "#close-council", "Conseil clôturé")
  assert has_element?(view, "#decision-#{s.id}-tableau_honneur[disabled]")
  assert has_element?(view, "#reopen-council")
end

test "header line and conduct out of 20", ctx do
  {:ok, view, _} = live(ctx.conn, council_path(ctx))
  assert has_element?(view, "#council h1", "Conseil de classe · #{ctx.cg.label}")
  assert has_element?(view, "#council-details")       # the disclosure keeps the existing form
end
```
(Grep `CouncilDistinctionChoice` values for the real chip value; existing tests using the distinction select/`set_decision` form need the chip ids; tests on header form, appreciation, conduct warning and passage keep working inside `#council-details`.)
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**: back link « ← Conseils de classe »; eyebrow « <période> · <Dates.long(held_on)> · <HH:MM> »; title « Conseil de classe · <classe> »; line « Présidé par <chair || "—"> · PP : <form master name> »; actions « Imprimer le PV » (existing link), `#close-council` (« Clôturer le conseil » → existing hold event with its confirmation under 100 %; when held, disabled button « Conseil clôturé ✓ ») and `#reopen-council` (« Rouvrir », existing event). Table: Élève, Moy. trim. (red < 10), Conduite (`note_de_conduite` from `Discipline.class_discipline/3` by enrollment, « 16 » or « — »), Décision: chips `id={"decision-#{student_id}-#{choice}"}` `phx-click="choose"` for each distinction choice offered today (and « Aucune »), `aria-pressed` on the current value (stored choice, else the proposal), `disabled` when held or locked; click re-uses the existing `set_decision` path with only `distinction_choice` changed (keep appreciation/warning/passage values). Footnote paragraph (spec §2.6 text). `<details id="council-details">` « Détails du conseil » containing the existing header form (add a time input bound to `starts_at`), stats and per-student appreciation / conduct warning / passage controls, unchanged events.
- [ ] **Step 4: Run** the council tests plus `test/teacher_assistant/councils_test.exs` and `test/teacher_assistant_web/controllers/council_print_controller_test.exs` — PASS. Commit `feat: council page with decision chips`.

---

### Task 11: Configurable report card elements and the on-screen bulletin

**Files:**
- Modify: `lib/teacher_assistant/academics/bulletin_element.ex` (seven values + labels)
- Modify: `lib/teacher_assistant/report_cards.ex:36-54` (`live_view/3` adds `teachers`)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` (assigns `teachers`, `highest`, `lowest`, `head_name`, `verify_url` per bundle)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html.ex` (column counts), `.../bulletin_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex`
- Test: `test/teacher_assistant/academics/bulletin_template_test.exs`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`, `test/teacher_assistant_web/live/school/bulletin_live_test.exs`, `test/teacher_assistant_web/live/school/bulletin_template_live_test.exs`

**Interfaces:**
- Produces: `BulletinElement` values `:subject_rank, :subject_teacher, :class_extremes, :repeater, :form_master, :parent_visa, :verify_link`; `ReportCards.live_view/3` map gains `teachers: %{context_id => display_name}` (absent in older snapshots → read with `Map.get(view, :teachers, %{})`).

- [ ] **Step 1: Failing tests**

```elixir
# bulletin_template_test.exs
test "new elements are on by default, off for a school that saved its list" do
  for el <- [:subject_rank, :subject_teacher, :class_extremes, :repeater, :form_master, :parent_visa, :verify_link],
      do: assert(el in BulletinTemplate.elements(nil))
  refute :subject_rank in BulletinTemplate.elements([:rank, :class_average])
end
```
```elixir
# bulletin_print_controller_test.exs — reuse its setup (draft bulletin of a student with marks)
test "shows subject teacher, subject rank, class extremes, PP and parent visa", ctx do
  html = ctx.conn |> get(print_path(ctx)) |> html_response(200)
  assert html =~ TeacherAssistant.Accounts.User.display_name(ctx.teacher_user)
  assert html =~ "Rang"                    # subject rank column header
  assert html =~ "Plus forte"
  assert html =~ "Visa du parent"
end

test "an element switched off disappears", ctx do
  {:ok, _} = TeacherAssistant.Assessment.update_bulletin_settings(ctx.head, %{"elements" => ["rank"]})   # use the real settings function (grep bulletin_elements in assessment.ex)
  html = ctx.conn |> get(print_path(ctx)) |> html_response(200)
  refute html =~ "Visa du parent"
  refute html =~ "Plus forte"
end

test "a snapshot published before teachers were stored still prints", ctx do
  # publish, then strip :teachers from the stored snapshot (Ash update with authorize?: false or Repo update)
  html = ctx.conn |> get(print_path(ctx)) |> html_response(200)
  assert html =~ "Bulletin de notes"
end
```
```elixir
# bulletin_live_test.exs
test "the bulletin page embeds the print document", ctx do
  {:ok, view, _} = live(ctx.conn, bulletin_path(ctx))
  assert has_element?(view, "#bulletin-sheet[src^='/school/classes/#{ctx.cg.id}/students/#{ctx.enrollment.id}/bulletin/print']")
  assert has_element?(view, "a", "Fiche élève")
end
```
Rewrite existing `bulletin_live_test.exs` content assertions (subject table, stats) as print-controller assertions where they are not already covered.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**
  - `BulletinElement`: add the seven values (after `:qr_code`), labels (« Rang par matière », « Enseignant de chaque matière », « Plus forte / plus faible moyenne de la classe », « Redoublant(e) », « Professeur principal », « Visa du parent », « Lien de vérification en ligne »); `defaults/0` stays `values() -- [:qr_code]`. The template page lists `values()` so the checkboxes appear unticked for schools with a saved list — assert in `bulletin_template_live_test.exs` that `input[value='subject_rank']` exists.
  - `ReportCards.live_view/3`: `teachers:` — teaching contexts of the class this year with `teacher` loaded → `%{tc.id => User.display_name(tc.teacher)}` (combined-course members included, keyed by each member context id since `subjects[].context_id` is the class's own context).
  - Print controller: per bundle `verify_url` (the URL already built for the QR, nil when unpublished); assigns `teachers` (`Map.get(view, :teachers, %{})`), `highest`/`lowest` from the period results (`view.results.highest/lowest`), `head_name` (first active member with role `:head`, display name).
  - Template:
    - subject cell: `{row.label}` + `<div :if={show?(@template, :subject_teacher) and @teachers[row.context_id]} class="teacher">{…}</div>` (small, grey);
    - new last column `<th :if={show?(@template, :subject_rank)} class="num">Rang</th>` / `<td>{row.subject_rank || "—"}</td>`; include it in `trailing_cols/1` (`+ if show?(:subject_rank), 1, 0`);
    - identity rows: « Redoublant(e) : oui/non » when `:repeater` (from `b.enrollment.repeater`, `Map.get` for old snapshots), « Professeur principal : <name> » when `:form_master`;
    - totals line: « Plus forte : X · plus faible : Y » when `:class_extremes` and values present;
    - visa: a « Visa du parent » slot when `:parent_visa`; under the head's line the head's name when present;
    - next to the QR: `<p :if={show?(@template, :verify_link) and b.verify_url} class="verify">Vérifiable en ligne : {b.verify_url}</p>`.
    All behind `show?` — output unchanged for schools with the old elements only.
  - `BulletinLive` (keep mount/rights/period select): top bar `← Bulletins de la <classe>` (→ `/school/bulletins?class=…&period=…`), « Fiche élève » (student page route — grep `students/:id` live route), « Imprimer » (print route, `target="_blank"`); body: `<div class="ta-panel overflow-x-auto !p-2"><iframe id="bulletin-sheet" src={print_path} title={gettext("Bulletin")} class="block h-[1400px] w-[794px] max-w-none rounded bg-white"></iframe></div>` (A4 width, scrolls horizontally inside its card on phones). Drop the duplicated HTML table/stats now shown by the print document.
- [ ] **Step 4: Run** the four files plus `test/teacher_assistant_web/controllers/bulletin_verify_controller_test.exs` and `test/teacher_assistant/report_cards_test.exs` — PASS. Commit `feat: configurable report card elements and on-screen bulletin`.

---

### Task 12: Bulletins list

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (`publish_checklist/3`)
- Modify: `lib/teacher_assistant_web/live/school/bulletins_live.ex`
- Test: `test/teacher_assistant/report_cards_test.exs`, `test/teacher_assistant_web/live/school/bulletins_live_test.exs`

**Interfaces:**
- Consumes: `Councils.council/3`, `Councils.status/2` (Task 1), `Pilotage.todo/1`-style unassigned lookup — use `Curriculum.assignment_overview/1` filtered to the class.
- Produces: `ReportCards.publish_checklist(scope, cg, period) :: [%{key: :notes | :conduct | :council, ok?: boolean, text: String.t()}]` (texts built in the LiveView from data: return `%{key, ok?, data}` with `data` = `%{rate, unassigned}` / `%{entered, effectif}` / `%{status, date, time}`).

- [ ] **Step 1: Failing tests**

```elixir
# report_cards_test.exs
test "publish checklist: notes, conduct, council", ctx do
  checks = ReportCards.publish_checklist(ctx.head, ctx.cg, ctx.period)
  assert [%{key: :notes}, %{key: :conduct, data: %{entered: 0}}, %{key: :council, ok?: false}] = checks
end
```
```elixir
# bulletins_live_test.exs
test "a draft trimester shows its banner and checklist", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/bulletins?class=#{ctx.cg.id}&period=#{ctx.period_param}")
  assert has_element?(view, "#draft-banner", "pas encore publiés")
  assert has_element?(view, "#publish-checks [data-check='conduct']", "Conduite")
  assert has_element?(view, "#publish-bulletins")
end

test "a séquence tab is read-only", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/bulletins?class=#{ctx.cg.id}&period=#{ctx.seq_param}")
  refute has_element?(view, "#publish-bulletins")
  refute has_element?(view, "#draft-banner")
  assert has_element?(view, "#bulletin-ranking")
end

test "ranks are ordinal and averages under 10 are red", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/bulletins?class=#{ctx.cg.id}&period=#{ctx.period_param}")
  assert has_element?(view, "#bulletin-ranking", "1er")
end
```
(Use the file's setup; `seq_param` via `Organization.period_param({:sequence, seq})`. Keep the existing publish/withdraw/history tests passing — update selectors that moved.)
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**
  - `ReportCards.periods` (`report_cards.ex:235`) — add séquence periods to the tab list (`{:sequence, seq}` for each séquence of the year, before trimesters); `publish/3` still refuses séquences.
  - `publish_checklist/3`: notes `entry_rate` (ok when 100) + unassigned subjects of the class; conduct entered = enrollments with non-nil `note_de_conduite` in `Discipline.class_discipline/3` vs effectif (ok when equal); council = `Councils.status(stored, false)` (ok when `:held`), with date/time.
  - Bulletins page: eyebrow « Bulletins · <classe> », title « Bulletins »; segmented class tabs and period tabs (séquences « Séquence N », trimesters, « Année »); published → `#published-banner` `bg-primary/10 border-primary/45` « Publiés le <date> par <nom> · visibles par les professeurs principaux et imprimables. » + « Imprimer toute la classe »; draft trimester/year → `#draft-banner` `bg-warning/10 border-warning/45` « <Période> — pas encore publiés », `#publish-checks` lines `data-check` with ✓ (`text-primary`) / ! (`text-warning`) and texts « Notes : N % saisies (N matière(s) sans enseignant) », « Conduite : x / effectif notes », « Conseil de classe : prévu le … à HH:MM / tenu le … / à planifier », then `#publish-bulletins` « Publier les bulletins » (existing publish event and rules); séquence → no banner. `#bulletin-ranking` table: Rang (`ordinal(n)`: « 1er » / « Ne », EN « 1st »… via gettext), Élève, Moyenne (red < 10, decimal comma), Distinction; row click selects; side card « <nom> », « <rang> / <effectif> · moyenne X », per-subject averages, « Ouvrir → » (bulletin page). Withdraw + history kept below; per-row print icon removed.
- [ ] **Step 4: Run** both files plus `test/teacher_assistant/report_cards_access_test.exs` — PASS. Commit `feat: bulletins list with banners and pre-publish checklist`.

---

### Task 13: Translations, final migration, checks

**Files:**
- Modify: `priv/gettext/**`, `priv/repo/migrations/*`, `priv/resource_snapshots/**`

- [ ] **Step 1:** `mix gettext.extract --merge`; fill every new EN msgstr (plural forms too); new FR entries get empty msgstr; clear every `#, fuzzy` flag on entries new this cycle (compare against `main`'s po with a script, as in the previous cycle); pre-existing fuzzies untouched.
- [ ] **Step 2:** Delete the `--dev` migration(s) and dev snapshot(s) from Task 1, `mix ash.codegen pilotage_redesign`; drop and recreate the partition-7 test DB (`MIX_ENV=test MIX_TEST_PARTITION=7 mix ecto.drop`) so the renamed migration runs; `mix ash.migrate` for dev.
- [ ] **Step 3:** `MIX_TEST_PARTITION=7 mix precommit`; `mix compile --force` shows no warning in `lib/`; full suite green.
- [ ] **Step 4:** Commit `chore: Pilotage redesign translations and final migration` (explicit paths).
- [ ] **Step 5:** Browser pass (dev server `PORT=4017`, demo seed, as `proviseur@demo.test` and `censeur@demo.test`) at desktop and 390 px (inject a 390 px same-origin iframe and check `scrollWidth == clientWidth` on every screen): dashboard, séquences (tabs, Relancer), bulletins (draft, séquence, published), bulletin sheet, councils (Planifier), council (chips, Clôturer, Rouvrir — avoid confirm dialogs in automation: test held state via the domain if a confirm appears), corrections (cards; refusal), notifications. Fix findings in a `fix: Pilotage visual pass — …` commit.
