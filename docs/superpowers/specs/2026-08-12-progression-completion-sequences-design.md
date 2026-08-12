# Progression — lesson completion & sequence assignment (P-D)

**Status:** Approved design
**Date:** 2026-08-12
**Builds on:** P-B (first-class `ProgressionModule`, grouped `FicheLive` with `fetch_owned_module/2` / `fetch_owned_entry/2`, `add_progression_entry/2`, `duplicate_progression_plan/2`), P-C (module inline editors pattern), and the existing `Coverage` (planned-vs-covered, grouped by `entry.sequence_id`, already rendered by `coverage_live.ex` with a "Sans séquence" nil bucket), `Sequence` (6/year, date ranges), `list_sequences/1`, and `TeachingLogEntry` (cahier de textes).

## Purpose

Let a teacher **check off lessons as done** with a single click on the fiche, and **assign each module to one of the 6 sequences** so the per-sequence coverage bars (which already exist but collapse into "Sans séquence" today because entries carry no sequence) become meaningful. A checked lesson counts as fully covered even without a cahier-de-textes log — the checkbox is the lightweight completion signal; the log remains the richer optional record. This is the last block of the year-management rework (after P-B modules and P-C quotas).

Completion and coverage are **advisory** — nothing is blocked or gated.

## Scope

In scope:
- `ProgressionEntry` gains `completed?` (boolean, default false).
- `ProgressionModule` gains `sequence_id` (nullable, belongs_to `Sequence`) — the module's assigned sequence, the inheritance source.
- Assigning a sequence to a module writes `module.sequence_id` AND propagates `sequence_id` to all its entries; a lesson added later inherits the module's sequence at creation.
- `Coverage.summarize` treats a `completed?` entry as fully covered (`covered = planned`), otherwise keeps the log-based cap.
- `FicheLive`: a done-checkbox per lesson row (toggle, owner-scoped) and a sequence selector per module card (assign, owner-scoped, propagating).
- Domain: `set_entry_completed/2`, `assign_module_sequence/2`; `add_progression_entry/2` inherits the module sequence; `duplicate_progression_plan/2` copies `module.sequence_id` + `entry.completed?`.

Out of scope (YAGNI / deferred):
- **No per-entry sequence override UI** — sequence is assigned at the module level and inherited (the user chose module-inherited). `entry.sequence_id` stays authoritative for `Coverage`, always kept in sync by propagation.
- **No auto-derivation** of sequence from `week_no`/calendar dates.
- No change to `coverage_live.ex` rendering — its by_sequence bars already handle real + nil sequences; this feature only feeds them real data.
- No "partial done" on the checkbox — partial coverage stays the province of `TeachingLogEntry` (done/partial); the checkbox is binary.
- No completion **count** stat (lessons-done/total per sequence) — coverage stays hours-based via the existing `Coverage`. A later increment could add counts.
- No gating/blocking anywhere.

## 1. Data model

### `ProgressionEntry` (add)
- `attribute :completed?, :boolean, allow_nil?: false, default: false, public?: true` — add `:completed?` to the `create` and `update` accept lists.

### `ProgressionModule` (add)
- `belongs_to :sequence, TeacherAssistant.Academics.Sequence` with `source_attribute :sequence_id`, `allow_nil? true`, `public? true`. Add `:sequence_id` to the default `create` and `update` accept lists (NOT to `:create_default_bucket` — the bucket can still be assigned later via the normal update path if desired, but is not required to carry one at creation).

Migration: one `mix ash.codegen` run adding `completed?` (NOT NULL default false) to `progression_entries` and a nullable `sequence_id` FK to `progression_modules`.

## 2. Sequence inheritance

- **`assign_module_sequence(module, sequence_id)`** (`sequence_id` may be nil to unassign): owner-scoped at the caller; sets `module.sequence_id` then updates every entry of that module to the same `sequence_id`. Sequential per-entry updates (mirrors `delete_module/1`'s reassignment loop) — fine at plan scale.
- **`add_progression_entry(module, attrs)`**: default the new entry's `sequence_id` to `module.sequence_id` when `attrs` does not specify one (`Map.put_new(attrs, :sequence_id, module.sequence_id)`). The `module` struct already carries `sequence_id` (a loaded attribute).
- **`duplicate_progression_plan/2`**: carry `sequence_id` when creating the copied modules, and `completed?` when copying entries (extend the existing copy maps).

## 3. Completion unified to `Coverage`

In `Coverage.summarize(entries, logs)`, the per-entry `covered` becomes:

```
completed = Map.get(e, :completed?, false)
covered = if completed, do: planned, else: (if logged > planned, do: planned, else: logged)
```

So a checked lesson is fully covered regardless of logs; an unchecked lesson keeps today's log-capped behaviour. `entries` already carry `completed?` (a loaded attribute); the pure test feeds it as a map key (default false when absent). No change to the by_sequence grouping (still `entry.sequence_id`) or the returned shape.

## 4. Domain API (`Academics`)

- `set_entry_completed(%ProgressionEntry{}, completed?) :: {:ok, entry} | {:error, _}` — plain `:update` of `completed?`.
- `assign_module_sequence(%ProgressionModule{}, sequence_id) :: {:ok, module} | {:error, _}` — update module `sequence_id`, then propagate to its entries (per §2).
- `add_progression_entry/2` — inherit module sequence (per §2).
- `duplicate_progression_plan/2` — copy the two new fields (per §2).
- Ownership is enforced by the LiveView via the existing `fetch_owned_entry/2` / `fetch_owned_module/2` before calling these.

## 5. UI — `FicheLive`

- **Done checkbox** on each lesson row: a small checkbox bound to `e.completed?`, `phx-click="toggle-complete"` with `phx-value-id={e.id}`. The handler resolves the entry via `fetch_owned_entry/2`, calls `set_entry_completed(entry, not entry.completed?)`, re-assigns. A completed lesson gets a subtle visual affordance (e.g. muted/struck title or a check accent) — reuse existing chalkboard vocabulary.
- **Sequence selector** on each module card header: a `<select>` of the year's sequences (label e.g. "Séq 1"… from `list_sequences/1`) plus a blank "Sans séquence" option, bound to `m.sequence_id`, `phx-change="assign-module-sequence"` with `phx-value-id={m.id}`. Handler resolves via `fetch_owned_module/2`, calls `assign_module_sequence(m, chosen_or_nil)`, re-assigns. Requires the sequences list assigned in `mount`/`assign_modules` (fetch via the plan's `academic_year_id` → `list_sequences/1`).

`coverage_live.ex` is unchanged — its by_sequence bars now reflect real sequences and checkbox completion.

## 6. Behavior & edge cases

- Advisory; toggling is reversible; assigning "Sans séquence" (blank) sets nil on module + entries.
- Assigning a module's sequence **overwrites** every entry's sequence in that module (no per-entry override in scope) — consistent with module-inherited.
- A newly added lesson inherits the module's current sequence; a lesson moved across modules by drag-and-drop keeps its own `sequence_id` (its `apply_layout` path doesn't touch sequence) — acceptable; the teacher can re-assign the module if needed. (Noted, not fixed here.)
- Default bucket may hold a sequence like any module; not required.

## 7. Testing

- **`Coverage` (pure):** a `completed?` entry → covered == planned even with no/partial log; unchecked entry keeps log-cap; `max(log, completed)` cap never exceeds planned; by_sequence grouping unchanged (non-regression of existing coverage_test).
- **Resources:** `ProgressionEntry` accepts/persists `completed?`; `ProgressionModule` accepts/persists `sequence_id`.
- **Domain:** `set_entry_completed/2` toggles; `assign_module_sequence/2` sets the module AND propagates to all its entries (and nil unassigns); `add_progression_entry/2` inherits the module sequence for a new lesson; `duplicate_progression_plan/2` carries both new fields.
- **`FicheLive`:** toggle-complete persists + reflects; sequence selector assigns and propagates (assert an entry's `sequence_id` changed); a lesson added after assignment inherits; ownership on both handlers.
- **Non-regression:** full suite green; `coverage_live` still renders.

## Open questions
None — completion model (boolean unified to Coverage), sequence assignment (module-inherited via a stored `module.sequence_id`), and no-blocking are all resolved.
