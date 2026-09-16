# P2.3 — Bulletins & Statistics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the Francophone séquentiel bulletin de notes and Conseil-de-Classe statistics for a school class — cross-subject moyenne générale (coefficient-weighted), rank, mention, class stats, and distinction rolls — rendered on screen and printable to A4, admin-gated.

**Architecture:** One new field (`TeachingContext.coefficient`). A new pure module `Academics.Bulletins` computes the whole class's bulletins from plain data (no DB), reusing the per-subject average formula extracted from `Academics.Marks`. `Academics` gains a loader that assembles `{students, subjects+marks+coefficients}` for a class+séquence. Two admin-gated LiveViews (class results, individual bulletin) and a print controller (single + whole-class) render it. Nothing is persisted — a bulletin is a live projection of marks + coefficients.

**Tech Stack:** Elixir/Phoenix LiveView, Ash 3 + AshPostgres, Decimal for /20 arithmetic, daisyUI "Tableau" theme, gettext FR/EN.

**Spec:** `docs/superpowers/specs/2026-07-05-p2-3-bulletins-statistics-design.md`

## Global Constraints

- **Never bare `:atom` attributes** — always an `Ash.Type.Enum` module (project rule). (No new enums are needed in P2.3.)
- Resource house style: `use Ash.Resource, otp_app: :teacher_assistant, domain: TeacherAssistant.Academics, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; `policy always() do authorize_if always() end`; `uuid_v7_primary_key :id`; `timestamps()`.
- All /20 arithmetic uses `Decimal` (never floats); `Marks`/`Bulletins` are pure — no `Ash`/`Repo` calls inside them.
- **Pass mark 10/20; mention bands 10/12/14/16/18 (top = Excellent)** — reuse `Marks.mention/1`, do not reimplement.
- **Moyenne générale = Σ(moyenne_matière × coef) ÷ Σ(coef)** over graded subjects only; a subject with a nil average is excluded from BOTH numerator and Σ(coef) and never counts as 0.
- **Distinction default thresholds: Tableau d'honneur ≥ 12, Encouragements ≥ 14, Félicitations ≥ 16**, each additionally gated on *every graded subject average ≥ 10*; a student is placed in the single highest roll they qualify for.
- Context functions call Ash with `authorize?: false` and return tagged tuples; never leak raw Ash errors to the UI.
- Every admin mutation/page is double-gated: `Permissions.admin?/1` in the UI AND re-checked server-side; every record lookup scoped to the current workspace (`fetch_owned_class_group/2`); enrollment/student resolved from the class's own roster, never a raw id.
- Module-level gettext = `use Gettext, backend: TeacherAssistantWeb.Gettext`; LiveViews/controllers get it via `use TeacherAssistantWeb`. All user-facing strings wrapped in gettext; extraction + FR/EN fill happens in the final task only.
- Every task ends with `mix precommit` green (compile --warnings-as-errors, deps.unlock --unused, format, full test suite). Commit any `mix format` reflows of earlier-task files.
- Branch: `feat/p2-3-bulletins` off `main`.
- Migrations: `mix ash.codegen <name>` then `mix ecto.migrate`; verify the migration is additive.
- Known pre-existing flake: an async email-fixture collision fails the full suite ~1 in 3 runs (always passes in isolation / on rerun). If a full-suite run fails only on that, rerun to confirm; it is not your regression.

---

### Task 1: `TeachingContext.coefficient` field + Assignments API

**Files:**
- Modify: `lib/teacher_assistant/academics/teaching_context.ex`
- Modify: `lib/teacher_assistant/academics/assignments.ex`
- Create: `priv/repo/migrations/<timestamp>_p2_3_coefficient.exs` (via codegen)
- Test: `test/teacher_assistant/academics/assignments_test.exs` (extend)

**Interfaces:**
- Produces: `TeachingContext.coefficient :: Decimal` (`allow_nil?: false`, `default: Decimal.new(1)`, public; in `create` + `update` accept lists). `Assignments.assign/3` reads `:coefficient` from attrs (default `Decimal.new(1)`). New `Assignments.set_coefficient(%TeachingContext{}, decimal_or_string) :: {:ok, %TeachingContext{}} | {:error, :invalid_coefficient}` — parses a positive decimal, rejects ≤ 0 / non-numeric.

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant/academics/assignments_test.exs`:

```elixir
  describe "coefficient (P2.3)" do
    test "assign accepts a coefficient; defaults to 1", ctx do
      %{head: head, cg: cg} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})
      assert Decimal.equal?(tc.coefficient, Decimal.new(4))

      other = TeacherFixtures.user_fixture()
      {:ok, _} = add_active_member(ctx.school, head, other)
      {:ok, tc2} = Assignments.assign(cg, other, %{subject: "Anglais"})
      assert Decimal.equal?(tc2.coefficient, Decimal.new(1))
    end

    test "set_coefficient updates a valid positive value", ctx do
      %{head: head, cg: cg} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, tc} = Assignments.set_coefficient(tc, "3")
      assert Decimal.equal?(tc.coefficient, Decimal.new(3))
    end

    test "set_coefficient rejects zero, negative and non-numeric", ctx do
      %{head: head, cg: cg} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
      assert {:error, :invalid_coefficient} = Assignments.set_coefficient(tc, "0")
      assert {:error, :invalid_coefficient} = Assignments.set_coefficient(tc, "-2")
      assert {:error, :invalid_coefficient} = Assignments.set_coefficient(tc, "abc")
    end
  end
```

(The existing `assignments_test.exs` setup provides `head`, `school`, `cg` and an `add_active_member/3` helper — reuse them; adapt names to what the file actually defines.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/academics/assignments_test.exs`
Expected: FAIL (`coefficient` not accepted / `set_coefficient` undefined).

- [ ] **Step 3: Add the attribute**

In `teaching_context.ex`, add to the `attributes` block (near `weekly_hours`):

```elixir
    attribute :coefficient, :decimal,
      allow_nil?: false,
      default: Decimal.new(1),
      public?: true
```

Add `:coefficient` to both the `create` and `update` accept lists in the `actions` block.

- [ ] **Step 4: Wire Assignments**

In `assignments.ex`, in `assign/3`'s changeset attrs map add:

```elixir
        coefficient: Map.get(attrs, :coefficient, Decimal.new(1)),
```

Add the new function:

```elixir
  def set_coefficient(%TeachingContext{} = tc, value) do
    case parse_coefficient(value) do
      {:ok, dec} ->
        tc
        |> Ash.Changeset.for_update(:update, %{coefficient: dec})
        |> Ash.update(authorize?: false)

      :error ->
        {:error, :invalid_coefficient}
    end
  end

  defp parse_coefficient(%Decimal{} = d), do: if(Decimal.positive?(d), do: {:ok, d}, else: :error)

  defp parse_coefficient(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {dec, ""} -> if Decimal.positive?(dec), do: {:ok, dec}, else: :error
      _ -> :error
    end
  end

  defp parse_coefficient(_), do: :error
```

- [ ] **Step 5: Codegen + migrate**

Run: `mix ash.codegen p2_3_coefficient`
Hand-check the migration only adds the `coefficient` column with a default of `1` (additive, no data movement). Run: `mix ecto.migrate`.

- [ ] **Step 6: Run tests + suite + commit**

Run: `mix test test/teacher_assistant/academics/assignments_test.exs` → PASS, then `mix precommit` → green.

```bash
git add -A && git commit -m "feat(academics): subject coefficient on TeachingContext + Assignments.set_coefficient"
```

---

### Task 2: Coefficient on the assignments panel UI

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex`
- Test: `test/teacher_assistant_web/live/school/class_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Assignments.assign/3` (now reads `:coefficient`), `Assignments.set_coefficient/2`, `Assignments.list_for_class/1`.
- Produces: assign form has a `coefficient` number input; each assignment row shows its coefficient and an inline `#coefficient-{context_id}` form (`phx-change="set_coefficient"`) to edit it. Handlers admin-gated + target resolved from `socket.assigns.assignments`.

- [ ] **Step 1: Write the failing tests**

Append to the "assignments panel" describe in `test/teacher_assistant_web/live/school/class_live_test.exs`:

```elixir
    test "assign sets a coefficient", %{conn: conn, cg: cg, user: head} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{"user_id" => head.id, "subject" => "Maths", "weekly_hours" => "4", "coefficient" => "5"}
      })
      |> render_submit()

      [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)
      assert Decimal.equal?(tc.coefficient, Decimal.new(5))
    end

    test "editing a coefficient inline persists it", %{conn: conn, cg: cg, user: head} do
      {:ok, tc} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> element("#coefficient-#{tc.id}")
      |> render_change(%{"coefficient" => "3"})

      [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)
      assert Decimal.equal?(tc.coefficient, Decimal.new(3))
    end

    test "a non-admin cannot change a coefficient (forged event)", ctx do
      %{school: school, cg: cg, user: head} = ctx
      {:ok, tc} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Maths"})
      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        TeacherAssistant.Accounts.Schools.invite_member(school, head, %{
          email: to_string(other.email), roles: [:teacher]
        })

      {:ok, _} = TeacherAssistant.Accounts.Schools.accept_invitation(inv.token, other)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, other.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "set_coefficient", %{"context-id" => tc.id, "coefficient" => "9"})
      [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)
      assert Decimal.equal?(tc.coefficient, Decimal.new(1))
    end
```

- [ ] **Step 2: Run to verify failure** — `mix test test/teacher_assistant_web/live/school/class_live_test.exs` → FAIL.

- [ ] **Step 3: Implement**

In `class_live.ex`:
- Add a `coefficient` number input to `#assign-form` (label `gettext("Coefficient")`, `name="assignment[coefficient]"`, `value="1"`, `step="0.5"`, `min="0"`); in the `assign` handler pass `coefficient: parse_coef(params["coefficient"])`, where `parse_coef` converts a string to a `Decimal` (default `Decimal.new(1)` on blank/invalid — the Assignments layer re-validates).
- Add a **Coefficient** column to the assignments table; each row renders a small form:

```heex
<form id={"coefficient-#{tc.id}"} phx-change="set_coefficient">
  <input type="hidden" name="context-id" value={tc.id} />
  <input type="number" step="0.5" min="0" name="coefficient"
         value={Decimal.to_string(tc.coefficient)} class="input input-sm w-20"
         disabled={!@admin?} />
</form>
```

- Add the handler (same gating shape as the other class_live handlers):

```elixir
  def handle_event("set_coefficient", %{"context-id" => cid, "coefficient" => value}, socket) do
    with true <- socket.assigns.admin?,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         {:ok, _} <- TeacherAssistant.Academics.Assignments.set_coefficient(tc, value) do
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> reload()}
    else
      {:error, :invalid_coefficient} ->
        {:noreply, put_flash(socket, :error, gettext("Enter a positive coefficient."))}

      _ ->
        {:noreply, socket}
    end
  end
```

(`reload/1` is the existing roster+assignments loader in the file; match its actual name.)

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/live/school/class_live_test.exs && mix precommit
git add -A && git commit -m "feat(school): set + edit subject coefficient on the assignments panel"
```

---

### Task 3: Extract the shared subject-average formula in `Marks`

**Files:**
- Modify: `lib/teacher_assistant/academics/marks.ex`
- Test: `test/teacher_assistant/academics/marks_test.exs` (extend; create if absent)

**Interfaces:**
- Produces: `Marks.subject_average(student_marks, assessments_by_id) :: %Decimal{} | nil` — `student_marks` = `[%{assessment_id, score}]` (one student, one subject/séquence; `score` may be nil); `assessments_by_id` = `%{assessment_id => %{weight: Decimal, max_score: Decimal}}`. Returns the /20 weighted average over non-nil marks, or nil when none. This is the existing `student_average/2` made public + renamed; `summarize/3` now calls it.

- [ ] **Step 1: Write the failing test**

Add to `test/teacher_assistant/academics/marks_test.exs` (create the file with `use ExUnit.Case, async: true` and `alias TeacherAssistant.Academics.Marks` if it doesn't exist):

```elixir
  describe "subject_average/2" do
    test "weights marks and normalizes to /20" do
      assessments = %{
        "a" => %{weight: Decimal.new(1), max_score: Decimal.new(20)},
        "b" => %{weight: Decimal.new(3), max_score: Decimal.new(10)}
      }

      # a: 10/20 → 10 (w1); b: 8/10 → 16/20 (w3) ⇒ (10*1 + 16*3)/4 = 58/4 = 14.5
      marks = [%{assessment_id: "a", score: Decimal.new(10)}, %{assessment_id: "b", score: Decimal.new(8)}]
      assert Decimal.equal?(Marks.subject_average(marks, assessments), Decimal.new("14.5"))
    end

    test "ignores nil scores and returns nil when nothing graded" do
      assessments = %{"a" => %{weight: Decimal.new(1), max_score: Decimal.new(20)}}
      assert Marks.subject_average([%{assessment_id: "a", score: nil}], assessments) == nil
      assert Marks.subject_average([], assessments) == nil
    end
  end
```

- [ ] **Step 2: Run to verify failure** — `mix test test/teacher_assistant/academics/marks_test.exs` → FAIL (`subject_average` undefined).

- [ ] **Step 3: Refactor**

In `marks.ex`, rename the private `student_average/2` to a public `subject_average/2` (identical body), and update the caller inside `summarize/3` from `student_average(...)` to `subject_average(...)`. Add a `@doc`. No behavior change.

- [ ] **Step 4: Run tests + suite + commit**

Run: `mix test test/teacher_assistant/academics/marks_test.exs` and the existing marks-summary LiveView test → PASS; `mix precommit` → green (proves `summarize/3` is unchanged in behavior).

```bash
git add -A && git commit -m "refactor(academics): expose Marks.subject_average for reuse by Bulletins"
```

---

### Task 4: `Academics.Bulletins` pure engine

**Files:**
- Create: `lib/teacher_assistant/academics/bulletins.ex`
- Test: `test/teacher_assistant/academics/bulletins_test.exs`

**Interfaces:**
- Consumes: `Marks.subject_average/2`, `Marks.mention/1`.
- Produces: `Bulletins.compile(students, subjects) :: map` where
  - `students :: [%{id, sex}]`
  - `subjects :: [%{context_id, label, coefficient :: Decimal, assessments_by_id :: %{id => %{weight, max_score}}, marks :: [%{student_id, assessment_id, score}]}]`
  - returns:
    ```
    %{
      per_student: %{student_id => %{
        subjects: [%{context_id, label, coefficient, average, note_x_coef, subject_rank, class_min, class_max}],
        total_points: Decimal | nil,
        total_coef: Decimal,
        moyenne_generale: Decimal | nil,
        mention: atom | nil,
        rank: integer | nil
      }},
      effectif: integer,
      graded_count: integer,
      class_average: Decimal | nil,
      pass_rate: float,
      highest: Decimal | nil,
      lowest: Decimal | nil,
      by_sex: %{m: %{class_average, pass_rate, graded_count}, f: %{...}},
      distinctions: %{felicitations: [id], encouragements: [id], tableau_honneur: [id]}
    }
    ```
  Rules per Global Constraints: nil-average subjects excluded from moyenne générale; ranks ex-aequo (ties share a rank); distinctions mutually exclusive (highest applicable), gated on all graded subject averages ≥ 10.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant/academics/bulletins_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.BulletinsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Bulletins

  # helper: one subject with a /20 mark per student (max 20, weight 1)
  defp subject(context_id, label, coef, marks) do
    aid = context_id <> "-a"
    %{
      context_id: context_id,
      label: label,
      coefficient: Decimal.new(coef),
      assessments_by_id: %{aid => %{weight: Decimal.new(1), max_score: Decimal.new(20)}},
      marks: Enum.map(marks, fn {sid, score} -> %{student_id: sid, assessment_id: aid, score: score && Decimal.new(score)} end)
    }
  end

  test "moyenne générale is coefficient-weighted over graded subjects" do
    students = [%{id: "s1", sex: :m}]
    subjects = [
      subject("maths", "Maths", "4", [{"s1", "15"}]),
      subject("eps", "EPS", "1", [{"s1", "10"}])
    ]
    r = Bulletins.compile(students, subjects)
    # (15*4 + 10*1) / (4+1) = 70/5 = 14
    assert Decimal.equal?(r.per_student["s1"].moyenne_generale, Decimal.new(14))
    assert Decimal.equal?(r.per_student["s1"].total_points, Decimal.new(70))
    assert Decimal.equal?(r.per_student["s1"].total_coef, Decimal.new(5))
    assert r.per_student["s1"].mention == :bien
  end

  test "a subject with no mark is excluded from the moyenne générale, not counted as 0" do
    students = [%{id: "s1", sex: :f}]
    subjects = [
      subject("maths", "Maths", "4", [{"s1", "12"}]),
      subject("svt", "SVT", "4", [{"s1", nil}])
    ]
    r = Bulletins.compile(students, subjects)
    # only Maths graded ⇒ 12; SVT excluded from Σcoef
    assert Decimal.equal?(r.per_student["s1"].moyenne_generale, Decimal.new(12))
    assert Decimal.equal?(r.per_student["s1"].total_coef, Decimal.new(4))
    svt = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "svt"))
    assert svt.average == nil
  end

  test "ranks students by moyenne générale with ex-aequo" do
    students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :m}, %{id: "s3", sex: :f}]
    subjects = [subject("maths", "Maths", "1", [{"s1", "16"}, {"s2", "16"}, {"s3", "8"}])]
    r = Bulletins.compile(students, subjects)
    assert r.per_student["s1"].rank == 1
    assert r.per_student["s2"].rank == 1
    assert r.per_student["s3"].rank == 3
  end

  test "class stats and gender split over graded students only" do
    students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :f}, %{id: "s3", sex: :f}]
    subjects = [subject("maths", "Maths", "1", [{"s1", "10"}, {"s2", "16"}, {"s3", nil}])]
    r = Bulletins.compile(students, subjects)
    assert r.effectif == 3
    assert r.graded_count == 2
    assert Decimal.equal?(r.class_average, Decimal.new(13))
    assert r.pass_rate == 1.0
    assert Decimal.equal?(r.highest, Decimal.new(16))
    assert Decimal.equal?(r.lowest, Decimal.new(10))
    assert r.by_sex.f.graded_count == 1
    assert Decimal.equal?(r.by_sex.f.class_average, Decimal.new(16))
    # ungraded student is unranked
    assert r.per_student["s3"].rank == nil
    assert r.per_student["s3"].moyenne_generale == nil
  end

  test "per-subject class min/max and subject rank" do
    students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :m}]
    subjects = [subject("maths", "Maths", "1", [{"s1", "18"}, {"s2", "12"}])]
    r = Bulletins.compile(students, subjects)
    m1 = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "maths"))
    assert Decimal.equal?(m1.class_max, Decimal.new(18))
    assert Decimal.equal?(m1.class_min, Decimal.new(12))
    assert m1.subject_rank == 1
    assert Decimal.equal?(m1.note_x_coef, Decimal.new(18))
  end

  test "distinctions: highest applicable roll, gated on all subjects >= 10" do
    students = [%{id: "hi", sex: :m}, %{id: "mid", sex: :m}, %{id: "fail", sex: :f}]
    subjects = [
      subject("maths", "Maths", "1", [{"hi", "17"}, {"mid", "14"}, {"fail", "18"}]),
      subject("fr", "Français", "1", [{"hi", "16"}, {"mid", "15"}, {"fail", "8"}])
    ]
    r = Bulletins.compile(students, subjects)
    # hi: avg 16.5 ⇒ Félicitations; mid: 14.5, all ≥10 ⇒ Encouragements;
    # fail: avg 13 but a subject <10 ⇒ no roll
    assert "hi" in r.distinctions.felicitations
    assert "mid" in r.distinctions.encouragements
    refute "fail" in r.distinctions.tableau_honneur
    refute "fail" in r.distinctions.encouragements
  end
end
```

- [ ] **Step 2: Run to verify failure** — `mix test test/teacher_assistant/academics/bulletins_test.exs` → FAIL (module undefined).

- [ ] **Step 3: Implement**

`lib/teacher_assistant/academics/bulletins.ex`:

```elixir
defmodule TeacherAssistant.Academics.Bulletins do
  @moduledoc """
  Pure, deterministic cross-subject bulletin computation (Francophone /20).
  No database access — operates on plain maps, like `Academics.Marks`. Reuses
  `Marks.subject_average/2` for the per-subject figure so the two never drift.
  """
  alias TeacherAssistant.Academics.Marks

  @pass Decimal.new(10)
  @felicitations Decimal.new(16)
  @encouragements Decimal.new(14)
  @tableau Decimal.new(12)

  def compile(students, subjects) do
    # 1) per (student, subject) average, then per-subject class min/max + rank
    subject_views =
      Enum.map(subjects, fn subj ->
        per_student_avg =
          Map.new(students, fn s ->
            student_marks = Enum.filter(subj.marks, &(&1.student_id == s.id))
            {s.id, Marks.subject_average(student_marks, subj.assessments_by_id)}
          end)

        graded = per_student_avg |> Map.values() |> Enum.reject(&is_nil/1)
        ranks = rank_map(per_student_avg)

        %{
          context_id: subj.context_id,
          label: subj.label,
          coefficient: subj.coefficient,
          per_student_avg: per_student_avg,
          class_min: min_of(graded),
          class_max: max_of(graded),
          ranks: ranks
        }
      end)

    # 2) per-student subject rows + totals + moyenne générale
    per_student_core =
      Map.new(students, fn s ->
        rows =
          Enum.map(subject_views, fn sv ->
            avg = sv.per_student_avg[s.id]

            %{
              context_id: sv.context_id,
              label: sv.label,
              coefficient: sv.coefficient,
              average: avg,
              note_x_coef: avg && Decimal.mult(avg, sv.coefficient),
              subject_rank: sv.ranks[s.id],
              class_min: sv.class_min,
              class_max: sv.class_max
            }
          end)

        graded_rows = Enum.filter(rows, &(&1.average != nil))
        total_coef = sum(Enum.map(graded_rows, & &1.coefficient))
        total_points = sum(Enum.map(graded_rows, & &1.note_x_coef))

        moy =
          if Decimal.equal?(total_coef, Decimal.new(0)),
            do: nil,
            else: Decimal.div(total_points, total_coef)

        {s.id,
         %{
           subjects: rows,
           total_points: if(graded_rows == [], do: nil, else: total_points),
           total_coef: total_coef,
           moyenne_generale: moy,
           mention: Marks.mention(moy),
           rank: nil
         }}
      end)

    # 3) class ranking on moyenne générale
    moy_map = Map.new(per_student_core, fn {id, d} -> {id, d.moyenne_generale} end)
    class_ranks = rank_map(moy_map)
    per_student = Map.new(per_student_core, fn {id, d} -> {id, %{d | rank: class_ranks[id]}} end)

    graded = per_student |> Map.values() |> Enum.map(& &1.moyenne_generale) |> Enum.reject(&is_nil/1)

    %{
      per_student: per_student,
      effectif: length(students),
      graded_count: length(graded),
      class_average: mean(graded),
      pass_rate: pass_rate(graded),
      highest: max_of(graded),
      lowest: min_of(graded),
      by_sex: %{m: sex_stats(students, per_student, :m), f: sex_stats(students, per_student, :f)},
      distinctions: distinctions(students, per_student)
    }
  end

  # --- ex-aequo ranking over a %{id => Decimal | nil} map ---
  defp rank_map(avg_map) do
    ordered =
      avg_map
      |> Enum.reject(fn {_id, a} -> is_nil(a) end)
      |> Enum.sort_by(fn {_id, a} -> a end, &(Decimal.compare(&1, &2) != :lt))

    {ranks, _} =
      Enum.reduce(ordered, {%{}, nil}, fn {id, a}, {acc, prev} ->
        position = map_size(acc) + 1

        rank =
          case prev do
            {pa, pr} -> if Decimal.equal?(pa, a), do: pr, else: position
            nil -> position
          end

        {Map.put(acc, id, rank), {a, rank}}
      end)

    ranks
  end

  defp distinctions(students, per_student) do
    base = %{felicitations: [], encouragements: [], tableau_honneur: []}

    Enum.reduce(students, base, fn s, acc ->
      d = per_student[s.id]
      all_pass? = Enum.all?(d.subjects, fn r -> is_nil(r.average) or gte(r.average, @pass) end)

      cond do
        is_nil(d.moyenne_generale) or not all_pass? -> acc
        gte(d.moyenne_generale, @felicitations) -> prepend(acc, :felicitations, s.id)
        gte(d.moyenne_generale, @encouragements) -> prepend(acc, :encouragements, s.id)
        gte(d.moyenne_generale, @tableau) -> prepend(acc, :tableau_honneur, s.id)
        true -> acc
      end
    end)
  end

  defp prepend(acc, key, id), do: Map.update!(acc, key, &(&1 ++ [id]))

  defp sex_stats(students, per_student, sex) do
    graded =
      students
      |> Enum.filter(&(&1.sex == sex))
      |> Enum.map(&per_student[&1.id].moyenne_generale)
      |> Enum.reject(&is_nil/1)

    %{class_average: mean(graded), pass_rate: pass_rate(graded), graded_count: length(graded)}
  end

  defp gte(a, b), do: Decimal.compare(a, b) != :lt
  defp sum(list), do: Enum.reduce(list, Decimal.new(0), &Decimal.add(&1, &2))
  defp mean([]), do: nil
  defp mean(list), do: Decimal.div(sum(list), Decimal.new(length(list)))
  defp pass_rate([]), do: 0.0
  defp pass_rate(l), do: Enum.count(l, &gte(&1, @pass)) / length(l)
  defp max_of([]), do: nil
  defp max_of(l), do: Enum.reduce(l, &if(Decimal.compare(&1, &2) == :gt, do: &1, else: &2))
  defp min_of([]), do: nil
  defp min_of(l), do: Enum.reduce(l, &if(Decimal.compare(&1, &2) == :lt, do: &1, else: &2))
end
```

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant/academics/bulletins_test.exs && mix precommit
git add -A && git commit -m "feat(academics): Bulletins pure engine — moyenne générale, ranks, stats, distinctions"
```

---

### Task 5: `Academics` loader — assemble bulletin data for a class + séquence

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/bulletin_data_test.exs`

**Interfaces:**
- Consumes: `list_students/1`, `list_teaching_contexts/2` (workspace+year), `list_assessments/2`, `list_marks_for_context_sequence/2`, `Bulletins.compile/2`.
- Produces:
  - `Academics.class_subjects(%ClassGroup{}, %Sequence{}) :: [subject_map]` — one entry per school teaching context of the class (`class_group_id == cg.id and teacher_user_id not nil`), shaped for `Bulletins.compile/2` (context_id, label = subject, coefficient, assessments_by_id, marks), sorted by subject.
  - `Academics.class_results(%ClassGroup{}, %Sequence{}) :: map` — `Bulletins.compile(students, class_subjects(cg, seq))` where `students` = `[%{id, sex}]` from `list_students/1`. Returns `nil` when the class has no school subjects.

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/academics/bulletin_data_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.BulletinDataTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée B"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true
      })

    [term | _] = Academics.build_default_calendar(year)
    [seq | _] = Academics.list_sequences(year)

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})
    {:ok, a} = Academics.create_assessment(tc, seq, %{label: "D1", weight: Decimal.new(1), max_score: Decimal.new(20)})
    _ = term
    %{school: school, year: year, seq: seq, cg: cg, tc: tc, a: a}
  end

  test "class_subjects shapes each context with coefficient, assessments and marks", ctx do
    %{cg: cg, seq: seq, tc: tc} = ctx
    [subj] = Academics.class_subjects(cg, seq)
    assert subj.context_id == tc.id
    assert subj.label == "Maths"
    assert Decimal.equal?(subj.coefficient, Decimal.new(4))
    assert map_size(subj.assessments_by_id) == 1
  end

  test "class_results computes a bulletin for the séquence", ctx do
    %{cg: cg, seq: seq, tc: tc, a: a} = ctx
    [student] = Academics.list_students(cg)
    :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(15)}])

    r = Academics.class_results(cg, seq)
    assert r.effectif == 1
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(15))
    _ = tc
  end

  test "class_results is nil when the class has no subjects", ctx do
    {:ok, cg2} = Academics.create_class_group(ctx.school, ctx.year, %{label: "6e B", level: "6ème"})
    assert Academics.class_results(cg2, ctx.seq) == nil
  end
end
```

(Check `build_default_calendar/1` and `upsert_marks/2` signatures against `academics.ex` — the setup must produce at least one `Sequence` and let marks be written. If `create_assessment/3` or `upsert_marks/2` differ, mirror how `marks_summary_live_test.exs` / existing marks tests build them.)

- [ ] **Step 2: Run to verify failure** — FAIL (`class_subjects`/`class_results` undefined).

- [ ] **Step 3: Implement**

Add to `academics.ex` (near the marks helpers). Ensure `alias TeacherAssistant.Academics.Bulletins` is present:

```elixir
  def class_subjects(%ClassGroup{id: cg_id}, %Sequence{} = seq) do
    TeachingContext
    |> Ash.Query.filter(class_group_id == ^cg_id and not is_nil(teacher_user_id))
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn tc ->
      assessments = list_assessments(tc, seq)

      %{
        context_id: tc.id,
        label: tc.subject,
        coefficient: tc.coefficient,
        assessments_by_id:
          Map.new(assessments, fn a -> {a.id, %{weight: a.weight, max_score: a.max_score}} end),
        marks:
          list_marks_for_context_sequence(tc, seq)
          |> Enum.map(fn m -> %{student_id: m.student_id, assessment_id: m.assessment_id, score: m.score} end)
      }
    end)
  end

  def class_results(%ClassGroup{} = cg, %Sequence{} = seq) do
    case class_subjects(cg, seq) do
      [] ->
        nil

      subjects ->
        students = list_students(cg) |> Enum.map(fn s -> %{id: s.id, sex: s.sex} end)
        TeacherAssistant.Academics.Bulletins.compile(students, subjects)
    end
  end
```

(Drop the `tap/2` line if it reads awkwardly — it's only there to keep `cg` bound; the function needs only `cg_id`. Prefer matching `%ClassGroup{id: cg_id}` and removing the unused `cg` binding.)

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant/academics/bulletin_data_test.exs && mix precommit
git add -A && git commit -m "feat(academics): class_subjects/class_results loader for bulletins"
```

---

### Task 6: Class results view — `/school/classes/:id/results`

**Files:**
- Create: `lib/teacher_assistant_web/live/school/results_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route in `:school_workspace`), `lib/teacher_assistant_web/live/school/class_live.ex` (add "Résultats & bulletins" link)
- Test: `test/teacher_assistant_web/live/school/results_live_test.exs`

**Interfaces:**
- Consumes: `Academics.class_results/2`, `fetch_owned_class_group/2`, `current_academic_year/1`, `list_sequences/1`, `Permissions.admin?/1`.
- Produces: DOM contract — `#class-results`, séquence switcher `#results-seq-select` (`phx-change="select_seq"`), stats strip, distinction lists, ranked `#results-table` with rows linking to `~p"/school/classes/#{cg}/students/#{enrollment_id}/bulletin?seq=#{seq}"`. Non-admin members → redirect `/school`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/school/results_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.ResultsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée R"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true
      })

    _ = Academics.build_default_calendar(year)
    [seq | _] = Academics.list_sequences(year)
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})
    {:ok, a} = Academics.create_assessment(tc, seq, %{label: "D1", weight: Decimal.new(1), max_score: Decimal.new(20)})
    [student] = Academics.list_students(cg)
    :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(15)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, student: student, head: head}
  end

  test "renders the ranked results with the moyenne générale", %{conn: conn, cg: cg} do
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/results")
    assert html =~ "Awa"
    assert html =~ "15"
  end

  test "cross-school class id redirects", %{conn: conn, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, os} = Schools.create_school(other, %{name: "Autre"})
    {:ok, oy} = Academics.create_academic_year(os, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ocg} = Academics.create_class_group(os, oy, %{label: "6e Z", level: "6ème"})
    _ = head
    assert {:error, {:live_redirect, %{to: "/school/classes"}}} = live(conn, ~p"/school/classes/#{ocg.id}/results")
  end

  test "a non-admin member is redirected to /school", %{conn: conn, school: school, cg: cg, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})
    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/classes/#{cg.id}/results")
  end
end
```

- [ ] **Step 2: Run to verify failure** — route/view missing.

- [ ] **Step 3: Implement**

`School.ResultsLive` — mirror `School.ClassLive`'s mount guard and `MarksSummaryLive`'s séquence-switch pattern:

```elixir
defmodule TeacherAssistantWeb.School.ResultsLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Permissions

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.admin?(scope),
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []
      {:ok, assign(socket, cg: cg, sequences: sequences) |> select_seq(nil)}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_params(params, _uri, socket), do: {:noreply, select_seq(socket, params["seq"])}

  def handle_event("select_seq", %{"seq" => seq_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/school/classes/#{socket.assigns.cg.id}/results?seq=#{seq_id}")}
  end

  defp select_seq(socket, seq_id) do
    seq = Enum.find(socket.assigns.sequences, &(&1.id == seq_id)) || List.first(socket.assigns.sequences)
    results = if seq, do: Academics.class_results(socket.assigns.cg, seq)
    roster = Academics.list_roster(socket.assigns.cg)
    assign(socket, seq: seq, results: results, roster: roster)
  end
end
```

Render (daisyUI, `<.page_header>` / `<.stat>` / `<.empty_state>` kit): `#class-results`; `#results-seq-select` (`phx-change="select_seq"`, options from `@sequences`); stats strip from `@results` (class_average, pass_rate, highest, lowest, effectif with `by_sex`); the three distinction lists (map ids to names via `@roster`); `#results-table` with a row per student sorted by rank — name (from roster), moyenne générale, rank, mention badge — each name linking to `~p"/school/classes/#{@cg.id}/students/#{enrollment_id}/bulletin?seq=#{@seq.id}"`. Use `<.empty_state>` when `@seq == nil` or `@results == nil`. Format Decimals with a local `fmt/1` (`Decimal.round(2)`); pass_rate as `round(rate*100)%`. Look up each student's enrollment_id from `@roster` (`%{student:, enrollment:}`).

Router: add inside `:school_workspace` (before the `:id` catch-all is fine; distinct path):

```elixir
live "/school/classes/:id/results", School.ResultsLive, :index
```

Class detail (`class_live.ex`): add an admin-only link near the header: `<.link navigate={~p"/school/classes/#{@cg.id}/results"}>{gettext("Résultats & bulletins")}</.link>`.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/live/school/results_live_test.exs && mix precommit
git add -A && git commit -m "feat(school): class results view — stats, distinctions, ranked table"
```

---

### Task 7: Individual bulletin view — `/school/classes/:id/students/:enrollment_id/bulletin`

**Files:**
- Create: `lib/teacher_assistant_web/live/school/bulletin_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex`
- Test: `test/teacher_assistant_web/live/school/bulletin_live_test.exs`

**Interfaces:**
- Consumes: `class_results/2`, `fetch_owned_class_group/2`, `list_roster/1`, `list_sequences/1`, `Permissions.admin?/1`.
- Produces: `#bulletin` with identity header (student name, matricule, class, séquence, effectif), per-subject `#bulletin-subjects` table (subject, coef, note/20, note×coef, cote min–max), totals (total points, total coef, moyenne générale), rank/effectif, mention. Enrollment resolved from the class roster (cross-class/cross-school id → redirect). Non-admin → `/school`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.BulletinLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Bu"})
    {:ok, year} = Academics.create_academic_year(school, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    _ = Academics.build_default_calendar(year)
    [seq | _] = Academics.list_sequences(year)
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa Ngo", sex: :f, matricule: "M-1"})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})
    {:ok, a} = Academics.create_assessment(tc, seq, %{label: "D1", weight: Decimal.new(1), max_score: Decimal.new(20)})
    [%{student: student, enrollment: enr}] = Academics.list_roster(cg)
    :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(15)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, enr: enr, head: head}
  end

  test "renders the student's bulletin", %{conn: conn, cg: cg, enr: enr, seq: seq} do
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?seq=#{seq.id}")
    assert html =~ "Awa Ngo"
    assert html =~ "M-1"
    assert html =~ "Maths"
    assert html =~ "15"
  end

  test "an enrollment from another class is rejected", %{conn: conn, cg: cg, seq: seq, school: school, head: head} do
    {:ok, cg2} = Academics.create_class_group(school, Academics.current_academic_year(school), %{label: "6e B", level: "6ème"})
    {:ok, _} = Academics.add_student(cg2, %{full_name: "Bob", sex: :m})
    [%{enrollment: other_enr}] = Academics.list_roster(cg2)
    _ = head
    assert {:error, {:live_redirect, %{}}} =
             live(conn, ~p"/school/classes/#{cg.id}/students/#{other_enr.id}/bulletin?seq=#{seq.id}")
  end
end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

`School.BulletinLive.mount(%{"id" => id, "enrollment_id" => eid}, ...)`: admin-gate; `fetch_owned_class_group(id, ws)`; resolve the enrollment from `list_roster(cg)` by `enrollment.id == eid` (nil → `push_navigate` to `~p"/school/classes/#{id}/results"`); pick séquence from `params["seq"]` else first; compute `class_results(cg, seq)` and pull `results.per_student[student.id]` for this student's rows/totals/rank; assign the student + effectif for the header. Render `#bulletin` with the identity header, `#bulletin-subjects` table, totals, rank/effectif, mention. Reuse `fmt/1`. Include a print link `~p"/school/classes/#{cg.id}/students/#{eid}/bulletin/print?seq=#{seq.id}"` (route lands in Task 8 — render the anchor now; it 404s until Task 8, acceptable within the branch).

Router: `live "/school/classes/:id/students/:enrollment_id/bulletin", School.BulletinLive, :show` in `:school_workspace`.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs && mix precommit
git add -A && git commit -m "feat(school): individual bulletin view"
```

---

### Task 8: Bulletin print — single + whole-class

**Files:**
- Create: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`
- Create: `lib/teacher_assistant_web/controllers/bulletin_print_html.ex` + `.../bulletin_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (two GET routes in the first browser scope, like the fiche print route), `lib/teacher_assistant_web/live/school/results_live.ex` (whole-class print link), `lib/teacher_assistant_web/live/school/bulletin_live.ex` (single print link if not already added)
- Test: `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`

**Interfaces:**
- Consumes: `Workspaces.scope_for/3`, `fetch_owned_class_group/2`, `list_roster/1`, `list_sequences/1`, `class_results/2` (all workspace/admin-scoped in the controller).
- Produces: `GET /school/classes/:id/students/:enrollment_id/bulletin/print?seq=` → one A4 bulletin; `GET /school/classes/:id/bulletin/print?seq=` → every enrolled student's bulletin, one A4 page each. Admin-gated; non-admin/cross-school → redirect `/school`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.BulletinPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Print"})
    {:ok, year} = Academics.create_academic_year(school, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    _ = Academics.build_default_calendar(year)
    [seq | _] = Academics.list_sequences(year)
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa Ngo", sex: :f, matricule: "M-1"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Bob Eyong", sex: :m})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})
    {:ok, a} = Academics.create_assessment(tc, seq, %{label: "D1", weight: Decimal.new(1), max_score: Decimal.new(20)})
    roster = Academics.list_roster(cg)
    for %{student: s} <- roster, do: Academics.upsert_marks(a, [%{student_id: s.id, score: Decimal.new(14)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, roster: roster, head: head}
  end

  test "single bulletin print shows the school and the student", %{conn: conn, cg: cg, seq: seq, roster: roster} do
    %{enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))
    conn = get(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?seq=#{seq.id}")
    body = html_response(conn, 200)
    assert body =~ "Lycée Print"
    assert body =~ "Awa Ngo"
    assert body =~ "Maths"
  end

  test "whole-class print includes every enrolled student", %{conn: conn, cg: cg, seq: seq} do
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?seq=#{seq.id}")
    body = html_response(conn, 200)
    assert body =~ "Awa Ngo"
    assert body =~ "Bob Eyong"
  end

  test "a non-admin member is redirected", %{school: school, cg: cg, seq: seq, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})
    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?seq=#{seq.id}")
    assert redirected_to(conn) == "/school"
  end
end
```

(Clean up that third test's `invite_member` inviter argument when writing it — the inviter is the head from the setup context; thread `head` through the setup return and pass it directly. The convoluted `then/2` chain above is a placeholder — replace with `Schools.invite_member(school, head, %{...})`.)

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

`bulletin_print_controller.ex` — mirror `fiche_print_controller.ex`'s user/scope resolution (`conn.assigns[:current_user] || load_user(get_session(conn, :user_id))`, `Workspaces.scope_for/3`), then **require `Permissions.admin?(scope)`** and `current_workspace_type == :school`; on any failure `redirect(conn, to: ~p"/school")`.

- `show/2` (`:id`, `:enrollment_id`, `seq`): `fetch_owned_class_group`; resolve enrollment from `list_roster`; pick séquence; `class_results(cg, seq)`; render `:show` with `put_layout(false)` + `put_root_layout(false)`, passing `etablissement` (workspace name), the class, séquence, and a **list of one** `{student, enrollment, per_student_data}` bundle.
- `class/2` (`:id`, `seq`): same, but build the bundle list over the whole `list_roster(cg)` (sorted by student name), each with `results.per_student[student.id]`.

Render `show.html.heex` once per bundle (an `Enum.map`/`for` over bundles), each in a `<section class="bulletin-page">` with `page-break-after: always`: bilingual national header (`République du Cameroun — Paix – Travail – Patrie` / `Republic of Cameroon — Peace – Work – Fatherland`), établissement cartouche, identity line (nom, matricule, classe, séquence, sexe, effectif), the per-subject table (matière, coef, note/20, note×coef, cote [min–max]), totals (total points, total coef, moyenne générale), rang/effectif, mention, and blank ruled lines labelled `Appréciation du conseil de classe`, `Décision`, `Visa Professeur Principal`, `Visa Chef d'établissement`. Reuse the A4/print CSS approach from `fiche_print_html/show.html.heex`.

Router (first browser `scope "/"`, next to the fiche print route, NOT in a live_session):

```elixir
get "/school/classes/:id/students/:enrollment_id/bulletin/print", BulletinPrintController, :show
get "/school/classes/:id/bulletin/print", BulletinPrintController, :class
```

Results view: add a **"Imprimer toute la classe"** link → `~p"/school/classes/#{@cg.id}/bulletin/print?seq=#{@seq.id}"` (target `_blank`), shown only when `@seq` and `@results`. Bulletin view: ensure the single-print link points at the `:show` print route.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs && mix precommit
git add -A && git commit -m "feat(school): bulletin print — single + whole class (A4)"
```

---

### Task 9: gettext extract + FR/EN + final gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/{en,fr}/LC_MESSAGES/default.po`

- [ ] **Step 1: Extract** — `mix gettext.extract --merge`

- [ ] **Step 2: Fill translations**

Every new P2.3 msgid gets a non-empty `msgstr` in BOTH locales (FR-authored msgids: `msgstr` = msgid in fr, real English in en; EN-authored: inverse). **No empty msgstr for any new msgid** (P2.1 finding I2 — empty msgstrs leak the wrong language). Keep `matricule` verbatim in both. New strings include (grep the diff for the full set): "Coefficient", "Coefficient updated.", "Enter a positive coefficient.", "Résultats & bulletins", "Moyenne générale", "Rang", "Effectif", "Mention", "Tableau d'honneur", "Encouragements", "Félicitations", "Imprimer toute la classe", "Bulletin de notes", "Total des points", "Total des coefficients", "Appréciation du conseil de classe", "Décision", "Visa Professeur Principal", "Visa Chef d'établissement", and the results/bulletin column headers. Resolve any `#, fuzzy` markers on NEW entries; leave pre-existing ones.

- [ ] **Step 3: Full gate** — `mix precommit` → green. Include any format-reflowed files.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore(i18n): extract + EN/FR translations for P2.3 bulletins"
```

---

## Final verification (after all tasks)

1. `mix precommit` on the branch tip — green (rerun once if only the known email-fixture flake fails).
2. Manual smoke: school → class detail → assignments panel, set Maths coef 4 + Anglais coef 1 → enter marks for both subjects across a séquence → class results view shows ranked moyennes générales + distinction rolls + gender split → open a student's bulletin → print single (school name + moyenne générale) → "Imprimer toute la classe" → one A4 page per student. Confirm a subject with no marks leaves the moyenne générale unpenalized.
3. Final whole-branch review (requesting-code-review), then finishing-a-development-branch.
