# P0 — Class-context switcher + component kit (design)

> Design spec. Written 2026-07-01. First build phase of the
> [authenticated UI design pass](2026-07-01-authenticated-ui-design-pass.md) (§1.1, §1.2, §1.4).
> Brand: apply the shipped **Tableau** identity — no rebrand.

## 1. Purpose

Give the authenticated shell a **current class** the teacher can switch between, so every per-class
page (Fiche, Coverage, Roster, Marks, Results) is reachable from the shell — closing the app's
biggest structural gap (today only Dashboard + Log are in the nav). Ship the shared component kit and
accessibility fixes alongside, since they touch the same shell/pages.

Two independent workstreams in one phase:
- **A — Class-context switcher** (stateful; the bulk of this design).
- **B — Component kit + a11y** (mechanical; no new app state).

## 2. Workstream A — Class-context switcher

### 2.1 State model
Extend `TeacherAssistant.Scope` with a `current_context` field (a
`TeacherAssistant.Academics.TeachingContext` or `nil`). Persist the selection as
`session["context_id"]`, mirroring the shipped `workspace_id` / `locale` session pattern
(`LiveUserAuth.session_context/1`, `assign_scope/2`).

Resolution happens during scope assembly (in `Accounts.Workspaces.scope_for/2` or a thin wrapper it
calls): given the resolved workspace + active academic year, look up `context_id` as an
**owner-scoped, active-year-scoped** `TeachingContext`. The selection is "most-recently-used" by
construction — it is simply the last id written to the session.

**Fallback order** when resolving the active class:
1. valid `session["context_id"]` (owned, in the active year) → use it;
2. else the teacher's first `TeachingContext` for the active year (alphabetical by subject) → use it;
3. else `nil` → shell shows "Set up a class".

An invalid / foreign / stale `context_id` is silently ignored (falls through to 2/3): no crash, no
IDOR, no leak of another workspace's class.

### 2.2 Selection route (controller → session → redirect)
LiveViews cannot write the session, so selection goes through a controller, mirroring the existing
`LocaleController` / workspace switcher convention (GET links, already used for `/locale/:locale`):

- Route: `GET /teacher/select-context/:id` with a `return_to` query param
  (`TeacherAssistantWeb.TeacherContextController.select/2`).
- Behavior: owner-validate `:id` against the current workspace + active year.
  - **Valid:** put `context_id` in the session; redirect **context-aware** — if `return_to` matches a
    per-class path (`/teacher/contexts/<uuid>/...`), rewrite the `<uuid>` segment to `:id` and
    redirect there; otherwise redirect to `return_to` unchanged.
  - **Invalid/foreign:** do not write the session; redirect to `/teacher/setup`.
- `return_to` is validated as a local path (must start with `/teacher`) to avoid open-redirect.

### 2.3 Shell rendering (`layouts.ex`)
The app header gains, below the existing top bar:

- **Class switcher** — a menu (daisyUI dropdown) labelled with the active class
  (`3e M2 · Maths ▾`); items are the teacher's active-year `TeachingContext`s, each an
  `<a href={~p"/teacher/select-context/#{ctx}?return_to=#{@current_path}"}>`. When there is no class,
  the control reads "Set up a class" and links to the setup gate.
- **Class-independent tabs** — Dashboard · Log · Import (always present).
- **Per-class tab row** — Fiche · Coverage · Roster · Marks · Results — rendered **only** when
  `current_context` is set; each links to that context's page.
- **Mobile bottom nav** — ≤5 items (Dashboard · Marks · Coverage · Log · More), safe-area-inset
  aware, with body bottom-padding reserved so content isn't hidden behind it.
- Active destination is highlighted; placement is identical on every page.

The shell needs the **current request path** to build `return_to` and to highlight the active tab.
Expose it via an `on_mount` assign (`@current_path`) using `handle_params`/`live_session` so
`Layouts.app` can read it.

### 2.4 Data flow
```
select-context link → TeacherContextController.select → session["context_id"]=id → redirect
   → next LiveView mount → LiveUserAuth.assign_scope → Workspaces.scope_for resolves current_context
   → Layouts.app renders switcher label + per-class tabs from scope.current_context
```

## 3. Workstream B — Component kit + accessibility

### 3.1 Components (in `core_components.ex`)
Per the design-pass spec Appendix A — no new state, pure presentation:
- `page_header` (eyebrow + h1 + optional `:actions` slot),
- `stat` (label + `ta-num` value + suffix + tone),
- `empty_state` (icon + title + message + `:action` slot),
- `setup_gate` (promotes the dashboard's icon-chip gate to a component).

Migrate each authenticated page's hand-rolled header/empty/gate markup onto these — behavior
unchanged, DOM IDs preserved so existing LiveView tests keep passing.

### 3.2 Accessibility (from §1.4)
- `aria-label={student.full_name}` on each mark score input; ensure ≥44px height.
- A shared mention helper renders **word + icon** (`hero-check-circle` ≥10 / `hero-x-circle` <10),
  never color alone; FR/EN labels per the design-pass spec Appendix B (below-10 = *Insuffisant*).
- `ta-num` on numeric columns so figures align.
- Verify craie (light) contrast on muted `text-base-content/55–65` labels.

## 4. Error handling

- Invalid/foreign/stale `context_id` in session → ignored; default applies. No crash, no IDOR.
- No active academic year → switcher hidden; shell routes to the setup gate.
- Active class deleted mid-session → next mount falls back to default (first class or none).
- `return_to` not a local `/teacher` path → treated as absent; redirect to the class's default page.

## 5. Testing

- **Scope resolution (unit, `Scope`/`Workspaces`):** valid id used; invalid/foreign/stale id →
  fallback; no-context → `nil`; first-class default when session empty.
- **Controller (`TeacherContextController`):** valid select writes session + redirects; per-class
  `return_to` has its context segment rewritten; class-independent `return_to` preserved; foreign id
  rejected (no session write, redirect to setup); non-local `return_to` ignored.
- **Shell (LiveView):** switcher lists only owned/active-year contexts; active class label shown;
  per-class tabs appear only when a context is active; class-independent tabs always present;
  "Set up a class" when none.
- **Component kit:** render test per component (header/stat/empty_state/setup_gate) asserting slots
  and DOM.
- **Regression:** existing page tests still pass after migrating onto the kit (DOM IDs preserved).

## 6. Non-goals (this phase)

- No redesign of the per-class page bodies (that's P1: roster / marks / summary tables).
- No multi-workspace/school nav (Phase 2).
- No new persistence table — selection lives in the session only.
- No change to the mark/coverage calculations.

## 7. Quality bar (inherits app-wide)

Workspace- and owner-scoped (no IDOR through `context_id`); no route crash on missing/invalid class —
guide to setup; both themes and both languages verified at mobile widths; stable DOM IDs; deterministic
behavior; `mix precommit` green.
