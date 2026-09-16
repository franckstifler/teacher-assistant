# Progression — hour quotas & count targets (P-C)

**Status:** Approved design
**Date:** 2026-08-12
**Builds on:** P-B (first-class `ProgressionModule` with per-module computed hours; grouped `FicheLive` with inline module rename + `fetch_owned_module/2`; `Coverage` planned-vs-covered by sequence). Also on the existing `TeachingContext` (`weekly_hours`, `coefficient`), `SetupLive` (context creation), and the owner-scoped `fetch_owned_teaching_context/2` / `fetch_owned_plan/2` helpers.

## Purpose

Let a teacher capture the official **targets** for a subject×class — the annual hour volume, the number of chapters/modules, and the number of lessons, plus a per-module hour credit — and see, at a glance on the fiche de progression, how their **planned** work measures against those targets. This makes the fiche's cartouche (*"Nombre de chapitres (leçons)..12(21).. Horaire annuel 50h"*) a live, trackable thing instead of a static header, and completes the hour-credit that P-B deliberately left as a computed sum only.

Targets are **advisory** — the app shows gaps, it never blocks. This matches the domain KB's "support the APC structure without forcing it; meet teachers where they are."

## Scope

In scope:
- `TeachingContext` gains three nullable targets: `annual_hours`, `target_module_count`, `target_lesson_count`.
- `ProgressionModule` gains a nullable `credit_hours` (the module's CRÉDIT).
- A pure `Quota` module computing planned-vs-target gaps at the context level and per module (nil-safe: an unset target yields no bar).
- `FicheLive`: a quota header (planned h vs annual, modules vs target, lessons vs target) with an inline edit affordance for the three context targets; each module card shows planned-vs-credit and edits `credit_hours` inline.
- `SetupLive`: the three context targets are (optionally) enterable at context creation.
- A new owner-scoped `update_teaching_context/2` domain function.

Out of scope (YAGNI / deferred):
- **No enforcement** — never block adding entries/modules past a target; no gating.
- No cross-level reconciliation bar (e.g. "Σ module credits vs annual_hours") — the two levels are shown independently. A later increment can add it.
- No dashboard surfacing — quota bars live on the fiche only for now (the dashboard already has coverage KPIs; wiring quotas there is a follow-up).
- No change to `Coverage` (planned-vs-*covered* is a different axis, tracked by sequence — P-D territory).
- No auto-derivation of `annual_hours` from `weekly_hours × weeks` — it is the authoritative official programme figure, entered manually (a create-time default may pre-fill, see §4).

## 1. Data model

### `TeachingContext` (add)
| Attribute | Type | Notes |
|---|---|---|
| `annual_hours` | `:decimal` | nullable; official volume horaire annuel (e.g. 50, 75, 100) |
| `target_module_count` | `:integer` | nullable; number of named chapters/modules expected |
| `target_lesson_count` | `:integer` | nullable; number of lessons expected (the "(21)") |

Add all three to the `create` and `update` accept lists. A new update action is not needed on the resource beyond the default `:update` (already present) — the domain function wraps it.

### `ProgressionModule` (add)
| Attribute | Type | Notes |
|---|---|---|
| `credit_hours` | `:decimal` | nullable; the module's CRÉDIT (target hours) |

Add `:credit_hours` to the resource's `update` accept list (and `create` for completeness).

## 2. Pure computation — `TeacherAssistant.Academics.Quota`

Mirrors `Coverage`'s shape (pure, no Repo). Signature:

```
Quota.summarize(ctx, modules) :: %{
  planned_hours: Decimal,           # Σ of every entry's planned_hours across modules
  annual_hours: Decimal | nil,
  hours_ratio: float | nil,         # planned/annual, nil if annual unset or 0
  module_count: integer,            # modules excluding the default? bucket
  target_module_count: integer | nil,
  lesson_count: integer,            # entries with entry_type == :lesson, across modules
  target_lesson_count: integer | nil,
  per_module: [%{module_id, planned: Decimal, credit: Decimal | nil, ratio: float | nil}]
}
```

- `modules` is the loaded list from `list_progression_modules/1` (each with ordered `entries`).
- `module_count` **excludes** the `default? == true` bucket (the cartouche counts named chapters).
- `lesson_count` counts only `entry_type == :lesson` entries (evaluations, integration, revision, correction, remediation, holiday are excluded), matching the fiche's "(21)".
- Every ratio is `nil` when its target is unset or zero — the UI hides that bar.
- Pure and unit-testable with plain structs/maps.

## 3. UI

### `FicheLive` — quota header
Above the module cards, a compact header shows three read-outs, each rendered as a labelled value + a thin progress bar when its target is set (hidden when nil):
- **Heures** — `planned_hours` / `annual_hours` h
- **Modules** — `module_count` / `target_module_count`
- **Leçons** — `lesson_count` / `target_lesson_count`

A subtle accent marks over/under target (reuse the dashboard's behind-schedule accent vocabulary). An edit affordance (small "pencil"/"Cibles" button) reveals a form to set `annual_hours`, `target_module_count`, `target_lesson_count`, submitting to a `save-targets` handler → `update_teaching_context/2` (owner-scoped via `fetch_owned_teaching_context/2`), then re-assign.

### `FicheLive` — per-module card
Each card header, next to the existing computed hours sum, shows `planned h / credit h` with a thin bar when `credit_hours` is set. An inline `credit_hours` editor (same pattern as the P-B inline rename: a small form `id={"module-credit-form-#{m.id}"}`, hidden `module_id`, number input) submits to a `save-module-credit` handler → `rename_module`-style owner-scoped update of the module.

### `SetupLive` — context creation
The context form gains three optional number inputs (`annual_hours`, `target_module_count`, `target_lesson_count`), passed through the existing `save` handler into `create_teaching_context/3`. Blank → nil.

## 4. Domain API (`Academics`)

- **`update_teaching_context(ctx_or_id, ws, attrs)`** → owner-scoped (`fetch_owned_teaching_context/2`), accepts `annual_hours` / `target_module_count` / `target_lesson_count` (and leaves the existing editable fields intact); returns `{:ok, ctx}` / `{:error, _}`.
- **Module credit update** — reuse a small owner-scoped update on `ProgressionModule` (mirror `rename_module/2`; either extend it or add `update_module_credit/2`) accepting `credit_hours`.
- `create_teaching_context/3` already forwards accepted attrs; the three new fields ride along once added to the accept list.
- **Pre-fill (optional, §Scope):** `SetupLive`'s form may default `annual_hours` blank (no derivation) — no domain change needed.

## 5. Behavior & edge cases

- **Advisory only** — no code path blocks adding/removing entries or modules based on a target.
- **Nil targets** hide their bar/ratio everywhere; a fiche with no targets set looks exactly like today plus the raw counts.
- **Default bucket** excluded from `module_count`; its lessons still count toward `lesson_count` if they are `:lesson` type.
- Hours are `Decimal`; sum with `Decimal.add/2`; ratios computed as floats guarded against division by zero.

## 6. Testing

- **`Quota` pure:** planned/annual ratio; module_count excludes default bucket; lesson_count filters to `:lesson`; per-module planned-vs-credit; nil-safety for every unset target; zero-annual guard.
- **Resources:** `TeachingContext` accepts + persists the three targets; `ProgressionModule` accepts `credit_hours`.
- **Domain:** `update_teaching_context/2` enforces ownership (rejects another workspace's context) and persists targets; module credit update enforces ownership.
- **`FicheLive`:** quota header renders counts/bars; hides bars when targets nil; `save-targets` persists and re-renders; per-module `save-module-credit` persists; ownership on both.
- **`SetupLive`:** creating a context with the three targets persists them; blank fields → nil.
- **Non-regression:** `Coverage` untouched; P-B fiche tests still green.

## Open questions
None — targets to track (all three levels), lesson-count semantics (two counters: modules auto + `:lesson` lessons), entry point (both SetupLive create + FicheLive inline), and enforcement (advisory only) are all resolved.
