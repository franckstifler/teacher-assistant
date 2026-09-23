# School onboarding setup wizard (blocking)

**Status:** Design / spec — awaiting user review
**Date:** 2026-09-22
**Branch:** `feat/onboarding-setup-wizard`
**Follows:** the `Onboarding` mockup (claude.ai design project), rendered in the app's real "Tableau" chalkboard tokens.

## Overview

Today a new school head creates the school (identity only) and is dropped on the
dashboard, which merely *nudges* them (a checklist + setup gates) toward creating
an academic year, classes, and inviting staff. The `Onboarding` mockup is a
stepped wizard; only step 1 (identity) was ever built.

This increment builds the multi-step wizard as a **blocking gate**: a new head
must set up an **academic year** and at least **one class** before the rest of the
school app opens. Inviting staff is offered as the final step but is **optional**.
All four step-actions already exist (`create_school`, `create_academic_year`,
`create_class_group` + `Seeding`, `invite_member`) — this is an orchestration +
UX layer that reuses them, with **no new schema or persisted onboarding state**
(progress is derived from data, exactly as the dashboard checklist already does).

## Goals / non-goals

**Goals**
- A brand-new head is walked through: Identity (done) → Academic year → Classes →
  Invite team, in the mockup's stepped layout, in Tableau tokens.
- The school app is **blocked** (every school screen redirects into the wizard)
  until the school has an **active academic year AND ≥1 class**. No redirect loop.
- Each step reuses the existing action; progress is derived from existing data
  signals — no `onboarding_step`/`completed` field anywhere.
- Once the gate opens, the dashboard, settings, members, etc. behave exactly as
  today; the wizard is no longer forced (its invite step is reachable but optional).

**Non-goals**
- No change to what `create_school` / `create_academic_year` / `create_class_group`
  / `invite_member` do — the wizard calls them unchanged.
- No verification changes; the wizard runs pre-verification (setup never required
  verification, and still doesn't).
- No authorization/policy rework (roadmap C). Setup actions stay head/admin-gated
  via the existing `Permissions` checks.
- No new persisted onboarding state.

## Global constraints

- Forms use `AshPhoenix.Form` with build-time `prepare_source` for server-controlled
  fields (`workspace_id`, `academic_year_id`, `active`) — never param-merging.
- Enums via `Ash.Type.Enum`. Gettext FR-default; all copy translatable.
- Setup actions remain head/admin-gated (`Permissions.head?/1` / `admin?/1`), unchanged.
- `mix precommit` does NOT gate on warnings — verify with `mix test`.
- Rendered in existing "Tableau" tokens (`.ta-board`/`.ta-leaf`/`.ta-field`/
  `.ta-eyebrow`/`.ta-num`); no theme-color changes.

## The blocking gate

A new `on_mount` hook **`:require_school_setup`** added to the `:school_workspace`
live_session, running **after** the scope-assigning hook (so `current_scope` is
available):

```
def on_mount(:require_school_setup, _params, _session, socket) do
  scope = socket.assigns.current_scope
  cond do
    scope.current_workspace_type != :school -> {:cont, socket}   # personal/teacher unaffected
    socket.view == TeacherAssistantWeb.Onboarding.SetupWizardLive -> {:cont, socket} # exempt (no loop)
    setup_complete?(scope) -> {:cont, socket}
    true -> {:halt, push_navigate(socket, to: ~p"/school/setup")}
  end
end
```

- `setup_complete?(scope)` = `scope.current_academic_year != nil` AND
  `Enrollment.list_class_groups(ws, year) != []`. Add as `Scope.setup_complete?/1`
  (mirrors the existing `academic_year_ready?/1`).
- The gate applies to **school** scope only; personal/teacher scope is untouched.
- The wizard view is exempt by identity check, preventing a redirect loop.
- **Entry:** after `create_school`, `WorkspaceController.select` lands on `/school`;
  the gate immediately bounces an incomplete school to `/school/setup`. So a new
  head arrives in the wizard with no change to the create/redirect flow. (Optional:
  land fresh schools on `/school/setup` directly; not required — the gate is the
  single source of truth.)

## The wizard LiveView

**`TeacherAssistantWeb.Onboarding.SetupWizardLive`** at `live "/school/setup"`,
inside the `:school_workspace` session (scope auto-assigned; gate-exempt). Renders
inside `Layouts.app`. A 4-step progress header (Identity ✓ · Academic year ·
Classes · Invite team) matching the mockup.

`@step` assign, initialized to the first incomplete required step (derived from
data), advanced by events; "Continue" is disabled until the step's requirement is met:

1. **Identity** — shown as complete (the school exists). A recap card of the
   profile (name, type, subsystem, region). Profile *editing* is NOT linked from
   here — `/school/settings` is gated during onboarding and would loop back to the
   wizard. Any profile field the wizard wants to capture (e.g. `head_name`, the
   dashboard "Profile" signal) is edited **inline in this step**, not by navigating
   out. `head_name` is NOT part of the gate; full profile editing lives in Settings
   after setup completes.
2. **Academic year** *(required)* — a form (name, start_date, end_date) bound to
   `AcademicYear.:create_for_workspace` via `AshPhoenix.Form`, `workspace_id`/`active`
   set by `prepare_source` (first year auto-active). On submit →
   `Organization.create_academic_year/2`. Creating the year **auto-seeds starter
   classes** (`Seeding.seed_starter_classes`), so the wizard advances to Classes
   with rows usually already present.
3. **Classes** *(required: ≥1)* — lists `Enrollment.list_class_groups(ws, year)`;
   an inline add form (reuse the `ClassGroup.:create` shape: label, level, série,
   `workspace_id`/`academic_year_id` via `prepare_source`) and delete
   (`Enrollment.delete_class_group/1`, which refuses `:has_data`). "Continue" is
   enabled only when ≥1 class exists (covers school types whose template seeds none).
4. **Invite team** *(optional)* — embeds the increment-B invite form
   (`SchoolInvitation.:create` → `Accounts.invite_member(ws, head, %{email, roles,
   membership_status})`), with "Invite another" and a pending list. A **"Finish
   setup"** (and a "Skip for now") button redirects to `/school`. By now year + ≥1
   class exist, so the gate is open and the dashboard loads.

**Step derivation:** on mount, `@step` = `:year` if no year, else `:classes` if no
class, else `:invite`. This makes the wizard resilient to refresh/re-entry (a head
who created the year but not classes returns to the Classes step). Forward "Continue"
buttons move `@step`; the gate guarantees they cannot escape to the dashboard early.

## Dashboard cleanup (small)

With the hard gate, the dashboard's own `year == nil` / `classes == []`
`<.setup_gate>` branches become **unreachable** (those states now redirect to the
wizard). Simplify: keep the completed-state checklist (Profile / Year / Classes /
Staff) as an at-a-glance + links for later edits, and remove the now-dead blocking
`setup_gate` branches. (Low-risk tidy; the checklist stays.)

## Design fidelity

Pull `Onboarding.dc.html` from the design project at build time and match its
stepped layout (progress header, per-step panel, primary/secondary actions) in
Tableau tokens. Logged-in app = real chalkboard tokens (per the prior design-import
decision), not the paper palette.

## Testing

- **Gate:** an incomplete school head hitting `/school` (and another school route,
  e.g. `/school/members`) is redirected to `/school/setup`; the wizard route itself
  is NOT redirected; once an active year + ≥1 class exist, `/school` loads normally.
  A personal/teacher scope is never redirected by the gate.
- **Wizard year step:** submitting valid year data creates the year, auto-seeds
  classes, and advances to Classes.
- **Wizard classes step:** "Continue" is blocked with 0 classes and enabled with
  ≥1; add/delete work; deleting the last class re-blocks Continue.
- **Wizard invite step:** inviting reuses `invite_member` (email delivered — assert
  via Swoosh Test adapter), "Finish" lands on `/school` and the dashboard now loads.
- **Head-gating:** a non-head member cannot perform the wizard's mutating actions
  (existing `Permissions` checks).
- Fixtures: reuse `school_fixture/1`; add a helper to create a year (+seeded
  classes) where a test needs a "setup-complete" school.

## Files (map)

**Create**
- `lib/teacher_assistant_web/live/onboarding/setup_wizard_live.ex`
- `test/teacher_assistant_web/live/onboarding/setup_wizard_live_test.exs`
- `test/teacher_assistant_web/live/onboarding/setup_gate_test.exs` (the redirect gate)

**Modify**
- `lib/teacher_assistant_web/live_user_auth.ex` — add `on_mount(:require_school_setup, …)`.
- `lib/teacher_assistant_web/router.ex` — add `/school/setup` route; wire
  `:require_school_setup` into the `:school_workspace` live_session's on_mount chain
  (after scope assignment).
- `lib/teacher_assistant/scope.ex` — add `setup_complete?/1`.
- `lib/teacher_assistant_web/live/school/dashboard_live.ex` — remove the now-unreachable
  `year == nil` / `classes == []` blocking `setup_gate` branches (keep the checklist).

## Rollout / risk
- No migration, no schema change. Pure LiveView + routing + a scope helper.
- The gate is the one behavior change with reach: it must run only for school scope,
  exempt the wizard view, and open exactly on (active year + ≥1 class). The gate
  and wizard tests pin all three.
- Reversible: removing the on_mount entry restores today's non-blocking behavior.
