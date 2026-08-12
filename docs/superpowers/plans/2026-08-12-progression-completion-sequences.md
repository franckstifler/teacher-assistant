# Progression Lesson Completion & Sequence Assignment (P-D) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A one-click "done" checkbox per lesson and a per-module sequence selector, so the existing per-sequence coverage bars become meaningful — advisory only.

**Architecture:** `completed?` boolean on `ProgressionEntry` + `sequence_id` FK on `ProgressionModule` (inheritance source); assigning a module's sequence propagates to its entries and new lessons inherit it; `Coverage` counts a checked entry as fully covered; `FicheLive` gains the checkbox + selector. `coverage_live` is unchanged.

**Tech Stack:** Elixir, Ash 3.26 + AshPostgres 2.0, Phoenix LiveView, gettext (FR/EN), DaisyUI, Decimal.

## Global Constraints

- Ash 3 house style; domain functions `authorize?: false` with ownership via `fetch_owned_entry/2` / `fetch_owned_module/2` in the LiveView — never in the LiveView body beyond the fetch.
- All user copy in `gettext(...)`; FR+EN same commit (`mix gettext.extract --merge`).
- Migrations via `mix ash.codegen <snake_name>`.
- Hours are `Decimal`. **Advisory only** — no code path blocks or gates on completion/coverage.
- Sequence is assigned at the MODULE level and inherited by entries; `entry.sequence_id` stays the value `Coverage` groups by, kept in sync by propagation. No per-entry sequence override UI.
- Full gate before PR: `mix precommit`.

---

### Task 1: Data model — entry `completed?` + module `sequence_id`

**Files:**
- Modify: `lib/teacher_assistant/academics/progression_entry.ex`
- Modify: `lib/teacher_assistant/academics/progression_module.ex`
- Test: extend `test/teacher_assistant/academics/progression_module_test.exs` and `test/teacher_assistant/academics/progression_entry_test.exs`
- Generated: `priv/repo/migrations/*_add_entry_completed_and_module_sequence.exs`

**Interfaces:**
- Produces: `ProgressionEntry.completed? :: boolean` (default false, in create+update accepts). `ProgressionModule` gains `belongs_to :sequence` / `sequence_id` (nullable, in default create+update accepts, NOT in `:create_default_bucket`).

- [ ] **Step 1: Write failing tests**

Add to `progression_entry_test.exs`:

```elixir
  test "entry defaults completed? to false and accepts it on update", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    assert e.completed? == false
    {:ok, e} = e |> Ash.Changeset.for_update(:update, %{completed?: true}) |> Ash.update(authorize?: false)
    assert e.completed? == true
  end
```

Add to `progression_module_test.exs`:

```elixir
  test "module accepts a sequence_id", %{plan: plan} do
    year = Academics.current_academic_year(TeacherFixtures.workspace_fixture()) # placeholder — see NOTE
    _ = year
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    # sequence_id acceptance is exercised more fully in Task 3; here just assert the attribute exists & is nil by default
    assert m.sequence_id == nil
  end
```

> NOTE: creating a real `Sequence` needs a Term/AcademicYear graph. Keep Task-1's module test minimal (assert `sequence_id` defaults to nil and the attribute compiles); the full "assign a real sequence and propagate" behaviour is tested in Task 3, which builds the calendar. Drop the `year` placeholder line — it was illustrative.

- [ ] **Step 2: Run — expect fail** — `mix test test/teacher_assistant/academics/progression_entry_test.exs test/teacher_assistant/academics/progression_module_test.exs` → FAIL (unknown `completed?` / `sequence_id`).

- [ ] **Step 3: Add the attributes + accepts**

In `progression_entry.ex` `attributes do` (near `week_no`):

```elixir
    attribute :completed?, :boolean, allow_nil?: false, default: false, public?: true
```

Add `:completed?` to BOTH the `create:` and `update:` accept lists.

In `progression_module.ex`: add `:sequence_id` to the default `create:` and `update:` accept lists (leave `:create_default_bucket` untouched). In `relationships do`:

```elixir
    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? true
      public? true
    end
```

- [ ] **Step 4: Generate + migrate**

Run: `mix ash.codegen add_entry_completed_and_module_sequence`
Expected: `progression_entries.completed?` boolean NOT NULL default false; `progression_modules.sequence_id` nullable FK. Then `mix ecto.migrate`.

- [ ] **Step 5: Run — expect pass** — the two test files → PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/progression_entry.ex \
  lib/teacher_assistant/academics/progression_module.ex \
  test/teacher_assistant/academics priv/repo/migrations priv/resource_snapshots
git commit -m "feat(academics): entry completed? + module sequence_id"
```

---

### Task 2: `Coverage` honours `completed?`

**Files:**
- Modify: `lib/teacher_assistant/academics/coverage.ex`
- Test: `test/teacher_assistant/academics/coverage_test.exs`

**Interfaces:**
- Consumes: entries now carry `completed?` (a map key; default false when absent). Return shape unchanged.

- [ ] **Step 1: Write failing test** (append)

```elixir
  test "a completed entry counts as fully covered regardless of logs" do
    entries = [
      %{id: "e1", planned_hours: Decimal.new("3"), sequence_id: "s1", completed?: true},
      %{id: "e2", planned_hours: Decimal.new("2"), sequence_id: "s1", completed?: false}
    ]

    # e1 has NO log yet is completed → covered 3; e2 logged 1 → covered 1
    logs = [%{progression_entry_id: "e2", hours: Decimal.new("1")}]

    result = Coverage.summarize(entries, logs)
    assert Decimal.equal?(result.covered_hours, Decimal.new("4"))
    pe1 = Enum.find(result.per_entry, &(&1.entry_id == "e1"))
    assert Decimal.equal?(pe1.covered, Decimal.new("3"))
  end

  test "completed does not exceed planned even with over-logging" do
    entries = [%{id: "e1", planned_hours: Decimal.new("2"), sequence_id: nil, completed?: true}]
    logs = [%{progression_entry_id: "e1", hours: Decimal.new("5")}]
    result = Coverage.summarize(entries, logs)
    assert Decimal.equal?(result.covered_hours, Decimal.new("2"))
  end
```

- [ ] **Step 2: Run — expect fail** (e1 currently covered 0 without a log).

- [ ] **Step 3: Update the covered calc**

In `coverage.ex`, replace the `covered = ...` line inside the per_entry map:

```elixir
        completed = Map.get(e, :completed?, false)

        covered =
          cond do
            completed -> planned
            Decimal.compare(logged, planned) == :gt -> planned
            true -> logged
          end
```

- [ ] **Step 4: Run — expect pass** — `mix test test/teacher_assistant/academics/coverage_test.exs` → PASS (incl. the pre-existing non-regression tests, which use entries without `completed?` → default false).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/coverage.ex test/teacher_assistant/academics/coverage_test.exs
git commit -m "feat(coverage): a completed? entry counts as fully covered"
```

---

### Task 3: Domain API — completion toggle, module-sequence assignment, inheritance, duplicate

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: extend `test/teacher_assistant/academics/progression_module_test.exs` (+ a small progression_plan duplicate assertion)

**Interfaces:**
- Produces:
  - `set_entry_completed(%ProgressionEntry{}, boolean) :: {:ok, entry} | {:error, _}`.
  - `assign_module_sequence(%ProgressionModule{}, sequence_id | nil) :: {:ok, module} | {:error, _}` — updates the module then propagates `sequence_id` to all its entries.
  - `add_progression_entry/2` inherits `module.sequence_id` for the new entry (unless attrs specify one).
  - `duplicate_progression_plan/2` copies `module.sequence_id` and `entry.completed?`.

- [ ] **Step 1: Write failing tests** (append to `progression_module_test.exs`)

```elixir
  defp seed_sequence(plan) do
    {:ok, year} = Academics.get_progression_plan(plan.id) |> then(fn {:ok, p} -> {:ok, p} end)
    _ = year
    # build the calendar for the plan's academic year so real sequences exist
    {:ok, ay} = Ash.get(TeacherAssistant.Academics.AcademicYear, plan.academic_year_id, authorize?: false)
    :ok = Academics.build_default_calendar(ay)
    [seq | _] = Academics.list_sequences(ay)
    seq
  end

  test "assign_module_sequence sets the module and propagates to its entries", %{plan: plan} do
    seq = seed_sequence(plan)
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e1} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, m} = Academics.assign_module_sequence(m, seq.id)
    assert m.sequence_id == seq.id
    {:ok, e1} = Academics.get_progression_entry(e1.id)
    assert e1.sequence_id == seq.id
  end

  test "a lesson added after assignment inherits the module sequence", %{plan: plan} do
    seq = seed_sequence(plan)
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m} = Academics.assign_module_sequence(m, seq.id)
    {:ok, m} = Academics.fetch_owned_module(m.id, plan_ws(plan))
    {:ok, e} = Academics.add_progression_entry(m, %{lesson_title: "L2", entry_type: :lesson})
    assert e.sequence_id == seq.id
  end

  test "set_entry_completed toggles the flag", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, e} = Academics.set_entry_completed(e, true)
    assert e.completed? == true
  end
```

> NOTE: `plan_ws/1` — obtain the plan's workspace the way the test file's other owner-scoped tests do (the setup exposes `ws`/`plan`; use that `ws`). `get_progression_plan/1` and `get_progression_entry/1` already exist. Simplify `seed_sequence/1` to just: load the AcademicYear by `plan.academic_year_id`, `build_default_calendar/1`, `list_sequences/1` → first. Also add a duplicate assertion in `progression_plan_test.exs` that a copied plan carries `module.sequence_id` and `entry.completed?` (build a sequence, assign, mark an entry done, duplicate, assert).

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Implement**

Add near `rename_module/2` (~line 962):

```elixir
  def set_entry_completed(%ProgressionEntry{} = e, completed?) when is_boolean(completed?),
    do: e |> Ash.Changeset.for_update(:update, %{completed?: completed?}) |> Ash.update(authorize?: false)

  def assign_module_sequence(%ProgressionModule{} = m, sequence_id) do
    with {:ok, m} <-
           m |> Ash.Changeset.for_update(:update, %{sequence_id: sequence_id}) |> Ash.update(authorize?: false) do
      entries_in_module(m.id)
      |> Enum.each(fn e -> update_progression_entry(e, %{sequence_id: sequence_id}) end)

      {:ok, m}
    end
  end
```

(`entries_in_module/1` and `update_progression_entry/2` already exist — reuse them.)

Change `add_progression_entry/2`'s head + attrs to inherit the module sequence:

```elixir
  def add_progression_entry(
        %ProgressionModule{id: module_id, progression_plan_id: plan_id, sequence_id: module_seq},
        attrs
      ) do
    pos = entry_count(module_id) + 1

    attrs =
      attrs
      |> Map.put(:progression_plan_id, plan_id)
      |> Map.put(:progression_module_id, module_id)
      |> Map.put(:position, pos)
      |> Map.put_new(:sequence_id, module_seq)

    ProgressionEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end
```

In `duplicate_progression_plan/2`: the `:create_default_bucket` action does NOT accept `sequence_id`, so set it after creating the module; and copy `completed?` on entries. Replace the module+entry copy block:

```elixir
      for m <- list_progression_modules(plan) do
        {:ok, new_m} =
          ProgressionModule
          |> Ash.Changeset.for_create(
            if(m.default?, do: :create_default_bucket, else: :create),
            %{title: m.title, position: m.position, progression_plan_id: copy.id}
          )
          |> Ash.create(authorize?: false)

        new_m =
          if m.sequence_id do
            {:ok, nm} =
              new_m |> Ash.Changeset.for_update(:update, %{sequence_id: m.sequence_id}) |> Ash.update(authorize?: false)

            nm
          else
            new_m
          end

        for e <- m.entries do
          ProgressionEntry
          |> Ash.Changeset.for_create(:create, %{
            lesson_title: e.lesson_title,
            planned_hours: e.planned_hours,
            entry_type: e.entry_type,
            week_no: e.week_no,
            position: e.position,
            famille_de_situations: e.famille_de_situations,
            categories_action: e.categories_action,
            competence_visee: e.competence_visee,
            completed?: e.completed?,
            progression_plan_id: copy.id,
            progression_module_id: new_m.id,
            sequence_id: e.sequence_id
          })
          |> Ash.create!(authorize?: false)
        end
      end
```

- [ ] **Step 4: Run — expect pass** — the module + plan test files → PASS. `mix compile --warnings-as-errors` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics
git commit -m "feat(academics): set_entry_completed, assign_module_sequence, sequence inheritance, duplicate"
```

---

### Task 4: `FicheLive` — done checkbox + module sequence selector

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/fiche_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/fiche_live_test.exs`

**Interfaces:**
- Consumes: `set_entry_completed/2`, `assign_module_sequence/2`, `list_sequences/1`, `current_academic_year/1`, `fetch_owned_entry/2`, `fetch_owned_module/2`.

- [ ] **Step 1: Write failing tests** (append)

```elixir
  test "toggle-complete marks a lesson done", %{conn: conn, plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")
    view |> element("#entry-complete-#{e.id}") |> render_click()
    {:ok, e} = Academics.get_progression_entry(e.id)
    assert e.completed? == true
  end

  test "assign-module-sequence propagates the sequence to the module's entries", %{conn: conn, plan: plan} do
    {:ok, ay} = Ash.get(TeacherAssistant.Academics.AcademicYear, plan.academic_year_id, authorize?: false)
    :ok = Academics.build_default_calendar(ay)
    [seq | _] = Academics.list_sequences(ay)
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")
    view |> form("#seq-form-#{m.id}", %{module_id: m.id, sequence_id: seq.id}) |> render_change()
    {:ok, e} = Academics.get_progression_entry(e.id)
    assert e.sequence_id == seq.id
  end
```

> The file's `setup` already builds the default calendar in some cases (it calls `build_default_calendar` — check; if so, reuse `Academics.list_sequences/1` on the setup's `year` instead of rebuilding).

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Assign sequences**

In `assign_modules/2`, add (mirroring `coverage_live.ex`'s approach):

```elixir
    ws = socket.assigns.current_scope.current_workspace
    year = ws && Academics.current_academic_year(ws)
    sequences = (year && Academics.list_sequences(year)) || []
```

and `|> assign(:sequences, sequences)`. (If `assign_modules/2` doesn't already have `ws` in scope, read it from `socket.assigns.current_scope.current_workspace`.)

- [ ] **Step 4: Add handlers**

```elixir
  def handle_event("toggle-complete", %{"id" => id}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, e} <- ws && Academics.fetch_owned_entry(id, ws),
         {:ok, _} <- Academics.set_entry_completed(e, not e.completed?) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not update lesson"))}
    end
  end

  def handle_event("assign-module-sequence", %{"module_id" => id, "sequence_id" => raw}, socket) do
    ws = socket.assigns.current_scope.current_workspace
    sequence_id = if raw in [nil, ""], do: nil, else: raw

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         {:ok, _} <- Academics.assign_module_sequence(m, sequence_id) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not assign sequence"))}
    end
  end
```

- [ ] **Step 5: Render the checkbox + selector**

On each lesson `<li>`, prepend a checkbox:

```heex
<input
  id={"entry-complete-#{e.id}"}
  type="checkbox"
  class="checkbox checkbox-sm"
  checked={e.completed?}
  phx-click="toggle-complete"
  phx-value-id={e.id}
  aria-label={gettext("Mark lesson done")}
/>
```

Give the completed row a subtle affordance, e.g. wrap the title with `class={["font-display font-semibold", e.completed? && "line-through text-base-content/50"]}`.

On each module card header, add a sequence selector form:

```heex
<.form for={to_form(%{}, as: :seq)} id={"seq-form-#{m.id}"} phx-change="assign-module-sequence">
  <input type="hidden" name="module_id" value={m.id} />
  <select name="sequence_id" class="select select-sm" aria-label={gettext("Assign sequence")}>
    <option value="" selected={is_nil(m.sequence_id)}>{gettext("Sans séquence")}</option>
    <option :for={s <- @sequences} value={s.id} selected={m.sequence_id == s.id}>
      {gettext("Séq %{n}", n: s.number)}
    </option>
  </select>
</.form>
```

- [ ] **Step 6: gettext + run tests**

```bash
mix gettext.extract --merge
mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs
```
Fill FR/EN for new msgids ("Mark lesson done"→"Marquer la leçon comme faite"/"Mark lesson done", "Assign sequence"→"Affecter la séquence"/"Assign sequence", "Sans séquence"→"Sans séquence"/"No sequence", "Séq %{n}"→"Séq %{n}"/"Seq %{n}", "Could not update lesson", "Could not assign sequence"). Then full `mix test` → 0 failures; `mix compile --warnings-as-errors` clean. (Known intermittent `users_unique_email_index` fixture flake: re-run to confirm if it appears.)

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web priv/gettext test/teacher_assistant_web
git commit -m "feat(fiche): lesson done checkbox + per-module sequence selector"
```

---

## Self-Review

**Spec coverage:**
- §1 data model (`completed?`, module `sequence_id`) → Task 1. ✅
- §2 sequence inheritance (`assign_module_sequence` propagation, `add_progression_entry` inherit, duplicate copy) → Task 3. ✅
- §3 Coverage completion → Task 2. ✅
- §4 domain API → Task 3. ✅
- §5 UI (checkbox + selector; coverage_live unchanged) → Task 4. ✅
- §6 behavior (advisory, nil unassign, module overwrite, new-lesson inherit) → Tasks 3 (domain) + 4 (UI). ✅
- §7 testing (Coverage completed/cap/non-regression, resource accepts, propagation/inherit/toggle/duplicate, FicheLive toggle+assign, ownership, full suite) → Tasks 1–4. ✅

**Placeholder scan:** No "TBD"/vague directives. The test NOTES (Task 1 minimal module test; Task 3 `seed_sequence`/`plan_ws` binding; Task 4 calendar reuse) point at real per-file specifics to match, not deferred work; the illustrative `seed_sequence` is explicitly told to be simplified to load-year→build-calendar→list-sequences.

**Type consistency:** `set_entry_completed/2` (entry, bool) and `assign_module_sequence/2` (module, sequence_id|nil) signatures match between Task 3 and their Task 4 callers. `Coverage.summarize/2` return shape unchanged (Task 2 only alters the internal `covered` value), so `coverage_live` and `coverage_for_plan` need no change. Handler param shapes — `toggle-complete` `%{"id"=>...}` (checkbox `phx-value-id`), `assign-module-sequence` `%{"module_id"=>..., "sequence_id"=>...}` (form) — match the render markup and the tests. `add_progression_entry/2`'s new `sequence_id: module_seq` destructure reads a loaded attribute present on every `%ProgressionModule{}`.
