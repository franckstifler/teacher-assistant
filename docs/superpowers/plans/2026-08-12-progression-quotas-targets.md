# Progression Hour Quotas & Count Targets (P-C) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture per-subject targets (annual hours, module count, lesson count, per-module hour credit) and show planned-vs-target gaps on the fiche de progression — advisory only, never blocking.

**Architecture:** Three nullable target columns on `TeachingContext` + a nullable `credit_hours` on `ProgressionModule`; a pure `Quota` module (twin of `Coverage`) computes context- and module-level gaps; `FicheLive` renders a quota header + inline target/credit editors; `SetupLive` seeds the context targets at creation. A new owner-scoped `update_teaching_context/3` persists context targets.

**Tech Stack:** Elixir, Ash 3.26 + AshPostgres 2.0, Phoenix LiveView, gettext (FR/EN), DaisyUI/Tailwind, Decimal.

## Global Constraints

- Ash 3 house style; domain functions use `authorize?: false` with ownership enforced via `fetch_owned_*` helpers (`fetch_owned_teaching_context/2`, `fetch_owned_module/2`) — never in the LiveView.
- All user-facing copy in `gettext(...)`; FR + EN filled in the same commit (`mix gettext.extract --merge`, then edit `priv/gettext/{fr,en}/LC_MESSAGES/default.po`).
- Migrations via `mix ash.codegen <snake_name>`.
- Hours are `Decimal` (sum with `Decimal.add/2`); ratios are floats guarded against division by zero.
- **Targets are advisory** — no code path blocks adding/removing entries or modules. Any unset (nil) target renders no bar.
- `module_count` excludes the `default? == true` bucket; `lesson_count` counts only `entry_type == :lesson`.
- Full gate before PR: `mix precommit` (compile, deps.unlock, format, test).

---

### Task 1: Data model — context targets + module credit

**Files:**
- Modify: `lib/teacher_assistant/academics/teaching_context.ex`
- Modify: `lib/teacher_assistant/academics/progression_module.ex`
- Test: `test/teacher_assistant/academics/teaching_context_test.exs` (create if absent) and extend `test/teacher_assistant/academics/progression_module_test.exs`
- Generated: `priv/repo/migrations/*_add_context_targets_and_module_credit.exs`

**Interfaces:**
- Produces: `TeachingContext` with `annual_hours:decimal`, `target_module_count:integer`, `target_lesson_count:integer` (all nullable, in create+update accepts). `ProgressionModule` with `credit_hours:decimal` (nullable, in create+update accepts).

- [ ] **Step 1: Write failing tests**

Create `test/teacher_assistant/academics/teaching_context_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.TeachingContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{ws: ws, year: year}
  end

  test "create accepts annual_hours and count targets", %{ws: ws, year: year} do
    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4,
        annual_hours: Decimal.new("100"),
        target_module_count: 4,
        target_lesson_count: 21
      })

    assert Decimal.equal?(ctx.annual_hours, Decimal.new("100"))
    assert ctx.target_module_count == 4
    assert ctx.target_lesson_count == 21
  end
end
```

Add to `test/teacher_assistant/academics/progression_module_test.exs`:

```elixir
  test "module accepts a credit_hours", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m} = Academics.update_module_credit(m, Decimal.new("11"))
    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end
```

> NOTE: `update_module_credit/2` is added in Task 3; if you are running strictly task-by-task, write this assertion against a direct `Ash.Changeset.for_update(:update, %{credit_hours: ...})` in Task 1 and switch it to `update_module_credit/2` in Task 3. Simpler: keep this specific assertion in Task 3's test batch. For Task 1, assert acceptance via a direct changeset:

```elixir
  test "module accepts credit_hours via update", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m} =
      m |> Ash.Changeset.for_update(:update, %{credit_hours: Decimal.new("11")}) |> Ash.update(authorize?: false)
    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end
```

- [ ] **Step 2: Run — expect fail** — `mix test test/teacher_assistant/academics/teaching_context_test.exs test/teacher_assistant/academics/progression_module_test.exs` → FAIL (unknown attributes).

- [ ] **Step 3: Add the attributes + accepts**

In `teaching_context.ex` `attributes do` (after `coefficient`):

```elixir
    attribute :annual_hours, :decimal, allow_nil?: true, public?: true
    attribute :target_module_count, :integer, allow_nil?: true, public?: true
    attribute :target_lesson_count, :integer, allow_nil?: true, public?: true
```

Add `:annual_hours, :target_module_count, :target_lesson_count` to BOTH the `create:` and `update:` accept lists.

In `progression_module.ex` `attributes do` (after `default?`):

```elixir
    attribute :credit_hours, :decimal, allow_nil?: true, public?: true
```

Add `:credit_hours` to the default `create:` and `update:` accept lists. (Leave `:create_default_bucket`'s accept list unchanged.)

- [ ] **Step 4: Generate + migrate**

Run: `mix ash.codegen add_context_targets_and_module_credit`
Expected: one migration adding three nullable columns to `teaching_contexts` and one nullable column to `progression_modules`. Then `mix ecto.migrate`.

- [ ] **Step 5: Run — expect pass** — `mix test test/teacher_assistant/academics/teaching_context_test.exs test/teacher_assistant/academics/progression_module_test.exs` → PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/teaching_context.ex \
  lib/teacher_assistant/academics/progression_module.ex \
  test/teacher_assistant/academics priv/repo/migrations priv/resource_snapshots
git commit -m "feat(academics): context hour/count targets + module credit_hours"
```

---

### Task 2: Pure `Quota` computation

**Files:**
- Create: `lib/teacher_assistant/academics/quota.ex`
- Test: `test/teacher_assistant/academics/quota_test.exs`

**Interfaces:**
- Produces: `TeacherAssistant.Academics.Quota.summarize(ctx, modules)` → the map documented below. `ctx` may be `nil` (all targets nil). `modules` is the `list_progression_modules/1` shape: a list of maps/structs each with `id`, `default?`, `credit_hours`, and a loaded `entries` list whose items have `planned_hours` and `entry_type`.

- [ ] **Step 1: Write failing test**

```elixir
# test/teacher_assistant/academics/quota_test.exs
defmodule TeacherAssistant.Academics.QuotaTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Quota

  defp entry(hours, type \\ :lesson),
    do: %{planned_hours: Decimal.new(hours), entry_type: type}

  defp mod(id, default?, credit, entries),
    do: %{id: id, default?: default?, credit_hours: credit, entries: entries}

  test "summarizes context and per-module gaps, excluding default bucket and non-lessons" do
    ctx = %{annual_hours: Decimal.new("100"), target_module_count: 2, target_lesson_count: 3}

    modules = [
      mod("m1", false, Decimal.new("40"), [entry("20"), entry("10"), entry("2", :evaluation)]),
      mod("m2", false, nil, [entry("15")]),
      mod("bucket", true, nil, [entry("3", :lesson), entry("1", :holiday)])
    ]

    q = Quota.summarize(ctx, modules)

    assert Decimal.equal?(q.planned_hours, Decimal.new("51"))
    assert Decimal.equal?(q.annual_hours, Decimal.new("100"))
    assert_in_delta q.hours_ratio, 0.51, 0.0001
    # default bucket excluded from module count
    assert q.module_count == 2
    assert q.target_module_count == 2
    # lessons only: 20,10 (m1) + 15 (m2) + 3 (bucket lesson) = 4 lessons; evaluation & holiday excluded
    assert q.lesson_count == 4
    assert q.target_lesson_count == 3

    m1 = Enum.find(q.per_module, &(&1.module_id == "m1"))
    assert Decimal.equal?(m1.planned, Decimal.new("32"))
    assert Decimal.equal?(m1.credit, Decimal.new("40"))
    assert_in_delta m1.ratio, 0.8, 0.0001

    m2 = Enum.find(q.per_module, &(&1.module_id == "m2"))
    assert m2.credit == nil
    assert m2.ratio == nil
  end

  test "nil context yields nil targets and nil ratios, planned still computed" do
    modules = [%{id: "m1", default?: false, credit_hours: nil, entries: [%{planned_hours: Decimal.new("5"), entry_type: :lesson}]}]
    q = Quota.summarize(nil, modules)
    assert Decimal.equal?(q.planned_hours, Decimal.new("5"))
    assert q.annual_hours == nil
    assert q.hours_ratio == nil
    assert q.target_module_count == nil
    assert q.module_count == 1
  end
end
```

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Implement `Quota`**

```elixir
# lib/teacher_assistant/academics/quota.ex
defmodule TeacherAssistant.Academics.Quota do
  @moduledoc "Pure planned-vs-target gap calculation for progression quotas."

  def summarize(ctx, modules) do
    entries = Enum.flat_map(modules, &Map.get(&1, :entries, []))
    planned = sum_hours(entries)

    named_modules = Enum.reject(modules, & &1.default?)
    lesson_count = Enum.count(entries, &(&1.entry_type == :lesson))

    annual = ctx && ctx.annual_hours
    target_modules = ctx && ctx.target_module_count
    target_lessons = ctx && ctx.target_lesson_count

    per_module =
      Enum.map(modules, fn m ->
        p = sum_hours(Map.get(m, :entries, []))
        credit = Map.get(m, :credit_hours)
        %{module_id: m.id, planned: p, credit: credit, ratio: ratio(p, credit)}
      end)

    %{
      planned_hours: planned,
      annual_hours: annual,
      hours_ratio: ratio(planned, annual),
      module_count: length(named_modules),
      target_module_count: target_modules,
      lesson_count: lesson_count,
      target_lesson_count: target_lessons,
      per_module: per_module
    }
  end

  defp sum_hours(entries),
    do: Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, to_decimal(e.planned_hours)) end)

  # ratio numerator/denominator; nil when denominator is nil or zero
  defp ratio(_num, nil), do: nil

  defp ratio(num, %Decimal{} = den) do
    if Decimal.equal?(den, Decimal.new(0)), do: nil, else: Decimal.to_float(Decimal.div(num, den))
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
end
```

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/quota.ex test/teacher_assistant/academics/quota_test.exs
git commit -m "feat(academics): pure Quota planned-vs-target gap calculation"
```

---

### Task 3: Domain API — `update_teaching_context/3` + `update_module_credit/2`

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/teaching_context_test.exs` (extend) + `test/teacher_assistant/academics/progression_module_test.exs` (extend)

**Interfaces:**
- Produces:
  - `update_teaching_context(id, %Workspace{}, attrs) :: {:ok, TeachingContext.t()} | {:error, :not_found | term}` — owner-scoped via `fetch_owned_teaching_context/2`, then default `:update`.
  - `update_module_credit(%ProgressionModule{}, credit) :: {:ok, ProgressionModule.t()} | {:error, term}` — mirrors `rename_module/2`.

- [ ] **Step 1: Write failing tests**

Add to `teaching_context_test.exs`:

```elixir
  test "update_teaching_context persists targets for an owned context", %{ws: ws, year: year} do
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, ctx} = Academics.update_teaching_context(ctx.id, ws, %{annual_hours: Decimal.new("75"), target_lesson_count: 18})
    assert Decimal.equal?(ctx.annual_hours, Decimal.new("75"))
    assert ctx.target_lesson_count == 18
  end

  test "update_teaching_context rejects a context from another workspace", %{ws: ws, year: year} do
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    other = TeacherFixtures.workspace_fixture()
    assert {:error, :not_found} = Academics.update_teaching_context(ctx.id, other, %{annual_hours: Decimal.new("50")})
  end
```

Add to `progression_module_test.exs` (this supersedes the Task 1 direct-changeset assertion):

```elixir
  test "update_module_credit sets the credit", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m} = Academics.update_module_credit(m, Decimal.new("11"))
    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end
```

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Implement**

Near `create_teaching_context/3` (~line 236) add:

```elixir
  def update_teaching_context(id, %Workspace{} = ws, attrs) do
    with {:ok, ctx} <- fetch_owned_teaching_context(id, ws) do
      ctx |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)
    end
  end
```

Near `rename_module/2` (~line 956) add:

```elixir
  def update_module_credit(%ProgressionModule{} = m, credit),
    do: m |> Ash.Changeset.for_update(:update, %{credit_hours: credit}) |> Ash.update(authorize?: false)
```

- [ ] **Step 4: Run — expect pass** — `mix test test/teacher_assistant/academics/teaching_context_test.exs test/teacher_assistant/academics/progression_module_test.exs` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics
git commit -m "feat(academics): owner-scoped update_teaching_context + update_module_credit"
```

---

### Task 4: `FicheLive` quota header + inline target/credit editors

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/fiche_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/fiche_live_test.exs`

**Interfaces:**
- Consumes: `Quota.summarize/2`, `update_teaching_context/3`, `update_module_credit/2`, `fetch_owned_module/2`.

- [ ] **Step 1: Write failing tests** (append)

```elixir
  test "quota header renders planned-vs-annual and count read-outs", %{conn: conn, plan: plan, ctx: ctx} do
    {:ok, _} = Academics.update_teaching_context(ctx.id, ctx_ws(ctx), %{annual_hours: Decimal.new("50"), target_lesson_count: 3})
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, _} = Academics.add_progression_entry(m, %{lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson})
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")
    html = render(view)
    assert html =~ "50"
    assert html =~ "quota-header"
  end

  test "save-targets persists context targets", %{conn: conn, plan: plan} do
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")
    view |> form("#targets-form", %{targets: %{annual_hours: "75", target_module_count: "4", target_lesson_count: "21"}}) |> render_submit()
    ctx = Academics.get_teaching_context(plan.teaching_context_id) |> elem(1)
    assert Decimal.equal?(ctx.annual_hours, Decimal.new("75"))
    assert ctx.target_lesson_count == 21
  end

  test "save-module-credit persists a module credit", %{conn: conn, plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")
    view |> form("#module-credit-form-#{m.id}", %{credit_hours: "11", module_id: m.id}) |> render_submit()
    m = Academics.fetch_owned_module(m.id, ctx_ws_from_plan(plan)) |> elem(1)
    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end
```

> Helper note: the test setup already logs a user in with a workspace (`register_and_log_in_user`), and `plan`/`ctx` come from the file's `setup`. Use the `%{workspace: ws}` from that setup instead of `ctx_ws/ctx_ws_from_plan` if the file exposes it — adapt to the existing setup's bindings (see how sibling tests obtain `ws`). The assertion intent (targets/credit persisted) is what matters.

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Assign the quota summary**

In `assign_modules/2`, after computing `modules`, add `alias TeacherAssistant.Academics.Quota` at the top and:

```elixir
    |> assign(:quota, Quota.summarize(ctx, modules))
    |> assign(:targets_form, to_form(%{}, as: :targets))
```

- [ ] **Step 4: Add the handlers**

```elixir
  def handle_event("save-targets", %{"targets" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace
    ctx = socket.assigns.ctx

    attrs = %{
      annual_hours: parse_decimal(p["annual_hours"]),
      target_module_count: parse_int(p["target_module_count"]),
      target_lesson_count: parse_int(p["target_lesson_count"])
    }

    case ws && ctx && Academics.update_teaching_context(ctx.id, ws, attrs) do
      {:ok, _} -> {:noreply, assign_modules(socket, socket.assigns.plan)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not save targets"))}
    end
  end

  def handle_event("save-module-credit", %{"module_id" => id, "credit_hours" => raw}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         {:ok, _} <- Academics.update_module_credit(m, parse_decimal(raw)) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not save credit"))}
    end
  end
```

Add parse helpers near `blank_to/2`:

```elixir
  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal(s) when is_binary(s) do
    case Decimal.parse(String.trim(s)) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> n
      _ -> nil
    end
  end
```

- [ ] **Step 5: Render the quota header + module credit editor**

Add a quota header block just before the `#fiche-modules` div (replacing/augmenting the existing `#fiche-hours-total`). Use a small helper `ratio_pct/1` (`nil -> nil`, else `round(ratio*100)`), rendering a labelled value and a thin bar only when the target is set:

```heex
<div id="quota-header" class="grid gap-3 sm:grid-cols-3">
  <.quota_stat label={gettext("Heures")}
    value={Decimal.to_string(@quota.planned_hours)} target={@quota.annual_hours && Decimal.to_string(@quota.annual_hours)}
    suffix="h" ratio={@quota.hours_ratio} />
  <.quota_stat label={gettext("Modules")}
    value={Integer.to_string(@quota.module_count)} target={@quota.target_module_count && Integer.to_string(@quota.target_module_count)}
    ratio={count_ratio(@quota.module_count, @quota.target_module_count)} />
  <.quota_stat label={gettext("Leçons")}
    value={Integer.to_string(@quota.lesson_count)} target={@quota.target_lesson_count && Integer.to_string(@quota.target_lesson_count)}
    ratio={count_ratio(@quota.lesson_count, @quota.target_lesson_count)} />
</div>

<.form for={@targets_form} id="targets-form" phx-submit="save-targets" class="flex flex-wrap items-end gap-2">
  <.input type="number" name="targets[annual_hours]" value={@quota.annual_hours && Decimal.to_string(@quota.annual_hours)} label={gettext("Horaire annuel")} step="0.5" />
  <.input type="number" name="targets[target_module_count]" value={@quota.target_module_count} label={gettext("Cible modules")} />
  <.input type="number" name="targets[target_lesson_count]" value={@quota.target_lesson_count} label={gettext("Cible leçons")} />
  <.button type="submit" class="btn btn-ghost btn-sm">{gettext("Save targets")}</.button>
</.form>
```

Define a `quota_stat` function component (label, value, optional target, optional suffix, optional ratio) in this module — value shown as `value / target suffix`, with a `<progress>`/thin bar when `target` present, and an over/under accent class when `ratio` is > 1.0 / < some threshold. And `count_ratio(n, nil) -> nil; count_ratio(n, t) -> n/t`.

In each module card header, next to the computed hours, add a credit editor + read-out:

```heex
<span :if={credit_for(@quota, m.id)} class="ta-num text-sm text-base-content/60">
  / {Decimal.to_string(credit_for(@quota, m.id))}h
</span>
<.form for={to_form(%{}, as: :credit)} id={"module-credit-form-#{m.id}"} phx-submit="save-module-credit" class="flex items-end gap-1">
  <input type="hidden" name="module_id" value={m.id} />
  <.input type="number" name="credit_hours" value={m.credit_hours && Decimal.to_string(m.credit_hours)} step="0.5" label={gettext("Crédit h")} />
  <.button type="submit" class="btn btn-ghost btn-xs">{gettext("Save")}</.button>
</.form>
```

Helper `credit_for(quota, module_id)` looks up `per_module` for that id and returns its `credit`. (Or read `m.credit_hours` directly — the module is loaded — both are fine; prefer `m.credit_hours` and drop `credit_for`.)

- [ ] **Step 6: gettext + run tests**

```bash
mix gettext.extract --merge
mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs
```
Fill FR/EN for new msgids ("Heures"→"Heures"/"Hours", "Modules", "Leçons"→"Leçons"/"Lessons", "Horaire annuel"→"Horaire annuel"/"Annual hours", "Cible modules"→"Cible modules"/"Module target", "Cible leçons", "Save targets"→"Enregistrer les cibles"/"Save targets", "Crédit h"→"Crédit h"/"Credit h", "Could not save targets", "Could not save credit"). Then full `mix test` → 0 failures; `mix compile --warnings-as-errors` clean.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web priv/gettext test/teacher_assistant_web
git commit -m "feat(fiche): quota header + inline context targets & per-module credit editors"
```

---

### Task 5: `SetupLive` — seed context targets at creation

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/setup_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/setup_live_test.exs` (extend if present; else add a focused test)

**Interfaces:**
- Consumes: `create_teaching_context/3` (already forwards the three target attrs after Task 1).

- [ ] **Step 1: Write failing test** — assert that submitting the setup form with the three targets creates a context carrying them. Mirror the existing setup test's submission; add `annual_hours`, `target_module_count`, `target_lesson_count` to the params and assert on the created context via `Academics.list_teaching_contexts/2`.

```elixir
  test "setup persists annual hours and count targets", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/teacher/setup")
    view
    |> form("#setup-form", %{setup: setup_params(%{"annual_hours" => "100", "target_module_count" => "4", "target_lesson_count" => "21"})})
    |> render_submit()
    # fetch the created context and assert targets (adapt to how the test obtains ws/year)
  end
```

> Adapt `setup_params/1` and context retrieval to the existing setup test's helpers. If no setup test file exists, create one modeled on `fiche_live_test.exs`'s conn setup; the assertion intent is that the three targets round-trip through `create_teaching_context/3`.

- [ ] **Step 2: Run — expect fail** (targets not threaded).

- [ ] **Step 3: Thread the targets through `save`**

In `setup_live.ex` `handle_event("save", ...)`, extend the `create_teaching_context` attrs:

```elixir
           Academics.create_teaching_context(ws, year, %{
             subject: p["subject"],
             level: p["level"],
             subsystem: String.to_existing_atom(p["subsystem"]),
             weekly_hours: wh,
             annual_hours: parse_decimal(p["annual_hours"]),
             target_module_count: parse_int(p["target_module_count"]),
             target_lesson_count: parse_int(p["target_lesson_count"])
           })
```

Add the same `parse_decimal/1` and `parse_int/1` private helpers (blank/invalid → nil) as in Task 4. Add three optional number inputs to the render, after the weekly-hours input:

```heex
<.input type="number" field={@form[:annual_hours]} label={gettext("Horaire annuel")} step="0.5" />
<.input type="number" field={@form[:target_module_count]} label={gettext("Cible modules")} />
<.input type="number" field={@form[:target_lesson_count]} label={gettext("Cible leçons")} />
```

Give the setup `<.form>` `id="setup-form"` if it lacks one (the test selects it).

- [ ] **Step 4: gettext + run — expect pass**

```bash
mix gettext.extract --merge
mix test test/teacher_assistant_web/live/teacher/setup_live_test.exs
```
(The FR/EN for "Horaire annuel"/"Cible modules"/"Cible leçons" were already added in Task 4; confirm they resolve.) Then full `mix test` → 0 failures; `mix compile --warnings-as-errors` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/setup_live.ex priv/gettext test/teacher_assistant_web/live/teacher/setup_live_test.exs
git commit -m "feat(setup): enter annual hours + module/lesson targets at context creation"
```

---

## Self-Review

**Spec coverage:**
- §1 data model (3 context targets + module credit) → Task 1. ✅
- §2 pure `Quota` (context + per-module, default-bucket exclusion, `:lesson` filter, nil-safety) → Task 2. ✅
- §3 UI: FicheLive quota header + inline targets + per-module credit → Task 4; SetupLive targets → Task 5. ✅
- §4 domain API (`update_teaching_context/3`, module credit update) → Task 3. ✅
- §5 behavior (advisory, nil hides bar, default bucket excluded) → enforced in Task 2 (calc) + Task 4 (render `:if` guards). ✅
- §6 testing (Quota pure, resource accepts, ownership, FicheLive render/persist, SetupLive round-trip, Coverage non-regression) → across Tasks 1–5; `Coverage` untouched so its test stands. ✅

**Placeholder scan:** No "TBD"/"add validation"/"similar to". The test-helper NOTES (Task 1 credit assertion placement, Task 4/5 setup-binding adaptation) point at real per-file specifics to match, not deferred work.

**Type consistency:** `Quota.summarize/2` map keys (`planned_hours`, `annual_hours`, `hours_ratio`, `module_count`, `target_module_count`, `lesson_count`, `target_lesson_count`, `per_module` of `%{module_id, planned, credit, ratio}`) are identical between Task 2's implementation, its test, and Task 4's render. `update_teaching_context/3` (id, ws, attrs) and `update_module_credit/2` (module, credit) signatures match between Task 3 and their callers in Task 4. `parse_decimal/1`/`parse_int/1` defined in both Task 4 and Task 5 (same shape; each file gets its own copy — acceptable, they're 3-line view helpers, not domain logic). Accept-list additions in Task 1 are what let `create_teaching_context/3` (Task 5) and `update_teaching_context/3` (Task 3) persist the targets.
