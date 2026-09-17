# Combined Courses (Phase 2 + Timetable) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one teacher record marks, attendance and progression **once** across several classes taught together (e.g. 1ère MACO+MENU+ELEQ maths), while each class stays separate for enrollment, bulletins and ranking.

**Architecture:** A new `CombinedCourse` groups several per-class `TeachingContext`s taught by the same teacher for the same subject. A **teaching unit** is `context.combined_course || context`. The one structural change is that a `ProgressionPlan` belongs to a *unit* (context OR course) instead of only a context — so a combined course shares one fiche/coverage/log. Marks and attendance stay per-student/per-class in the DB; combined courses only give a **union recording surface** (one grid across the linked classes, each write routed to the student's own class). The combined timetable places one logical slot across the linked classes.

**Tech Stack:** Elixir/Ash 3.x + AshPostgres, Phoenix LiveView 1.1, Gettext (FR default), DaisyUI/Tailwind.

**Spec:** `docs/superpowers/specs/2026-09-17-school-subjects-teaching-model-design.md` §4 (Combined courses). Timetable-for-combined (item A) extends §4's "Timetable slot coordination".

## Global Constraints

- **Ash resource pattern** (match `lib/teacher_assistant/academics/class_group.ex`): `authorizers: [Ash.Policy.Authorizer]`, `policy always() do authorize_if always() end`, `uuid_v7_primary_key :id`, `timestamps()`, `defaults [...]` actions. Context modules call `Ash.create/update(authorize?: false)` and return tagged tuples.
- **Never a bare `:atom` attribute** — use an `Ash.Type.Enum`.
- **Classes stay the unit of record.** `Mark`(assessment+student), `AttendanceEntry`(enrollment+period+context), bulletins and ranking are per-student/per-class and MUST NOT change semantics. A combined course never merges students across classes in the DB.
- **Teaching unit:** `unit(context) = context.combined_course || context`. A `ProgressionPlan` belongs to **exactly one** unit (a context OR a course) — enforced in the context layer.
- **Linking rule:** every `TeachingContext` in a `CombinedCourse` shares the course's `teacher_user_id` and `subject`; each keeps its own `class_group_id`; a context belongs to ≤1 course.
- **`TeachingContext.subject` stays a denormalized string** (from Phase 1) — do not add a subject FK.
- Bilingual FR/EN via `gettext`, default locale `fr`; gettext extract + FR fill is the final task.
- Verify with `mix test` (the memory notes `mix precommit` does not gate on warnings). Every task ends green; the full suite must stay green (Phase-1 count is 590).
- Existing helpers to reuse: `Academics.fetch_owned_teaching_context/2`, `Academics.create_progression_plan/2`, `Academics.list_progression_plans/1`, `Academics.coverage_for_plan/1`, `Assignments.list_for_user/3` & `list_for_class/1`, `Academics.list_contexts_for_scope/1`, `Attendance.period_roll/3`, `Timetables.place_slot/2`.

---

## PHASE 2a — Model + shared progression

### Task 1: `CombinedCourse` resource

**Files:**
- Create: `lib/teacher_assistant/academics/combined_course.ex`
- Modify: `lib/teacher_assistant/academics.ex` (register `resource CombinedCourse`)
- Test: `test/teacher_assistant/academics/combined_course_test.exs`
- Migration: `mix ash.codegen add_combined_courses`

**Interfaces:**
- Produces `TeacherAssistant.Academics.CombinedCourse` with attributes `subject:string (required)`, `label:string (required)`, `workspace_id`, `academic_year_id`, `teacher_user_id`. `has_many :teaching_contexts`. Actions `:read, :destroy, create: [:subject, :label, :workspace_id, :academic_year_id, :teacher_user_id], update: [:label]`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/combined_course_test.exs
defmodule TeacherAssistant.Academics.CombinedCourseTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.{Academics, TeacherFixtures}

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    %{head: head, ws: ws, year: year}
  end

  test "creates a combined course", %{head: head, ws: ws, year: year} do
    {:ok, c} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{subject: "Mathématiques", label: "Maths · 1A MACO+MENU", workspace_id: ws.id, academic_year_id: year.id, teacher_user_id: head.id})
      |> Ash.create(authorize?: false)

    assert c.subject == "Mathématiques"
    assert c.teacher_user_id == head.id
  end
end
```

- [ ] **Step 2: Run it, verify it fails** — `mix test test/teacher_assistant/academics/combined_course_test.exs` → FAIL (module undefined).

- [ ] **Step 3: Create the resource** (mirror `ClassGroup`)

```elixir
# lib/teacher_assistant/academics/combined_course.ex
defmodule TeacherAssistant.Academics.CombinedCourse do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "combined_courses"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:subject, :label, :workspace_id, :academic_year_id, :teacher_user_id],
      update: [:label]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :teacher, TeacherAssistant.Accounts.User do
      source_attribute :teacher_user_id
      define_attribute? false
      allow_nil? false
      public? true
    end

    has_many :teaching_contexts, TeacherAssistant.Academics.TeachingContext
  end
end
```

Note: `teacher_user_id` needs an explicit attribute because `define_attribute? false` is used above only when the column is created by the belongs_to. To match `TeachingContext`'s style, add `attribute :teacher_user_id, :uuid, allow_nil?: false, public?: true` in `attributes` and keep `define_attribute? false` on the relationship. (Copy exactly how `TeachingContext` wires `teacher`.)

- [ ] **Step 4: Register in the domain** — in `lib/teacher_assistant/academics.ex` `resources do … end`, add `resource CombinedCourse` after `resource TeachingContext`.

- [ ] **Step 5: Migration** — `mix ash.codegen add_combined_courses` then `mix ash.migrate`; confirm the `combined_courses` table + FKs.

- [ ] **Step 6: Run the test → PASS.**

- [ ] **Step 7: Commit** — `git add … && git commit -m "feat: CombinedCourse resource"`.

---

### Task 2: `TeachingContext.combined_course_id`

**Files:**
- Modify: `lib/teacher_assistant/academics/teaching_context.ex` (add nullable `belongs_to :combined_course` + accept in `:update`)
- Test: `test/teacher_assistant/academics/teaching_context_combined_test.exs`
- Migration: `mix ash.codegen add_context_combined_course`

**Interfaces:** Produces `TeachingContext.combined_course_id` (nullable uuid) + `belongs_to :combined_course`. `:update` action accepts `:combined_course_id`.

- [ ] **Step 1: Failing test** — assert a context can be stamped with a `combined_course_id` via `update`, and `nil` means solo.

```elixir
# test/teacher_assistant/academics/teaching_context_combined_test.exs — key assertion
test "a context can be linked to a combined course", ctx do
  # build a class + assignment (use Assignments.assign) and a CombinedCourse, then:
  {:ok, updated} = tc |> Ash.Changeset.for_update(:update, %{combined_course_id: course.id}) |> Ash.update(authorize?: false)
  assert updated.combined_course_id == course.id
end
```

(Set up `ws`/`year`/`cg`/`tc` via the same fixtures as `assignments_test.exs`, and a `CombinedCourse` as in Task 1.)

- [ ] **Step 2: Run → FAIL** (`:update` rejects `combined_course_id`).

- [ ] **Step 3: Implement** — in `teaching_context.ex`:
  - In `attributes`, add `attribute :combined_course_id, :uuid, allow_nil?: true, public?: true`.
  - In `relationships`, add:
    ```elixir
    belongs_to :combined_course, TeacherAssistant.Academics.CombinedCourse do
      source_attribute :combined_course_id
      define_attribute? false
      allow_nil? true
      public? true
    end
    ```
  - Add `:combined_course_id` to the `update:` accept list of the existing `defaults`/update action.
  - `postgres do references do reference :combined_course, on_delete: :nilify end end` so splitting/deleting a course nilifies the link.

- [ ] **Step 4: Migration** — `mix ash.codegen add_context_combined_course` + `mix ash.migrate`.

- [ ] **Step 5: Run → PASS.**

- [ ] **Step 6: Commit.**

---

### Task 3: `ProgressionPlan` belongs to a teaching unit

**Files:**
- Modify: `lib/teacher_assistant/academics/progression_plan.ex` (add nullable `combined_course_id`; make `teaching_context_id` nullable)
- Modify: `lib/teacher_assistant/academics.ex` (`create_progression_plan` variant + owner validation)
- Test: `test/teacher_assistant/academics/progression_plan_unit_test.exs`
- Migration: `mix ash.codegen add_plan_combined_course`

**Interfaces:** Produces `ProgressionPlan.combined_course_id` (nullable) with `teaching_context_id` now nullable; a plan has exactly one owner. Produces `Academics.create_course_plan(%CombinedCourse{}, attrs) → {:ok, %ProgressionPlan{}}`.

- [ ] **Step 1: Failing test**

```elixir
# key assertions
test "a plan can belong to a combined course", %{course: course} do
  {:ok, plan} = Academics.create_course_plan(course, %{title: "Maths"})
  assert plan.combined_course_id == course.id
  assert is_nil(plan.teaching_context_id)
end

test "exactly one owner is required", %{ws: ws, year: year} do
  assert {:error, :no_owner} =
           ProgressionPlanOwner.validate(%{teaching_context_id: nil, combined_course_id: nil})
end
```

(Prefer enforcing "exactly one owner" in the context function `create_course_plan` / `create_progression_plan`, not a DB check-constraint — keep it a context-layer rule per the spec. The second test can instead assert `create_progression_plan` still requires a context and `create_course_plan` requires a course.)

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement**
  - In `progression_plan.ex`: make `teaching_context_id` nullable (`allow_nil? true` on the belongs_to and the attribute if present); add `attribute :combined_course_id, :uuid, allow_nil?: true, public?: true` + `belongs_to :combined_course` (nullable, `define_attribute? false`). Add both to the create/update accept lists.
  - In `academics.ex`, add:
    ```elixir
    def create_course_plan(%CombinedCourse{} = course, attrs) do
      attrs =
        attrs
        |> Map.put(:combined_course_id, course.id)
        |> Map.put(:workspace_id, course.workspace_id)
        |> Map.put_new(:academic_year_id, course.academic_year_id)
        |> Map.put_new(:title, course.subject)

      ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
    end
    ```
    (mirror the existing `create_progression_plan/2` which stamps `teaching_context_id`).

- [ ] **Step 4: Migration** — codegen + migrate; confirm `progression_plans.combined_course_id` nullable and `teaching_context_id` now nullable.

- [ ] **Step 5: Run → PASS; run `mix test test/teacher_assistant/academics/` (no regression on existing plan tests).**

- [ ] **Step 6: Commit.**

---

### Task 4: `Courses` context — combine / split / list units

**Files:**
- Create: `lib/teacher_assistant/academics/courses.ex`
- Test: `test/teacher_assistant/academics/courses_test.exs`

**Interfaces:** Produces `TeacherAssistant.Academics.Courses`:
- `combine([%TeachingContext{}, ...]) → {:ok, %CombinedCourse{}} | {:error, :need_two | :teacher_mismatch | :subject_mismatch | :already_combined}` — validates ≥2 contexts, all same `teacher_user_id` + `subject`, none already in a course; creates the `CombinedCourse` (label auto = `"<subject> · <levels/series joined>"`), stamps `combined_course_id` on each context, and creates the course's shared `ProgressionPlan` via `create_course_plan`.
- `split(%CombinedCourse{}) → :ok` — nilifies `combined_course_id` on member contexts and destroys the course (its plan is destroyed or detached — see step 3).
- `list_units_for_user(ws, year, user) → [unit]` where a unit is `{:course, %CombinedCourse{contexts: [...]}}` or `{:solo, %TeachingContext{}}` — collapses combined contexts into one course entry.

- [ ] **Step 1: Failing test**

```elixir
# test/teacher_assistant/academics/courses_test.exs — key cases
test "combine links contexts and creates one shared plan", ctx do
  {:ok, course} = Courses.combine([tc_maco, tc_menu])
  assert Enum.sort([tc_maco.id, tc_menu.id]) ==
           Enum.sort(Enum.map(Academics.contexts_of_course(course), & &1.id))
  assert [_plan] = Academics.list_progression_plans(ws) |> Enum.filter(& &1.combined_course_id == course.id)
end

test "combine rejects mismatched subject/teacher and <2", ctx do
  assert {:error, :need_two} = Courses.combine([tc_maco])
  assert {:error, :subject_mismatch} = Courses.combine([tc_maco, tc_french])
end

test "split unlinks and removes the course", %{course: course} do
  :ok = Courses.split(course)
  assert Academics.get_teaching_context(tc_maco.id).combined_course_id == nil
end

test "list_units collapses combined contexts into one entry", ctx do
  {:ok, _} = Courses.combine([tc_maco, tc_menu])
  units = Courses.list_units_for_user(ws, year, head)
  assert Enum.count(units, &match?({:course, _}, &1)) == 1
end
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** `courses.ex` with `Ash.create/update/destroy(authorize?: false)`; use `Repo.transaction` for `combine` (create course → update each context → create plan; rollback on any error). On `split`, `Ash.destroy!` the course (the `on_delete: :nilify` from Task 2 clears the contexts' link); explicitly `Ash.destroy!` the course's `ProgressionPlan` **only if empty**, else leave it detached with a flash upstream — for this task, destroy the plan on split (document that a split discards the shared fiche; acceptable for Inc-2 scope). Add tiny helpers `Academics.contexts_of_course/1` and `Academics.get_course/1` as needed.

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Commit.**

---

### Task 5: Teaching-unit resolution (switcher, fiche, coverage)

**Files:**
- Modify: `lib/teacher_assistant/academics.ex` (`list_units_for_scope/1`; `plan_for_context/2`)
- Modify: `lib/teacher_assistant_web/components/layouts.ex` (switcher renders units)
- Modify: `lib/teacher_assistant_web/live/teacher/dashboard_live.ex` (KPIs already per-plan — verify combined shows once)
- Test: `test/teacher_assistant_web/live/teacher/context_switcher_combined_test.exs`

**Interfaces:** Produces `Academics.list_units_for_scope(scope)` returning display units (course rows + solo context rows) built on `Courses.list_units_for_user`; each row exposes `id` (context id to select — for a course, a representative member context) and a `label`. The switcher shows one row per unit; selecting a course row selects its representative context but the fiche/coverage resolve to the course's plan.

- [ ] **Step 1: Failing test** — mount a teacher page for a head who has a combined course; assert the class-switcher renders ONE row labelled with the course label (not one per class).

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement**
  - `list_units_for_scope/1`: like `list_contexts_for_scope/1` but returns collapsed units (reuse `Courses.list_units_for_user`). Provide a `unit_label/1` and `unit_select_id/1`.
  - In `layouts.ex`, change the `@contexts` assign to `@units` (or map units to the existing `context_label`/link shape): render `:for={u <- @units}` with `unit_label(u)` and link to the representative context id. Keep the solo path identical to today.
  - `plan_for_context/2 (ctx, ws)`: if `ctx.combined_course_id`, return the course's plan; else the context's plan. Point the dashboard/coverage plan lookups that key off a context at this helper. (The dashboard already iterates `list_progression_plans/1`, which returns one plan per combined course — verify it shows a single KPI per course; if it double-counts because member contexts still have stale plans, ensure `combine` removed/►migrated member-context plans in Task 4.)

- [ ] **Step 4: Run → PASS; full `mix test`.**

- [ ] **Step 5: Commit.**

---

### Task 6: "Teach together / split" UI in the class Assignments panel

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex` (Assignments panel gains a combine control; admin-gated like the other class mutations)
- Test: add cases to `test/teacher_assistant_web/live/school/class_live_test.exs`

**Interfaces:** From a class's Assignments panel, an admin can pick another class (same subject+teacher assignment) and "teach together" → calls `Courses.combine/1`; a combined assignment shows a "Split" control → `Courses.split/1`. Admin-gated (`Permissions.admin?`), mirroring Phase-1's subject handlers.

- [ ] **Step 1: Failing test** — as an admin with two classes assigned the same teacher+subject, trigger `combine` and assert both contexts share a `combined_course_id`; a non-admin forged event is refused.

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** — add a small form/select listing eligible sibling contexts (same year, same subject, same teacher, not already combined) and `handle_event("teach_together", ...)` / `handle_event("split_course", ...)`, both guarded by `Permissions.admin?(scope)`. Surface tagged errors as flashes. Show the combined label on combined assignment rows.

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Commit.**

---

## PHASE 2b — Record-once marks & attendance

### Task 7: Combined marks — union roster, per-class assessment routing

**Files:**
- Modify: `lib/teacher_assistant/academics.ex` (`combined_assessments_for/2`, `list_union_students/1`)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex` (combined mode)
- Test: `test/teacher_assistant_web/live/teacher/marks_combined_test.exs`

**Interfaces:** When the current context is combined, the marks page shows the **union** of students across the course's classes, grouped by class. Creating an assessment creates one `Assessment` **per member context** (same label/sequence); saving a student's score writes to that student's class's assessment. Each mark still satisfies `Mark.unique_mark [assessment_id, student_id]` and lands on the right bulletin.

- [ ] **Step 1: Failing test** — combined course over MACO+MENU; create an assessment for a sequence; enter a score for a MACO student; assert a `Mark` exists against MACO's context's assessment (not MENU's), and a MENU student's score writes to MENU's assessment.

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement**
  - `combined_assessments_for(course, seq)`: ensure one `Assessment{label, sequence}` per member context (create missing) and return them keyed by `class_group_id`.
  - `list_union_students(course)`: students of every member class, tagged with their `class_group`.
  - `marks_live` mount: if `ctx.combined_course_id`, load the course, the union roster (grouped by class), and per-class assessments; render one grid grouped by class header. On save, for each `{student, score}` route to `assessments_by_class[student.class_group_id]` and upsert (reuse the existing per-student upsert path). Solo mode unchanged.

- [ ] **Step 4: Run → PASS; `mix test test/teacher_assistant_web/live/teacher/` + marks context tests.**

- [ ] **Step 5: Commit.**

---

### Task 8: Combined attendance — one session over the union

**Files:**
- Modify: `lib/teacher_assistant/academics/attendance.ex` (`combined_period_roll/…`)
- Modify: the school attendance LiveView / add a combined entry point
- Test: `test/teacher_assistant/academics/attendance_combined_test.exs`

**Interfaces:** For a combined course, one attendance surface lists the union of the linked classes' rolls for a period/date; recording writes `AttendanceEntry` per enrollment (each in its own class), exactly as today. Reuse `Attendance.period_roll/3` per member class and concatenate (grouped by class).

- [ ] **Step 1: Failing test** — combined course; `combined_period_roll` returns students from both classes; recording an absence for a MENU student creates an `AttendanceEntry` on that enrollment.

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** `combined_period_roll(course, period, date)` = `Enum.flat_map(member_classes, &period_roll(&1, period, date))` grouped by class; wire a combined attendance view (route or a mode on the existing attendance LiveView) that records per-enrollment via the existing record path.

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Commit.**

---

## A — Combined timetable slot

### Task 9: Place one timetable slot across a combined course's classes

**Files:**
- Modify: `lib/teacher_assistant/academics/timetables.ex` (`place_combined_slot/…`, `clear_combined_slot/…`)
- Modify: the school timetable LiveView (`lib/teacher_assistant_web/live/school/timetable_live.ex`) to offer placing a combined course
- Test: `test/teacher_assistant/academics/timetables_combined_test.exs`

**Interfaces:** `Timetables.place_combined_slot(course, day, period)` places a `TimetableSlot` for each member class (referencing that class's context) at the same `day`/`period`, so the combined course occupies one logical cell across its classes; `clear_combined_slot(course, day, period)` clears them. Reuse `place_slot/2` / `clear_slot/3` per member class.

- [ ] **Step 1: Failing test** — placing a combined slot creates one `TimetableSlot` per member class at that day/period, each `unique_cell` satisfied.

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** the two helpers (`Enum.each(member_classes, ...)` over `place_slot`/`clear_slot`) and a minimal UI affordance to place a combined course into the timetable grid. Keep per-class placement working unchanged.

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Commit.**

---

### Task 10: gettext extract + FR fill; full-suite gate

**Files:** `priv/gettext/**` (translations only).

- [ ] **Step 1:** `mix gettext.extract && mix gettext.merge priv/gettext`.
- [ ] **Step 2:** Fill French `msgstr` for every new msgid from Tasks 5–9 (teach-together / split / combined labels / combined marks & attendance / combined timetable). Set English `msgstr` = msgid.
- [ ] **Step 3:** `mix test` — 0 failures.
- [ ] **Step 4:** Commit.

---

## Self-Review

**Spec coverage (§4):** `CombinedCourse` (T1); `TeachingContext.combined_course_id` + linking rule (T2, T4); `ProgressionPlan` unit ownership + nullable `teaching_context_id` (T3); teaching-unit resolution + switcher one-row (T5); teach-together/split (T4 context, T6 UI); record-once marks union + per-student writes (T7); attendance union (T8); timetable coordination = item A (T9). Bulletins/ranking untouched (no task changes `Mark`/bulletin code). ✅

**Type consistency:** `Courses.combine/1 → {:ok, %CombinedCourse{}}`, `split/1 → :ok`, `list_units_for_user/3`; `Academics.create_course_plan/2`, `plan_for_context/2`, `list_units_for_scope/1`, `combined_assessments_for/2`, `list_union_students/1`, `combined_period_roll/3`, `Timetables.place_combined_slot/3` — used consistently across T4–T9. `unit = context.combined_course || context` throughout.

**Known verification points flagged inline:** the `teacher_user_id` attribute wiring on `CombinedCourse` (T1 note); whether `combine` should migrate an existing member-context plan into the course vs create fresh (T4 step 3 — chosen: create the course plan; if a member context already had a plan, T4 must decide — default: keep the course plan and detach/ignore member-context plans, and the dashboard uses `plan_for_context`); the dashboard double-count check (T5). These are called out for the implementer/reviewer.

**Scope note:** B/C/D/E (staff&roles, permissions, config, nav) are separate increments, each needing its own brief design → spec → plan, per the roadmap memory. This plan is Phase 2 + timetable only.
