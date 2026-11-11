# A9 — Data retention policy and orphan photo sweep — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The product states, and enforces, what happens to a child's record after they leave: anonymised three years later, their photo file gone, orphan files swept weekly, and a member with no school left can delete their own account.

**Architecture:** Two weekly Oban workers in `lib/teacher_assistant/workers/` on the existing cron plugin. `Student` gains an `:anonymise` action and `Enrollment.anonymise_due_students/2` selects the due students from A7's `left_on` and the year's `end_date`. `Uploads` gains its first delete and a `sweep_orphans/2` whose referenced set covers students, school profiles **and** bulletin snapshots. The sweep's counts are recorded as an `AuditEvent` the daily digest reads. A new `Account.AccountLive` at `/account` hosts account deletion through a self-only `User` action that refuses while an active membership exists. The policy is written in `docs/PRODUCT.md` and on the privacy page.

**Tech Stack:** Elixir, Oban 2.22 (`Oban.Plugins.Cron`, `Oban.Testing` with `testing: :manual`), Ash 3.37, Phoenix 1.8 LiveView 1.2, Gettext FR source + EN.

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A9 (and §A7 for `left_on`).

## Global Constraints

- **Depends on A7 merged** (`Enrollment.left_on`, `departure_reason`). Do not start before.
- Three years before anonymisation (spec, user's default). Anonymisation replaces the name with « Élève parti », unlinks guardians (through `StudentGuardian :unlink`, so a sibling's guardian survives), clears `national_id`, `birth_place`, `photo_path` and deletes the photo file. `matricule`, `sex`, `birth_date`, marks, attendance, payments and bulletin snapshots are kept (statistics and the school's legal record). The published snapshots still carry the old name and photo path: a published bulletin is an issued document and is not rewritten (builder's call, stated in PRODUCT.md).
- The sweep deletes only regular files inside the three known folders `student_photos`, `school_logos`, `school_signatures`, older than one day, not referenced by `Student.photo_path`, `SchoolProfile.logo_path | signature_path | stamp_path` or any `BulletinPublication.snapshot` roster entry's `photo_path`. Everything else under `UPLOADS_DIR` (including `.write_check`, unknown folders) is left alone. The sweep takes its root as a parameter so tests use their own tmp dir (the test uploads dir is shared by async tests).
- Account deletion keeps the `users` row (audit events and memberships reference it): tokens revoked (`Accounts.revoke_all_sessions/2`), `email` and `phone` nil, `name` « Compte supprimé », `hashed_password` nil. Refused while an **active** membership exists (removal by the head is a soft deactivate).
- Never write a migration by hand; `mix ash.codegen` only if a resource changes (none planned: AuditEvent gets a new enum value only — check whether the enum is a DB constraint; if `mix ash.codegen --check` complains, generate).
- Branch `feat/audit-a9` in `.claude/worktrees/audit-a9`, `MIX_TEST_PARTITION=a9`; explicit paths in commits; Gettext extract + EN, no fuzzy; `mix precommit` green before merge.

## Review Focus

1. A student who left one school and is enrolled in another school on the same Scolaka: workspaces are tenants, the student row is per school, so each school's copy follows its own clock — Task 1 tests that a sibling row in another workspace is untouched.
2. A student with a departed enrollment and a later active one in the same school (returned the next year): never anonymised while any enrollment is not past — Task 1 tests it.
3. A photo uploaded a minute before the sweep runs, whose `set_photo` has not committed yet: the one-day age guard keeps it — Task 2 tests a fresh unreferenced file survives.
4. An account deletion attempted by an operator impersonating the member: refused like the password page (`live_user_auth.ex:37-50`) — Task 3 tests it.
5. A deleted account whose e-mail is reused by a new sign-up: the identities are freed because the columns are nil, and the old row cannot sign in (no password, no tokens) — Task 3 tests a sign-in attempt after deletion is refused.

---

### Task 1: Anonymise departed students

**Files:**
- Modify: `lib/teacher_assistant/academics/student.ex` (action `:anonymise`, lines 31–69; policy)
- Modify: `lib/teacher_assistant/enrollment.ex` (`anonymise_due_students/2`, `due_for_anonymisation/2`, next to `delete_student/2` :249)
- Modify: `lib/teacher_assistant/uploads.ex` (`delete/2`)
- Create: `lib/teacher_assistant/workers/anonymise_departed_students.ex`
- Modify: `config/config.exs:13-31` (cron `{"0 3 * * 0", TeacherAssistant.Workers.AnonymiseDepartedStudents}` — Sunday 04:00 school time)
- Test: `test/teacher_assistant/enrollment_anonymisation_test.exs` (new), `test/teacher_assistant/workers/anonymise_departed_students_test.exs` (new)

**Interfaces:**
- `Student` `update :anonymise` — `require_atomic? false`, no accepted attributes; sets `full_name: "Élève parti"` (a constant, not translated: it is data), `national_id: nil`, `birth_place: nil`, `photo_path: nil`, `photo_taken_at: nil`. Policy: `:admin` axis or a system call (`authorize?: false` from the worker). Its `after_action` unlinks every `guardian_links` entry with the `:unlink` action (`DeleteOrphanGuardian` runs) — or the context function does it before the update; builder's call, one place.
- `Uploads.delete(relative, workspace_id) :: :ok | {:error, term}` — `resolve/2` first (same path rules), then `File.rm/1`; `:ok` when the file is already gone.
- `Enrollment.due_for_anonymisation(workspace_id, today) :: [Student]` — students of the tenant with at least one enrollment, where **every** enrollment is past: `left_on != nil` or `academic_year.end_date < today`; and `max(coalesce(left_on, year.end_date)) <= Date.shift(today, year: -3)`; and `full_name != "Élève parti"`. One query with `authorize?: false, tenant: workspace_id` (an Ash aggregate `max` over enrollments of `coalesce(left_on, academic_year.end_date)`, or two reads and a filter in Elixir — ≤ 2 queries either way).
- `Enrollment.anonymise_due_students(workspace_id, today \\ Reference.today()) :: %{anonymised: n}` — for each due student: delete the photo file (if `photo_path`), unlink guardians, run `:anonymise`. Returns the count.
- Worker `perform/1`: for each workspace id (`Ash.read!(Workspace, authorize?: false)` — not `Workspaces.job_scopes/0`, which skips schools without an active head; a suspended school is still anonymised), call `anonymise_due_students/2`, rescue and `Logger.warning` per school like `MissedRollCalls.run/2`; `Logger.info` the total.

- [ ] **Step 1: Write the failing tests**

```elixir
# enrollment_anonymisation_test.exs — clock ~U[2025-09-15 …] (test default); year 2025-09-08..2026-07-31
test "a student departed more than three years ago is anonymised: name, guardians, ids, photo file" do
  # left_on 2022-06-01 (set via the :leave action with a backdated left_on); guardian linked; photo stored
  # anonymise_due_students(ws, ~D[2025-09-15]) == %{anonymised: 1}; student.full_name == "Élève parti"; national_id nil
  # guardian row gone (orphan) ; refute File.exists?(photo)
end
test "a sibling's guardian survives the anonymisation" do
test "three years minus a day is not due; a year that ended 3 years ago with no left_on is due" do
test "a student with a later active enrollment is never due" do
test "an already anonymised student is not counted again" do
test "another workspace's student is untouched" do
# worker test: perform_job(AnonymiseDepartedStudents, %{}) == :ok and the due student is anonymised
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=a9 mix test test/teacher_assistant/enrollment_anonymisation_test.exs` — FAIL (`anonymise_due_students/2` undefined).
- [ ] **Step 3: Implement** action, `Uploads.delete/2`, context functions, worker, cron line. Update the moduledoc of `StudentPhotos` (« never deleted ») and the doc of `delete_student/2` to name the two cases where a file is deleted (anonymisation, sweep).
- [ ] **Step 4: Run** both files + `test/teacher_assistant/student_photos_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(retention): anonymise students three years after they left`.

---

### Task 2: Orphan file sweep, counted in the digest

**Files:**
- Modify: `lib/teacher_assistant/uploads.ex` (`sweep_orphans/2`, `referenced_paths/0`)
- Create: `lib/teacher_assistant/workers/sweep_orphan_photos.ex`
- Modify: `lib/teacher_assistant/accounts/audit_event/action.ex` (value `:files_swept`, label « Fichiers orphelins supprimés »)
- Modify: `lib/teacher_assistant/operator.ex:86-100` (`digest/1` key `swept_files`), `lib/teacher_assistant/workers/telegram_digest.ex:29-56` (`text/2` line)
- Modify: `config/config.exs` (cron `{"30 3 * * 0", TeacherAssistant.Workers.SweepOrphanPhotos}` — after the anonymisation)
- Test: `test/teacher_assistant/uploads_sweep_test.exs` (new), `test/teacher_assistant/workers/sweep_orphan_photos_test.exs` (new), `test/teacher_assistant/workers/telegram_digest_test.exs` (digest maps at 52–59 and 73–83 gain `swept_files`), `test/teacher_assistant/operator_test.exs`

**Interfaces:**
- `Uploads.referenced_paths() :: MapSet.t(String.t())` — relative paths from `Student.photo_path` (all tenants: `Ash.read` with `authorize?: false` and no tenant filter — check that attribute multitenancy allows a tenant-less read for this resource, else iterate workspaces), `SchoolProfile.logo_path/signature_path/stamp_path`, and every `BulletinPublication` snapshot's `roster[].student.photo_path` (`Ash.Query.select([:snapshot])`, streamed with `Ash.stream!` in batches of 50 — the one place that reads all snapshots, weekly).
- `Uploads.sweep_orphans(root \\ dir(), opts \\ []) :: %{deleted: n, kept: n}` — `opts[:referenced]` (default `referenced_paths()`), `opts[:older_than]` (default one day, `DateTime`): walks `root/<folder>/<workspace_id>/<file>` for the three folders only; deletes a regular file when its relative path is not referenced and its mtime is older than the cut-off; counts the rest as kept; never touches other folders or the root.
- Worker `perform/1`: `counts = Uploads.sweep_orphans()`; records `AuditEvent :record` with `action: :files_swept, details: %{"deleted" => n, "kept" => n}` (no workspace, no actor); `Logger.info`.
- `Operator.digest/1` gains `swept_files: integer | nil` — the `details["deleted"]` of the latest `:files_swept` event within the last 7 days, nil when none. `TelegramDigest.text/2` adds, after the body and before `first_steps`, « Fichiers orphelins supprimés cette semaine : N » when `swept_files` is a positive integer (`count/2` already hides 0 and nil must not raise).

- [ ] **Step 1: Write the failing tests**

```elixir
# uploads_sweep_test.exs — own tmp root per test (System.tmp_dir!() <> unique), files created with File.touch! and a backdated mtime via File.touch!(path, time)
test "deletes an old unreferenced photo and keeps the referenced one" do
test "keeps a photo referenced only by a published bulletin snapshot" do  # publish_trimester after storing the photo, then remove_photo → still referenced
test "keeps a file younger than a day" do
test "never touches files outside the three folders or at the root" do  # root/.write_check and root/other/x.bin survive
# worker test: perform_job → :ok, an AuditEvent :files_swept with details; digest.swept_files == n; TelegramDigest text includes the line
```

- [ ] **Step 2: Run** — FAIL (`sweep_orphans/2` undefined).
- [ ] **Step 3: Implement**; update the two digest test maps; Gettext extract + EN for the digest line and the audit label.
- [ ] **Step 4: Run** the four test files + `telegram_digest_test.exs` + `operator_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(retention): weekly sweep of orphan upload files, counted in the digest`.

---

### Task 3: « Mon compte » and account deletion

**Files:**
- Modify: `lib/teacher_assistant/accounts/user.ex` (action `:delete_own_account`, policy, validation `NoActiveMembership`)
- Create: `lib/teacher_assistant/accounts/user/validations/no_active_membership.ex`
- Modify: `lib/teacher_assistant/accounts.ex` (`delete_own_account(scope) :: :ok | {:error, :has_membership}`; calls the action then `revoke_all_sessions/2`)
- Create: `lib/teacher_assistant_web/live/account/account_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex:242-247` (`live "/account", Account.AccountLive, :show` in the same `ash_authentication_live_session :account`), `lib/teacher_assistant_web/live_user_auth.ex:37-50` (the impersonation refusal covers AccountLive too), `lib/teacher_assistant_web/components/layouts.ex:367,678` (rail and sheet entry « Mon compte » → `/account`; the password page stays reachable from it)
- Test: `test/teacher_assistant_web/live/account/account_live_test.exs` (new), `test/teacher_assistant/accounts_test.exs` (deletion unit tests)

**Interfaces:**
- `User` `update :delete_own_account` — `require_atomic? false`, no accepted attributes; `change set_attribute(:email, nil)`, `:phone` nil, `:name, "Compte supprimé"`, `:hashed_password` nil; `validate {NoActiveMembership, []}` (reads `SchoolMembership :active_for_user` for the user id; error message « Demandez d'abord au chef d'établissement de vous retirer de l'école. »); policy `authorize_if expr(id == ^actor(:id))`; `:create_by_school`/identities unchanged (nil email and phone are allowed on update).
- `Accounts.delete_own_account(%Scope{current_user: user})`: runs the action with `actor: user`; on success `revoke_all_sessions(user)`; maps the validation error to `{:error, :has_membership}`.
- `AccountLive` (`/account`, auth layout like PasswordLive): identity block (`User.display_name/1`, e-mail / phone), link « Mot de passe » → `/account/password`, a `#account-schools` list of active memberships (`Organization.list_workspaces_for/1`), and a « Supprimer mon compte » section `#account-delete`: with an active membership it shows the explanatory sentence and no button; without, a button → `phx-click="delete"` with `data-confirm`; on `:ok` → `redirect(to: ~p"/")` with flash « Compte supprimé. »; impersonation → the same refusal as PasswordLive.

- [ ] **Step 1: Write the failing tests**

```elixir
# accounts_test.exs
test "a user with no active membership deletes their account: identity cleared, tokens revoked" do
  # user_fixture(); delete_own_account == :ok; reloaded email nil, phone nil, name "Compte supprimé"; Token count for subject == 0
end
test "a member of a school is refused; a deactivated membership no longer blocks" do
test "a deleted account cannot sign in with its old password" do  # AshAuthentication sign_in strategy returns error
# account_live_test.exs
test "the page shows the identity and, for a head, no delete button but the explanation" do  # register_and_log_in_user
test "a user without school deletes their account and lands on the landing page" do  # user_fixture + log_in_user; render_click #account-delete button; assert_redirect "/"
test "an operator impersonating a member is refused" do  # same helper as password_live_test's impersonation test (grep for it; if none, build the impersonating conn as impersonation_test.exs does)
test "the rail links to Mon compte" do
```

- [ ] **Step 2: Run** — FAIL (route missing, action missing).
- [ ] **Step 3: Implement**; Gettext extract + EN.
- [ ] **Step 4: Run** the two files + `password_live_test.exs` + `test/teacher_assistant_web/gettext_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(account): « Mon compte » with self-service deletion for members of no school`.

---

### Task 4: The written policy

**Files:**
- Modify: `docs/PRODUCT.md` (new `## Données personnelles` after `## Product quality bar`, line 126)
- Modify: `lib/teacher_assistant_web/controllers/page_html.ex:332` (`privacy_sections/0`: new section `"retention"` « Combien de temps » after `"kept"`; update the `"owner"`/rights paragraphs if they contradict), `page_html/privacy.html.heex` (date line 29 → the merge date; `#privacy-rights` gains the account-deletion sentence)
- Test: `test/teacher_assistant_web/controllers/page_controller_test.exs:152-190`

**Interfaces:**
- PRODUCT.md states, in five short paragraphs: records belong to the school and live while it is active; a departed student is anonymised three years after `left_on` or the end of their last year (what is replaced, what is kept, published bulletins untouched); orphan files swept weekly; a member with no school deletes their own account, a member of a school is removed by the head first; what the operator never does (sell, share).
- Privacy page section « Combien de temps » with the same facts in user words (FR, EN filled); « Consulter, corriger ou supprimer » adds « Un membre qui n'appartient plus à aucune école peut supprimer son compte depuis Mon compte. »

- [ ] **Step 1: Write the failing test** — `page_controller_test.exs`: the `main h2` list includes « Combien de temps »; EN render includes "How long".
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Write** both documents; Gettext extract + EN.
- [ ] **Step 4: Run** the file + gettext test — PASS.
- [ ] **Step 5: Commit** `docs(privacy): retention policy in PRODUCT.md and on the privacy page`.

---

### Task 5: Verify and merge

- [ ] Browser check (worktree server on 4010): `/account` as a head (no button, explanation), as a membership-less user (button, confirm, landing page); `/confidentialite` FR and EN; `mix run -e 'TeacherAssistant.Uploads.sweep_orphans() |> IO.inspect()'` against the dev uploads dir **with `older_than` set far in the past only if you want to see deletions** — otherwise just read the counts (never delete dev photos by accident; the dev DB and files are the user's).
- [ ] `MIX_TEST_PARTITION=a9 mix precommit` → exit 0; fast-forward merge into main; update memory `project-audit-2026-11-10` (A9 merged; the two cron times; the snapshot-keeps-old-name call) and add the retention facts to `reference-demo-school-seed` only if the seed changed.
