# P3 — Debounce the fiche de préparation autosave — Design

> Design spec. Written 2026-07-02. Small UI-polish increment on the v1.3 fiche editor
> ([`LessonPlanLive`](../../../lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex)).
> Deliverable = spec first; no code until the plan is approved.

## 0. Premise

The v1.3 lesson-plan editor autosaves the header and each déroulement step. Its design intent was
**autosave-on-blur**, but the shipped forms carry BOTH `phx-change="save_*"` and
`phx-blur="save_*"`. `phx-change` fires on every input event, so **every keystroke triggers a full
DB write**. For a mobile-first app used over intermittent connectivity (a core PRODUCT.md
principle), that is wasteful and can queue many round-trips while a teacher types a paragraph into a
textarea.

P3 (this increment) is scoped to exactly this one fix. Other polish candidates (over-budget duration
signal, header field grouping, print cartouche) were considered and **deferred** — not in scope.

## 1. Scope

**In scope:** debounce the autosave on the two forms in `lesson_plan_live.ex` so a field saves when
it loses focus (or its value is committed), not on every keystroke — matching the intended
autosave-on-blur behavior.

**Out of scope (YAGNI):** any handler/context change; over-budget duration coloring; header field
grouping; print-template changes; changes to any other page.

## 2. Change

File: `lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex` (template only).

- **Header form** (`#fiche-header-form`, currently `phx-change="save_header" phx-blur="save_header"`):
  add **`phx-debounce="blur"`** and **remove `phx-blur="save_header"`**. Keep
  `phx-change="save_header"` as the single save trigger.
- **Each step form** (currently `phx-change="save_step" phx-blur="save_step" phx-value-id={s.id}`):
  add **`phx-debounce="blur"`** and **remove `phx-blur="save_step"`**. Keep `phx-change="save_step"`
  and `phx-value-id`.

Rationale: `phx-debounce="blur"` on a form applies to all its inputs; the `phx-change` event for an
input then fires only when that input loses focus, giving one write per field edit instead of one
per keystroke. This is the "autosave-on-blur" the design specified. Date/number/select fields
likewise commit on blur, which is acceptable. Removing the separate `phx-blur` binding avoids a
redundant double-save on blur (both events would otherwise fire).

No `handle_event` clauses change: `save_header` and `save_step` already receive the full field map
on the `phx-change` event, so a blurred field's save still carries the other fields' current values
(no partial-wipe). No DOM ids change.

## 3. Testing

File: `test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`.

- The existing autosave tests currently trigger saves via `render_blur/2` — **three call sites**
  (one on `#fiche-header-form`, two on step-row forms). Because `phx-blur` is removed, switch all
  three to `render_change/2` (still bound to `save_header`/`save_step`; `render_change` bypasses
  client-side debounce and exercises the real handler). Assertions (persisted value, saved
  indicator, reordering, duration check) are unchanged.
- Add one assertion that both forms render `phx-debounce="blur"` (e.g. the header form element and a
  step-row form carry the attribute), so the debounce can't silently regress.

## 4. Definition of done

- No per-keystroke DB writes: the header and step forms save on blur (debounced), not on every input
  event.
- Autosave still persists a field on blur (verified by the updated `render_change` tests).
- Both forms carry `phx-debounce="blur"`; the separate `phx-blur="save_*"` bindings are gone.
- All existing DOM ids unchanged; `mix precommit` green (currently 148 tests, 0 failures).

## 5. Guardrails

Unchanged from prior phases: no new colors/fonts; stable DOM ids; bilingual copy already via
gettext (no new strings); every change behind LiveView test selectors — no test churn beyond the two
`render_blur`→`render_change` switches and the added debounce assertion.
