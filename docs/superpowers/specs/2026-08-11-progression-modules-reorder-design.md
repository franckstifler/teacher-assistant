# Progression — first-class modules + drag-and-drop reordering

**Status:** Approved design
**Date:** 2026-08-11
**Builds on:** the existing progression stack — `ProgressionPlan` / `ProgressionEntry`
(module currently a free-text column + plan-wide `position`), `import_progression_plan/3`
+ `FicheParser` (carry-forward `current_module`), `FicheLive` builder, `Coverage`
(planned-vs-covered, grouped by sequence), and the `move_lesson_step/2` up/down pattern
already used for lesson-plan steps.

## Purpose

Turn the progression's **module** from a free-text string on each entry into a
first-class, orderable entity, and let each teacher **reorganize their own plan by
drag-and-drop** — reorder whole module blocks, reorder lessons inside a module, and drag
a lesson from one module to another. Every teacher's plan is already their own document
(scoped to their workspace/teaching-context), so "per-teacher order" needs no new
ownership concept — only the ability to reposition.

This is the structural foundation the domain KB calls for ("keep the immutable national
syllabus separate from the teacher's local pacing"; module = a real hierarchy level with
3–8 per subject) and it unblocks the later quota work (P-C) and completion/sequence stats
(P-D).

## Scope

In scope:
- New `ProgressionModule` resource (title, position within plan, `default?` flag).
- `ProgressionEntry`: replace the free-text `module` string with a required
  `progression_module_id`; `position` now means order **within its module**.
- A **default bucket module** ("Général / General") per plan for entries that belong to
  no named module (prise de contact, standalone evaluations, holidays). Every entry
  always belongs to a module — module blocks are contiguous.
- Data migration: existing entries' `module` strings → grouped `ProgressionModule` rows,
  first-appearance order preserved; blank → the default bucket; per-module positions
  recomputed.
- Import rewrite: create modules from the parser's ordered module list, link entries.
- Drag-and-drop reordering in `FicheLive` (SortableJS), two levels, cross-module moves,
  with keyboard-accessible drag handles.
- Module CRUD (add / rename / delete-with-reassign) and per-module "add lesson".
- Per-module **computed** hours total (sum of its lessons' `planned_hours`).
- Update every reader of `entry.module` to `entry.progression_module.title`.

Out of scope (deferred / YAGNI):
- **No editable module hour *credit/quota*** and no "planned vs quota" bars — that is
  P-C (quotas & targets). P-B shows only the computed sum.
- No moving `famille_de_situations` / competence fields up to the module level — they
  stay on the entry for now (a later normalization).
- No sequence assignment or completion checkbox — that is P-D.
- No `Coverage` change — it stays grouped by sequence. A future `by_module` breakdown is
  out of scope here.
- No syllabus-level (national, immutable) module reference data — modules are
  plan-local and teacher-authored.

## 1. Data model

### `ProgressionModule` (new, table `progression_modules`)

| Attribute | Type | Notes |
|---|---|---|
| `id` | uuid_v7 | pk |
| `title` | string | required |
| `position` | integer | required; order within the plan (1-based) |
| `default?` | boolean | default `false`; marks the "Général" bucket, undeletable |
| timestamps | | |

Relationships: `belongs_to :progression_plan` (required); `has_many :entries,
ProgressionEntry`.

Actions: default `:read` / `:destroy`; `create: [:title, :position,
:progression_plan_id]`; `update: [:title, :position]`. `default?` is **not** publicly
accepted — it is set internally by `ensure_default_module/1` (a dedicated create action
or a `set_attribute` change), so a teacher can never mint a second bucket. Policies
mirror the existing
`ProgressionEntry`/`ProgressionPlan` house style (`policy always() -> authorize_if
always()`); workspace ownership is enforced at the domain-function layer via the plan,
as it is today.

### `ProgressionEntry` (modified)

- **Remove** `attribute :module, :string`.
- **Add** `belongs_to :progression_module` (`allow_nil? false`, `public? true`); add
  `:progression_module_id` to the create/update accepted args, drop `:module`.
- `position` semantics change from **plan-wide** to **within the module**. No column
  change; only how it is assigned/sorted.

## 2. Data migration

A data migration (not just a schema migration) runs per plan:

1. Add `progression_modules` table; add nullable `progression_module_id` to
   `progression_entries` (backfill), then flip to `NOT NULL` and drop the `module`
   column in a follow-up step once backfilled.
2. For each plan: read entries ordered by current `position`. Walk them, collecting
   **distinct `module` strings in first-appearance order** → insert `ProgressionModule`
   rows with `position` 1..n. A blank/`nil`/whitespace `module` maps to a lazily-created
   **default bucket** module for that plan (`default? = true`, localized title).
3. Set each entry's `progression_module_id`, and recompute its `position` as its 1-based
   index **within its module** (preserving the original relative order).

The migration is deterministic and idempotent per plan (guard on "already has modules").

## 3. Import & parser

`FicheParser` already threads `current_module` (carry-forward when the cell is blank), so
its row output is unchanged. `import_progression_plan/3` changes:

1. From the ordered rows, derive the distinct module titles in first-appearance order;
   create `ProgressionModule` rows (blank → default bucket, created once).
2. Create each entry linked to its module, with `position` = its 1-based index within
   that module. All inside the existing `Repo.transaction`.

## 4. Domain API (`Academics`)

New / changed functions (all `authorize?: false`, workspace ownership checked via the
owned-plan/owned-entry fetch that already exists):

- `list_progression_modules(plan)` → modules ordered by `position`, each with its
  `entries` preloaded and ordered by `position`. Replaces `list_progression_entries/1`
  as the builder's primary read (the old function can stay for callers that want a flat
  list).
- `create_module(plan, attrs)` → appends a module at `position = count + 1`.
- `rename_module(module, title)`.
- `delete_module(module)` → reassign its entries to the plan's default bucket (appended
  after the bucket's current entries), then destroy. Refuses if `module.default?`.
- `add_progression_entry(module, attrs)` → append at end of that module (position =
  module entry count + 1). (Signature changes from plan-targeted to module-targeted.)
- `ensure_default_module(plan)` → fetch-or-create the `default? = true` bucket.
- **`apply_layout(plan, layout)`** — the single transactional endpoint for every
  drag-and-drop (and keyboard) reorder. `layout` is the full resulting tree:
  `[%{"module_id" => id, "entry_ids" => [id, ...]}, ...]`. The server, in one
  transaction:
  - validates every id belongs to this plan (reject unknown/foreign ids → no-op error),
  - sets each module's `position` from the list order,
  - sets each entry's `progression_module_id` (handles cross-module moves) and its
    `position` from its index in that module's `entry_ids`,
  - verifies the layout covers **exactly** the plan's current module+entry sets (guards
    against a stale client dropping or duplicating rows).

  Sending the whole tree each drop is robust against client/server drift and trivial at
  plan sizes (~30 rows); it is preferred over granular move events.

## 5. UI — `FicheLive` with drag-and-drop

Layout: entries grouped into **module cards**, in `position` order. Each card:
- header row: drag handle · module title (inline-editable rename) · computed hours sum
  (`Σ planned_hours` of its lessons) · delete button (hidden on the default bucket) ·
  "add lesson" affordance targeting this module;
- body: its lessons as draggable rows (keeping the existing per-row content — title,
  type badge, hours, Préparer / delete).

A **"Add module"** button sits at the section level.

**SortableJS hook** (`assets/js/`), two coordinated sortables:
- module-level: modules sortable by the header handle;
- entry-level: lessons sortable within each card, all sharing **one group name** so a
  lesson can be dragged across cards.
- On any drop (either level), the hook reads the resulting DOM tree, builds the
  `layout`, and pushes `"apply-layout"`. Server persists via `apply_layout/2` and
  re-renders from truth (the DOM is reconciled to the persisted order).

**Keyboard accessibility** (SortableJS is not keyboard-operable on its own): each drag
handle is focusable and exposes a small keyboard interaction — `Enter`/`Space` to
"pick up", `↑`/`↓` to move one position (within level; at a card boundary an entry moves
into the adjacent card), `Enter`/`Space` to drop, `Esc` to cancel. Each committed move
pushes the same `"apply-layout"` event, so there is one persistence path. `aria-live`
announces the moved item's new position. This keeps reordering usable by keyboard and
screen-reader users without adding permanent up/down buttons.

## 6. Callers of `entry.module` to update

Every read of the old string becomes `entry.progression_module.title` (preloaded):
- `FicheLive` render (module cell / mobile subtitle),
- `FichePrintController` / any fiche print template,
- any export or summary that references `.module`.
An audit grep for `\.module\b` on `ProgressionEntry` values is part of the work; each hit
is switched to the preloaded association.

## 7. Testing

- **Resource:** `ProgressionModule` CRUD; `apply_layout/2` — reorders modules, reorders
  lessons in a module, moves a lesson cross-module, and **rejects** a layout with
  missing/extra/foreign ids (no partial writes).
- **Migration:** existing string modules → grouped modules in first-appearance order;
  blank strings → default bucket; per-module positions correct; idempotent re-run.
- **Import:** parser's ordered modules become `ProgressionModule` rows; entries linked;
  per-module positions; blank → bucket.
- **Domain:** `delete_module` reassigns entries to the bucket and refuses on the bucket;
  `add_progression_entry` appends within the target module.
- **LiveView:** drop payload reorders modules; cross-module lesson move persists;
  add/rename/delete module; keyboard move commits via `apply-layout`.
- **Non-regression:** `Coverage.summarize/2` output unchanged (still per-sequence).

## Open questions

None — the two prior open points are resolved: (a) drag-and-drop sends the **full tree**
per drop (§4); (b) keyboard accessibility via focusable handles is **kept** in P-B (§5).
