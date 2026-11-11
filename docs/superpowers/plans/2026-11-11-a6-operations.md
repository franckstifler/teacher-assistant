# A6 — Operations: impersonation attribution, error mail, CSP, cookie — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every write made while an operator impersonates a member names the operator next to the member; the operator error e-mail carries no error text; every page is served under a Content-Security-Policy that blocks foreign scripts; the session cookie is encrypted; the LiveDashboard request logger is out of prod.

**Architecture:** `Scope`'s `Ash.Scope.ToOpts` passes `operator_user_id` in the shared context, so one `StampOperator` change (with `atomic/3`) copies it into an `…operator_user_id` column beside each actor column; the two writers that carry no scope (`Mark.Journal`, `AuditEvent.Record`) pass it in their attrs. The marks journal and the sanction detail render « (opérateur X) ». A `Plug.ContentSecurityPolicy` in the `:browser` pipeline sets the policy with a per-request nonce assign that only the ErrorTracker dashboard uses; the print pages' inline `onclick` / `onchange` handlers move to a second esbuild entry `print.js`. `encryption_salt` on the session; `RequestLogger` behind `:dev_routes`.

**Tech Stack:** Elixir, Ash 3.37 (`Ash.Resource.Change` with `atomic/3`, `Ash.Scope.ToOpts`), Phoenix 1.8 (`put_secure_browser_headers/2`), esbuild multi-entry, ErrorTracker `csp_nonce_assign_key`, Swoosh test assertions.

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A6.

## Global Constraints

- `operator_user_id` columns are plain nullable `:uuid` attributes, no FK, no relationship (the operator is a global user outside the tenant).
- Spec list of actor columns, one operator column each: `MarkEvent.actor_user_id` → `operator_user_id`; `Payment.recorded_by_user_id` → `operator_user_id`, `Payment.cancelled_by_user_id` → `cancelled_operator_user_id`; `SanctionEntry.issued_by_user_id` → `operator_user_id`, `parents_notified_by_user_id` → `parents_notified_operator_user_id`; `AttendanceEntry.recorded_by_user_id` → `operator_user_id`; `AuditEvent.actor_user_id` → `operator_user_id`. The other actor columns found (typed absences, conduct marks, fee papers, publications, councils…) are out of scope for this increment: list them in the ledger as a candidate.
- The CSP keeps Phoenix's defaults `base-uri 'self'; frame-ancestors 'self'` (the bulletin page iframes its print; `bulletin_print_controller_test.exs:966-980`). Policy: `default-src 'self'; base-uri 'self'; frame-ancestors 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; script-src 'self' 'nonce-<n>'; connect-src 'self' wss: ws:; font-src 'self'; object-src 'none'`. The nonce exists for `/admin/errors` (ErrorTracker inlines its script) and the dev LiveDashboard; app pages never use it (builder's call against the spec's « no nonce »: the alternative is a second pipeline for the dashboard; the nonce is one plug and no duplicated policy). In dev, `script-src` also allows `http://127.0.0.1:4007` for live_debugger through a config key.
- No inline `<script>` and no inline event handler anywhere after Task 3 (`grep -rn "onclick=\|onchange=" lib/` empty).
- Never write a migration by hand: `mix ash.codegen --dev operator_attribution`, read, `mix ash.migrate` on dev.
- Branch `feat/audit-a6` in `.claude/worktrees/audit-a6`, `MIX_TEST_PARTITION=a6`; explicit paths; Gettext extract + EN, no fuzzy; `mix precommit` green before merge.

## Review Focus

1. A roll call re-taken by the member themself after an operator took it: the upsert rewrites `operator_user_id` to nil (it is in `upsert_fields`), so the last writer is right — Task 1 tests the overwrite in both directions.
2. A mark approved through a correction (`MarkCorrection.Decide`, scope passed as context) while impersonated: the MarkEvent carries the operator — Task 1 tests it.
3. The 20 print pages: « Imprimer » and the period `<select>` still work with no inline handler — Task 3 tests that each print template carries `data-print` / `data-submit-on-change` and the script tag, and Task 5 clicks two of them in the browser with the console clean.
4. The ErrorTracker dashboard under the policy: renders without console errors (nonce threaded) — Task 3 tests the header on `/admin/errors` and Task 5 opens it.
5. Existing sessions after the salt lands: every member is signed out once; the remember-me cookie is separate and signs them back in on the next visit — Task 4 documents it in `docs/DEPLOY.md` and the memory; no code test.

---

### Task 1: Operator attribution on writes

**Files:**
- Modify: `lib/teacher_assistant/scope.ex:48-55` (`get_context/1`)
- Create: `lib/teacher_assistant/academics/stamp_operator.ex` (`TeacherAssistant.Academics.StampOperator`)
- Modify: `lib/teacher_assistant/academics/mark_event.ex` (attribute; `:record` accept :38-51), `lib/teacher_assistant/academics/mark/journal.ex:13-45` (`operator_user_id: context.source_context[:operator_user_id]` in attrs), `lib/teacher_assistant/academics/mark_correction/request.ex:19-29` and `decide.ex:84-94` (same), `lib/teacher_assistant/academics/payment.ex` (two attributes; `change StampOperator` on create with `attribute: :operator_user_id`, on `:cancel` with `:cancelled_operator_user_id`), `lib/teacher_assistant/academics/sanction_entry.ex` (two attributes; create and `:mark_parents_notified`), `lib/teacher_assistant/academics/attendance_entry.ex` (attribute; `:record`, `:record_paper`, default `:update`, `create_group_entries` upsert_fields :491-498), `lib/teacher_assistant/attendance.ex:455-461` (upsert_fields), `lib/teacher_assistant/accounts/audit_event.ex` (attribute, accept), `lib/teacher_assistant/accounts/audit_event/record.ex:13-32` (pass from `context.source_context`), `lib/teacher_assistant/operator.ex:246-257` (nil)
- Modify: `lib/teacher_assistant/accounts.ex` (`user_name(id) :: String | nil` — move `Fees.user_name/1` :804-811 here; `Fees` delegates), `lib/teacher_assistant_web/live/school/correction_review_live.ex:216-257` (`author/2` → « %{member} (opérateur %{operator}) »), `lib/teacher_assistant_web/live/school/sanctions_live.ex:384-385` (same suffix), `lib/teacher_assistant_web/impersonation.ex:11-12` moduledoc, `lib/teacher_assistant_web/controllers/page_html.ex:367` (privacy wording: the school sees that an operator acted)
- Create (generated): migration + snapshots
- Test: `test/teacher_assistant/operator_attribution_test.exs` (new), `test/teacher_assistant_web/live/school/correction_review_live_test.exs`

**Interfaces:**
- `Scope` `get_context(%{locale: l, impersonation: imp})` → `{:ok, %{shared: %{locale: l, operator_user_id: imp && imp.operator.id}}}` (`imp` nil → nil).
- `StampOperator` — `use Ash.Resource.Change`; `init/1` requires `attribute:`; `change/3`: `Ash.Changeset.force_change_attribute(cs, attr, cs.context[:operator_user_id])` (shared keys are merged at the top level of `changeset.context`); `atomic/3`: `{:atomic, %{attr => cs.context[:operator_user_id]}}`; `batch_callbacks?/3` false (cheap per row). Attached with `change {StampOperator, attribute: :operator_user_id}, on: [...]` next to the `YearOpen` lines.
- Test scope helper: `impersonating(scope, operator) = %{scope | impersonation: %{operator: operator, ends_at: DateTime.add(DateTime.utc_now(), 3600)}}` in `test/support/data_case.ex`.
- Rendering: `Accounts.user_name/1` resolves any user (`Ash.get(User, id, authorize?: false)`); `author/2` returns « Système », the member name, or « <member> (opérateur <name>) » (`gettext("%{member} (opérateur %{operator})")`).

- [ ] **Step 1: Write the failing tests**

```elixir
# operator_attribution_test.exs — setup_complete_school_fixture + MarksFixtures/FeesFixtures as needed; op = admin_user_fixture()
test "a mark written while impersonated journals the operator; the member's own write does not"  # MarkEvent.operator_user_id == op.id, then nil
test "a correction approved while impersonated journals the operator"                           # MarkCorrection flow (see mark_correction tests for the helpers)
test "a payment and its cancellation carry their operator columns"                              # Fees.record_payment / cancel_payment with impersonating scope
test "a sanction and its parents-notified stamp carry the operator"
test "a roll call taken while impersonated carries the operator; retaken by the member it is cleared"  # Attendance.record_period twice; combined period too
test "an audit event written during impersonation (member renamed) carries the operator"
test "a plain scope writes nil everywhere"
# correction_review_live_test: the journal line reads "<member> (opérateur <op name>)"
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=a6 mix test test/teacher_assistant/operator_attribution_test.exs` — FAIL (unknown attribute).
- [ ] **Step 3: Implement**; `mix ash.codegen --dev operator_attribution`; rendering; docs wording; Gettext extract + EN.
- [ ] **Step 4: Run** the two files + `test/teacher_assistant/academics/` + `test/teacher_assistant/fees*` + `test/teacher_assistant_web/controllers/impersonation_controller_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(ops): writes made while impersonating carry the operator`.

---

### Task 2: Operator error e-mail without the reason

**Files:**
- Modify: `lib/teacher_assistant/accounts/emails.ex:44-79` (`error_alert/4`)
- Test: `test/teacher_assistant/error_reporting_test.exs:114-129`, `test/teacher_assistant/accounts/emails_test.exs`

**Interfaces:**
- Body (text and HTML): kind (`short_kind/1`), « À <source> », « Le <short_datetime(error.last_occurrence_at)> » (`TeacherAssistantWeb.Dates.short_datetime/1`), « Voir l'erreur : <url> ». No `reason`. Subject unchanged.

- [ ] **Step 1: Write the failing tests** — `error_reporting_test:124`: `refute email.text_body =~ "mail me"`; `assert email.text_body =~ "Voir l'erreur"`; `emails_test`: `error_alert/4` HTML body contains the kind, the source, a time and the link, not the reason (build an `%ErrorTracker.Error{}` struct literal).
- [ ] **Step 2: Run** — FAIL (reason present).
- [ ] **Step 3: Implement**; Gettext extract + EN.
- [ ] **Step 4: Run** both files — PASS.
- [ ] **Step 5: Commit** `fix(ops): the error e-mail names the kind, place and time, never the message`.

---

### Task 3: Content-Security-Policy

**Files:**
- Create: `lib/teacher_assistant_web/plug/content_security_policy.ex` (`TeacherAssistantWeb.Plug.ContentSecurityPolicy`)
- Modify: `lib/teacher_assistant_web/router.ex:14` (replace `plug :put_secure_browser_headers` with `plug Plug.ContentSecurityPolicy`, which calls `put_secure_browser_headers(conn, %{"content-security-policy" => policy})`), `:270-276` (`error_tracker_dashboard …, csp_nonce_assign_key: :csp_nonce`), `:279-288` (`live_dashboard …, csp_nonce_assign_key: :csp_nonce`)
- Modify: `config/config.exs` (esbuild args gain `js/print.js` as a second entry; `config :teacher_assistant, :csp_extra_script_src, []`), `config/dev.exs` (`csp_extra_script_src: ["http://127.0.0.1:4007"]`)
- Create: `assets/js/print.js` (binds `[data-print]` → `window.print()`, `[data-submit-on-change]` → `this.form.submit()`, on `DOMContentLoaded`)
- Modify: `lib/teacher_assistant_web/components/print_components.ex:47` (`print_bar/1`: `data-print` and a `<script defer src={~p"/assets/js/print.js"}>` emitted once by `setup/1`, the component every print page already calls — check `print_components.ex:26`), `controllers/fee_paper_print_html/{note,control,warnings}.html.heex`, `mark_sheet_print_html/show.html.heex:42,45`, `card_print_html/show.html.heex:85`, `receipt_print_html/show.html.heex:97`
- Test: `test/teacher_assistant_web/csp_test.exs` (new), `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs:966-980`

**Interfaces:**
- The plug: `nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)`; `assign(conn, :csp_nonce, nonce)`; policy string as in Global Constraints with `script-src 'self' 'nonce-#{nonce}' #{extra}`; `extra` from `Application.get_env(:teacher_assistant, :csp_extra_script_src, [])`.
- `print.js` is served digested like app.js (`phx-track-static`); the print pages reference it with `~p"/assets/js/print.js"`.

- [ ] **Step 1: Write the failing tests**

```elixir
# csp_test.exs (ConnCase)
test "/school carries the policy with self scripts and no unsafe-inline for scripts"   # header =~ "script-src 'self' 'nonce-"; =~ "frame-ancestors 'self'"; refute =~ "script-src 'self' 'unsafe-inline'"
test "the landing page and the sign-in page carry it too"
test "/admin/errors renders for an operator under the policy with the nonce on its script tag"   # admin_user_fixture; html =~ ~s(nonce=")
test "no template carries an inline handler"   # Path.wildcard("lib/**/*.{ex,heex}") |> Enum.reject(=~ ~r/onclick=|onchange=/) — a static guard, acceptable as a test
test "every print page references print.js and no inline handler"  # the 20 routes from router.ex:110-132 with the usual fixtures, or the 6 templates listed above read as files
```

- [ ] **Step 2: Run** — FAIL (default policy, inline handlers present).
- [ ] **Step 3: Implement** plug, router, esbuild entry (`mix assets.build`), `print.js`, templates.
- [ ] **Step 4: Run** `csp_test.exs` + `test/teacher_assistant_web/controllers/` — PASS.
- [ ] **Step 5: Commit** `feat(security): content-security-policy on every page; print pages without inline handlers`.

---

### Task 4: Encrypted session cookie, no RequestLogger in prod

**Files:**
- Modify: `lib/teacher_assistant_web/endpoint.ex:7-13` (`encryption_salt: "<8+ random chars>"`), `:49-51` (`if Application.compile_env(:teacher_assistant, :dev_routes) do plug Phoenix.LiveDashboard.RequestLogger … end`)
- Modify: `docs/DEPLOY.md` (release note: first deploy after A6 signs every member out once; remember-me brings them back)
- Test: `test/teacher_assistant_web/endpoint_test.exs` (new or from A8 if it exists — A6 and A8 both touch the endpoint; merge order decides who creates it)

**Interfaces:**
- `TeacherAssistantWeb.Endpoint` session options include `encryption_salt`; the LiveView socket reuses `@session_options` so it follows.

- [ ] **Step 1: Write the failing tests** — `endpoint_test.exs`: the session options of `Plug.Session` in the endpoint include `:encryption_salt` (read `TeacherAssistantWeb.Endpoint.__info__(:attributes)` is not available for module attributes; instead `Plug.Session` config is visible through a request: `get(conn, "/")` then the `_teacher_assistant_key` cookie value is not a readable signed payload — simplest: assert `TeacherAssistantWeb.Endpoint.session_options()[:encryption_salt]` after exposing `def session_options, do: @session_options`); and in `test` env (`dev_routes` false) `TeacherAssistantWeb.Endpoint.__info__(:functions)` is not enough — test that a request to `/` with `?request_logger=…` sets no `request_logger` cookie.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**; `docs/DEPLOY.md` note.
- [ ] **Step 4: Run** the file + `test/teacher_assistant_web/prod_config_test.exs` — PASS; a full `MIX_TEST_PARTITION=a6 mix test` (session fixtures still sign in).
- [ ] **Step 5: Commit** `chore(security): encrypted session cookie; request logger only with dev routes`.

---

### Task 5: Verify and merge

- [ ] Browser check (worktree server on 4010): sign in as proviseur (the new cookie), open `/school`, a marks grid, a bulletin print with « Imprimer » and the mark-sheet print's period select, a receipt print, `/admin/errors` as an operator, a student photo page, the photo studio upload (blob/camera) — console clean of CSP violations on each (`read_console_messages`). Impersonate the proviseur as operator, enter a mark, open the correction journal: « (opérateur …) » shown.
- [ ] `MIX_TEST_PARTITION=a6 mix precommit` → exit 0 (refresh Gettext references if needed); fast-forward merge into main; `mix ash.migrate` on the dev DB from main; update memory `project-audit-2026-11-10` (A6 merged; the nonce call; the out-of-scope actor columns candidate; the one-time sign-out at deploy).
