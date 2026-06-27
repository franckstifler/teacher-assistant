# Final Review Fixes Report

## Fix 1 — Privacy/IDOR: workspace-scope plan & entry access

**What changed:**

- Added `Academics.fetch_owned_plan(id, %PersonalWorkspace{})` in `academics.ex`: filters by `id AND personal_workspace_id == ws.id`, returns `{:ok, plan} | {:error, :not_found}`.
- Added `Academics.fetch_owned_entry(id, %PersonalWorkspace{})`: looks up entry then verifies the plan belongs to the workspace via `fetch_owned_plan`.
- `FicheLive.mount/3`: replaced unscoped `get_progression_plan/1` with `fetch_owned_plan/2`; on `{:error, :not_found}` pushes navigate to `/teacher` with error flash (gettext "Plan not found").
- `FicheLive.handle_event("delete-entry")`: replaced unscoped `get_progression_entry/1` with `fetch_owned_entry/2`; unauthorized attempts return error flash without mutating.
- `CoverageLive.mount/3`: replaced unscoped `get_progression_plan/1` with `fetch_owned_plan/2`; same redirect on failure.
- `LogLive.handle_event("save")`: verifies `progression_entry_id` belongs to the current workspace via `fetch_owned_entry/2` before writing the log; forged IDs now return error flash.

**New IDOR tests:**

- `FicheLiveTest` — "redirects to /teacher when accessing another user's plan (IDOR)": creates a second user+workspace+plan and asserts `{:error, {:live_redirect, %{to: "/teacher"}}}` when first user's conn visits the plan.
- `CoverageLiveTest` — "redirects to /teacher when accessing another user's coverage (IDOR)": same pattern for the coverage route.

## Fix 2 — Bilingual DoD: populate the FR gettext catalog

**What changed:**

1. Ran `mix gettext.extract` (Dev env) → generated `priv/gettext/default.pot` with 65 msgids.
2. Ran `mix gettext.merge priv/gettext` → updated `priv/gettext/fr/LC_MESSAGES/default.po` (62 new, 1 unchanged, 2 fuzzy resolved) and created `en/LC_MESSAGES/default.po` (empty msgstr, which is correct for EN).
3. Filled in **65 French msgstr values** in `priv/gettext/fr/LC_MESSAGES/default.po`, covering: all LiveView headings, buttons, labels, flash messages, empty states, and layout strings (nav items, workspace labels, error banners). Used Cameroon-French education terminology ("fiche de progression", "leçon", "module", "séquence", "matière", "classe", "sous-système").
4. Key translations: "Teacher dashboard"→"Tableau de bord" (preserved), "Add entry"→"Ajouter une entrée", "Coverage"→"Couverture", "Not yet covered"→"Pas encore couvert", "Finish"→"Terminer", "Start setup"→"Commencer la configuration", "Log"→"Journal", "Save"→"Enregistrer", "Dashboard"→"Tableau de bord", "Lesson"→"Leçon", "Module"→"Module", "Plan not found"→"Fiche introuvable".

The existing `locale_test.exs` still passes: FR "Tableau de bord" and EN "Teacher dashboard" both assert correctly.

## Fix 3 — Coverage "uncovered" list is now hours-based

**What changed:**

- `Coverage.summarize/2` in `coverage.ex`: added `entry_id: e.id` to each `per_entry` map, and exposed `per_entry: per_entry` in the returned summary map.
- `CoverageLive.mount/3`: replaced the log-presence check (`logged_ids` MapSet) with an hours-based check using `coverage.per_entry`. An entry is considered "covered" only when `covered >= planned`; all others appear in the uncovered list.
- The existing test scenario (e1: 2h planned, 2h logged → covered; e2: 2h planned, 0h logged → uncovered) still yields 50% and one uncovered entry — test passes unchanged.
- A partially-logged entry (e.g. 1h logged against 2h planned) now correctly remains in the uncovered list while contributing partially to the rate.

## Precommit Summary

```
mix precommit (compile --warning-as-errors, deps.unlock --unused, format, test)
35 tests, 0 failures
```

- 2 tests added (IDOR/ownership for FicheLive and CoverageLive)
- Total: 35 tests (was 33)

## FR Translation Count

65 msgstr values translated across `priv/gettext/fr/LC_MESSAGES/default.po`.
