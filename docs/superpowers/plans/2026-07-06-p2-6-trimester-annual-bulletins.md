# P2.6 Trimester + Annual Bulletins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users view and print bulletins for any period — a séquence, a trimestre (mean of its séquences), or the année (mean of the year's séquences) — by selecting a period on the existing results and bulletin surfaces.

**Architecture:** Extract the ranking/stats/distinctions core of `Bulletins.compile/2` into a shared `Bulletins.aggregate/2` that takes per-student per-subject *averages*. The séquentiel path keeps computing averages from assessments then calls `aggregate`; a period loader means the séquence averages per subject and calls the same `aggregate`, attaching component averages for the bulletin breakdown. A `period=` URL param (replacing `seq=`) drives results_live, bulletin_live, and both print routes.

**Tech Stack:** Elixir, Ash 3 + AshPostgres, Phoenix LiveView, gettext (FR source + EN translations), Decimal for all /20 arithmetic.

## Global Constraints

- All /20 arithmetic uses `Decimal`, never floats. A subject with no average in a period is excluded from BOTH the moyenne-générale numerator and Σcoef (never counted as 0).
- Methodology (docs/domain/04): trimester subject average = mean of the term's séquence subject-averages that exist; annual subject average = mean of the year's séquence subject-averages that exist (`Σ ÷ n`). Moyenne générale = `Σ(subject_avg × coef)/Σ(coef)` over graded subjects. Distinctions: Félicitations ≥16 / Encouragements ≥14 / Tableau d'honneur ≥12, gated on all graded subjects ≥10, mutually exclusive.
- The 6 existing `bulletins_test.exs` séquentiel tests MUST stay green with NO edits — the `aggregate` extraction is behavior-preserving.
- Ash context functions call Ash with `authorize?: false` and return tagged values; never leak raw Ash errors.
- Form-master scoped access (P2.5) is unchanged: every surface still gates the resolved class on `Permissions.admin_or_form_master?/2`; the period only changes what is computed, never who may see it.
- Every new gettext msgid needs a non-empty msgstr in BOTH `fr` and `en`.
- `mix precommit` runs the suite; NOTE its alias flag is misspelled `--warning-as-errors` (a no-op), so warnings do not gate — confirm the full suite passes. The `format` step rewrites files in place; commit any resulting format-only diffs.
- Display a user by `.email` (unchanged from P2.5).

---

### Task 1: Extract `Bulletins.aggregate/2` (behavior-preserving) + `components` on rows

**Files:**
- Modify: `lib/teacher_assistant/academics/bulletins.ex`
- Test: `test/teacher_assistant/academics/bulletins_test.exs` (extend — do NOT edit the 6 existing tests)

**Interfaces:**
- Produces:
  - `Bulletins.aggregate(students, subject_inputs)` where `students = [%{id, sex}]` and
    `subject_inputs = [%{context_id, label, coefficient, per_student_avg: %{student_id => %Decimal{} | nil}, components: %{student_id => map} | nil}]`.
    Returns the same map shape `compile/2` returns today, with each
    `per_student[id].subjects[i]` gaining a `components` field (the subject's
    `components[id]`, or `nil`).
  - `Bulletins.compile(students, subjects)` — unchanged signature and behavior; now builds `subject_inputs` (with `components: nil`) and delegates to `aggregate/2`.

- [ ] **Step 1: Write the failing test for `aggregate/2`**

Add to `test/teacher_assistant/academics/bulletins_test.exs`:

```elixir
  describe "aggregate/2" do
    test "ranks and weights pre-computed subject averages, carrying components" do
      students = [%{id: "s1", sex: :m}, %{id: "s2", sex: :f}]

      inputs = [
        %{
          context_id: "maths",
          label: "Maths",
          coefficient: Decimal.new(4),
          per_student_avg: %{"s1" => Decimal.new(15), "s2" => Decimal.new(9)},
          components: %{
            "s1" => %{sequences: [%{number: 1, average: Decimal.new(14)}, %{number: 2, average: Decimal.new(16)}]},
            "s2" => %{sequences: [%{number: 1, average: Decimal.new(8)}, %{number: 2, average: Decimal.new(10)}]}
          }
        },
        %{
          context_id: "eps",
          label: "EPS",
          coefficient: Decimal.new(1),
          per_student_avg: %{"s1" => Decimal.new(10), "s2" => Decimal.new(12)},
          components: nil
        }
      ]

      r = Bulletins.aggregate(students, inputs)
      # s1: (15*4 + 10*1)/5 = 14 ; s2: (9*4 + 12*1)/5 = 9.6
      assert Decimal.equal?(r.per_student["s1"].moyenne_generale, Decimal.new(14))
      assert Decimal.equal?(r.per_student["s2"].moyenne_generale, Decimal.new("9.6"))
      assert r.per_student["s1"].rank == 1
      assert r.per_student["s2"].rank == 2
      # component passthrough on the maths row
      maths = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "maths"))
      assert [%{number: 1, average: a1}, %{number: 2, average: a2}] = maths.components.sequences
      assert Decimal.equal?(a1, Decimal.new(14)) and Decimal.equal?(a2, Decimal.new(16))
      # nil components on the eps row
      eps = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "eps"))
      assert eps.components == nil
    end
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs`
Expected: FAIL — `aggregate/2` undefined.

- [ ] **Step 3: Refactor `compile/2` to delegate to a new `aggregate/2`**

Replace the body of `compile/2` and add `aggregate/2` in `lib/teacher_assistant/academics/bulletins.ex`. The new `compile/2` builds per-student averages from assessments (the old step 1), then calls `aggregate/2`; `aggregate/2` holds the old steps 1b (class min/max/ranks), 2 (rows/totals/moyenne), and 3 (class ranking + stats + distinctions):

```elixir
  def compile(students, subjects) do
    inputs =
      Enum.map(subjects, fn subj ->
        per_student_avg =
          Map.new(students, fn s ->
            student_marks = Enum.filter(subj.marks, &(&1.student_id == s.id))
            {s.id, Marks.subject_average(student_marks, subj.assessments_by_id)}
          end)

        %{
          context_id: subj.context_id,
          label: subj.label,
          coefficient: subj.coefficient,
          per_student_avg: per_student_avg,
          components: nil
        }
      end)

    aggregate(students, inputs)
  end

  @doc """
  Ranking/stats/distinctions over pre-computed per-subject averages. Shared by the
  séquentiel path (`compile/2`) and the periodic path (trimester/annual), so the
  arithmetic never drifts. `subject_inputs` carry `per_student_avg` (%{id => Decimal | nil})
  and optional per-student `components` for the bulletin breakdown.
  """
  def aggregate(students, subject_inputs) do
    subject_views =
      Enum.map(subject_inputs, fn subj ->
        graded = subj.per_student_avg |> Map.values() |> Enum.reject(&is_nil/1)

        %{
          context_id: subj.context_id,
          label: subj.label,
          coefficient: subj.coefficient,
          per_student_avg: subj.per_student_avg,
          components: subj.components,
          class_min: min_of(graded),
          class_max: max_of(graded),
          ranks: rank_map(subj.per_student_avg)
        }
      end)

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
              class_max: sv.class_max,
              components: sv.components && sv.components[s.id]
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

    moy_map = Map.new(per_student_core, fn {id, d} -> {id, d.moyenne_generale} end)
    class_ranks = rank_map(moy_map)
    per_student = Map.new(per_student_core, fn {id, d} -> {id, %{d | rank: class_ranks[id]}} end)

    graded =
      per_student |> Map.values() |> Enum.map(& &1.moyenne_generale) |> Enum.reject(&is_nil/1)

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
```

Leave `rank_map/1`, `distinctions/2`, `sex_stats/3`, and the numeric helpers unchanged.

- [ ] **Step 4: Run the whole engine test file**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs`
Expected: PASS — the 6 original séquentiel tests AND the new `aggregate/2` test all green (behavior-preserving refactor).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/bulletins.ex test/teacher_assistant/academics/bulletins_test.exs
git commit -m "refactor(bulletins): extract shared aggregate/2 + row components (P2.6)"
```

---

### Task 2: Period loader — `resolve_period/2`, `class_results_for_period/2`, helpers

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/period_results_test.exs` (create)

**Interfaces:**
- Consumes: `Bulletins.aggregate/2` (Task 1); existing `class_subjects/2`, `class_results/2`, `list_sequences/1`, `list_students/1`, `Marks.subject_average/2`.
- Produces:
  - `Academics.list_terms(year)` → `[%Term{}]` with `:sequences` loaded, sorted by `position`.
  - `Academics.resolve_period(year, param)` → `{:sequence, %Sequence{}} | {:trimester, %Term{}} | {:annual, %AcademicYear{}} | nil`. `param` is `"seq:<id>"` / `"trim:<id>"` / `"annee"`; returns nil for anything that does not resolve within `year`.
  - `Academics.period_param(period)` → `"seq:<id>" | "trim:<id>" | "annee"` (inverse of resolve).
  - `Academics.period_kind(period)` → `:sequence | :trimester | :annual`.
  - `Academics.class_results_for_period(cg, period)` → the `Bulletins` result map, or `nil` when the class has no subjects.

- [ ] **Step 1: Write the failing loader tests**

Create `test/teacher_assistant/academics/period_results_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.PeriodResultsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée P"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)
    sequences = Academics.list_sequences(year)
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(1)})
    [student] = Academics.list_students(cg)

    # helper: give the student `score`/20 in séquence `seq` for Maths
    grade = fn seq, score ->
      {:ok, a} =
        Academics.create_assessment(tc, seq, %{
          label: "D",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(score)}])
    end

    %{year: year, cg: cg, sequences: sequences, student: student, grade: grade}
  end

  test "trimester average is the mean of its two séquences", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade} = ctx
    [s1, s2 | _] = seqs
    grade.(s1, 12)
    grade.(s2, 16)

    [term1 | _] = Academics.list_terms(year)
    r = Academics.class_results_for_period(cg, {:trimester, term1})
    data = r.per_student[student.id]
    # (12 + 16) / 2 = 14
    assert Decimal.equal?(data.moyenne_generale, Decimal.new(14))
    maths = Enum.find(data.subjects, &(&1.label == "Maths"))
    assert [%{average: a1}, %{average: a2}] = maths.components.sequences
    assert Decimal.equal?(a1, Decimal.new(12)) and Decimal.equal?(a2, Decimal.new(16))
  end

  test "a partially-graded trimester uses the one séquence present", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade} = ctx
    [s1, _s2 | _] = seqs
    grade.(s1, 11)

    [term1 | _] = Academics.list_terms(year)
    r = Academics.class_results_for_period(cg, {:trimester, term1})
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(11))
  end

  test "annual average is the mean of the graded séquences, with trimester components", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade} = ctx
    [s1, s2, s3 | _] = seqs
    grade.(s1, 10)
    grade.(s2, 12)
    grade.(s3, 8)

    r = Academics.class_results_for_period(cg, {:annual, year})
    # mean of present séquences: (10 + 12 + 8) / 3 = 10
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(10))
    maths = Enum.find(r.per_student[student.id].subjects, &(&1.label == "Maths"))
    # trimester components: T1 = (10+12)/2 = 11 ; T2 = 8 ; T3 = nil
    assert [%{position: 1, average: t1}, %{position: 2, average: t2}, %{position: 3, average: t3}] =
             maths.components.trimesters

    assert Decimal.equal?(t1, Decimal.new(11))
    assert Decimal.equal?(t2, Decimal.new(8))
    assert t3 == nil
  end

  test "class_results_for_period is nil when the class has no subjects", %{year: year} do
    {:ok, school2} = Schools.create_school(TeacherAssistant.TeacherFixtures.user_fixture(), %{name: "Lycée Q"})

    {:ok, y2} =
      Academics.create_academic_year(school2, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(y2)
    {:ok, cg2} = Academics.create_class_group(school2, y2, %{label: "6e Z", level: "6ème"})
    assert Academics.class_results_for_period(cg2, {:annual, y2}) == nil
    _ = year
  end

  test "resolve_period maps params and rejects bad ones", %{year: year, sequences: seqs} do
    [s1 | _] = seqs
    [term1 | _] = Academics.list_terms(year)

    assert {:sequence, got_seq} = Academics.resolve_period(year, "seq:#{s1.id}")
    assert got_seq.id == s1.id
    assert {:trimester, got_term} = Academics.resolve_period(year, "trim:#{term1.id}")
    assert got_term.id == term1.id
    assert {:annual, got_year} = Academics.resolve_period(year, "annee")
    assert got_year.id == year.id
    assert Academics.resolve_period(year, "seq:#{Ecto.UUID.generate()}") == nil
    assert Academics.resolve_period(year, "garbage") == nil

    # round-trips
    assert Academics.period_param({:sequence, s1}) == "seq:#{s1.id}"
    assert Academics.period_param({:trimester, term1}) == "trim:#{term1.id}"
    assert Academics.period_param({:annual, year}) == "annee"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/period_results_test.exs`
Expected: FAIL — `list_terms/1` / `resolve_period/2` / `class_results_for_period/2` undefined.

- [ ] **Step 3: Add `list_terms/1` and the period helpers**

In `lib/teacher_assistant/academics.ex`, ensure `Term` is aliased (it is used elsewhere; add `alias TeacherAssistant.Academics.Term` if missing). Add near `list_sequences/1`:

```elixir
  def list_terms(%AcademicYear{id: year_id}) do
    Term
    |> Ash.Query.filter(academic_year_id == ^year_id)
    |> Ash.Query.load(:sequences)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def period_kind({:sequence, _}), do: :sequence
  def period_kind({:trimester, _}), do: :trimester
  def period_kind({:annual, _}), do: :annual

  def period_param({:sequence, %Sequence{id: id}}), do: "seq:" <> id
  def period_param({:trimester, %Term{id: id}}), do: "trim:" <> id
  def period_param({:annual, _}), do: "annee"

  def resolve_period(%AcademicYear{} = year, "annee"), do: {:annual, year}

  def resolve_period(%AcademicYear{} = year, "seq:" <> id) do
    case Enum.find(list_sequences(year), &(&1.id == id)) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  def resolve_period(%AcademicYear{} = year, "trim:" <> id) do
    case Enum.find(list_terms(year), &(&1.id == id)) do
      nil -> nil
      term -> {:trimester, term}
    end
  end

  def resolve_period(_year, _param), do: nil
```

- [ ] **Step 4: Add `class_results_for_period/2` and its private helpers**

In `lib/teacher_assistant/academics.ex`, near `class_results/2`:

```elixir
  @doc """
  Compiled class bulletins for a period (`{:sequence, seq}` / `{:trimester, term}` /
  `{:annual, year}`), or nil when the class has no subjects. Trimester/annual
  averages are the mean of the constituent séquence subject-averages that exist.
  """
  def class_results_for_period(%ClassGroup{} = cg, {:sequence, %Sequence{} = seq}) do
    class_results(cg, seq)
  end

  def class_results_for_period(%ClassGroup{} = cg, {:trimester, %Term{} = term}) do
    seqs = Enum.sort_by(term.sequences, & &1.position_in_term)
    period_result(cg, seqs, :sequences)
  end

  def class_results_for_period(%ClassGroup{} = cg, {:annual, %AcademicYear{} = year}) do
    seqs = list_sequences(year)
    period_result(cg, seqs, :trimesters)
  end

  # Builds a Bulletins result over a set of séquences. `component_kind` selects the
  # breakdown carried on each subject row: :sequences (per séquence, for trimester)
  # or :trimesters (per term, for annual).
  defp period_result(cg, seqs, component_kind) do
    students = cg |> list_students() |> Enum.map(fn s -> %{id: s.id, sex: s.sex} end)

    # per séquence: %{context_id => %{label, coefficient, per_student_avg}}
    per_seq =
      Enum.map(seqs, fn seq ->
        subjects =
          cg
          |> class_subjects(seq)
          |> Map.new(fn subj ->
            psa =
              Map.new(students, fn s ->
                sm = Enum.filter(subj.marks, &(&1.student_id == s.id))
                {s.id, TeacherAssistant.Academics.Marks.subject_average(sm, subj.assessments_by_id)}
              end)

            {subj.context_id, %{label: subj.label, coefficient: subj.coefficient, per_student_avg: psa}}
          end)

        {seq, subjects}
      end)

    contexts =
      per_seq |> Enum.flat_map(fn {_seq, m} -> Map.keys(m) end) |> Enum.uniq()

    if contexts == [] or students == [] do
      nil
    else
      subject_inputs =
        Enum.map(contexts, fn cid ->
          {label, coef} = context_label_coef(per_seq, cid)

          per_student_avg =
            Map.new(students, fn s ->
              {s.id, mean_present(sequence_values(per_seq, cid, s.id))}
            end)

          components =
            Map.new(students, fn s ->
              {s.id, build_components(component_kind, per_seq, cid, s.id)}
            end)

          %{
            context_id: cid,
            label: label,
            coefficient: coef,
            per_student_avg: per_student_avg,
            components: components
          }
        end)

      Bulletins.aggregate(students, subject_inputs)
    end
  end

  defp context_label_coef(per_seq, cid) do
    {_seq, m} = Enum.find(per_seq, fn {_seq, m} -> Map.has_key?(m, cid) end)
    sub = m[cid]
    {sub.label, sub.coefficient}
  end

  # this subject's per-séquence average for one student, in séquence order (nils dropped)
  defp sequence_values(per_seq, cid, sid) do
    per_seq
    |> Enum.map(fn {_seq, m} -> m[cid] && m[cid].per_student_avg[sid] end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_components(:sequences, per_seq, cid, sid) do
    seqs =
      Enum.map(per_seq, fn {seq, m} ->
        %{number: seq.number, average: m[cid] && m[cid].per_student_avg[sid]}
      end)

    %{sequences: seqs}
  end

  defp build_components(:trimesters, per_seq, cid, sid) do
    trimesters =
      per_seq
      |> Enum.group_by(fn {seq, _m} -> seq.term.position end)
      |> Enum.sort_by(fn {position, _} -> position end)
      |> Enum.map(fn {position, term_seqs} ->
        vals =
          term_seqs
          |> Enum.map(fn {_seq, m} -> m[cid] && m[cid].per_student_avg[sid] end)
          |> Enum.reject(&is_nil/1)

        %{position: position, average: mean_present(vals)}
      end)

    %{trimesters: trimesters}
  end

  defp mean_present([]), do: nil

  defp mean_present(vals) do
    Decimal.div(Enum.reduce(vals, Decimal.new(0), &Decimal.add/2), Decimal.new(length(vals)))
  end
```

NOTE for `:trimesters`, `seq.term.position` must be loaded — `list_sequences/1` already does `Ash.Query.load(:term)`, so it is available on the annual path. (The trimester path uses `:sequences` and does not need `:term`.)

- [ ] **Step 5: Run to verify it passes**

Run: `mix test test/teacher_assistant/academics/period_results_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 6: Confirm the séquentiel path is untouched**

Run: `mix test test/teacher_assistant/academics/bulletin_data_test.exs test/teacher_assistant/academics/bulletins_test.exs`
Expected: PASS (existing loader + engine tests still green).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics/period_results_test.exs
git commit -m "feat(academics): class_results_for_period + resolve_period (P2.6)"
```

---

### Task 3: Results page — period selector + `period=` param

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/results_live.ex`
- Test: `test/teacher_assistant_web/live/school/results_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Academics.list_terms/1`, `resolve_period/2`, `period_param/1`, `class_results_for_period/2`.
- Produces: results page carries `@period` (a period tuple) and `@period_param` (string); the séquence dropdown becomes a period selector; bulletin links + whole-class print link carry `period=<param>`.

- [ ] **Step 1: Write the failing test**

Add to `test/teacher_assistant_web/live/school/results_live_test.exs`:

```elixir
  test "the period selector switches to a trimester and recomputes", %{conn: conn, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/results")
    # séquence 1 is the default; switch to Trimestre 1
    year = TeacherAssistant.Academics.current_academic_year_for_class(cg)
    [term1 | _] = TeacherAssistant.Academics.list_terms(year)

    html =
      view
      |> element("#results-period-form")
      |> render_change(%{"period" => "trim:#{term1.id}"})

    assert html =~ "Awa"
    assert render(view) =~ "period=trim%3A#{term1.id}" or render(view) =~ "period=trim:#{term1.id}"
  end
```

If `Academics.current_academic_year_for_class/1` does not exist, resolve the year in the test via the setup's `school`: replace those two lines with `year = TeacherAssistant.Academics.current_academic_year(ctx_school)` — but simplest is to pull `term1` from the school/year already in the test's `setup`. Adjust to the setup's available bindings; the setup binds `%{conn, school, cg, seq, student, head}`, so use:

```elixir
    year = TeacherAssistant.Academics.current_academic_year(school)
```

and add `school` to the test's parameter map.

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/results_live_test.exs`
Expected: FAIL — no `#results-period-form` / period handling.

- [ ] **Step 3: Rewrite mount + selection to use periods**

In `lib/teacher_assistant_web/live/school/results_live.ex`, replace the séquence machinery. Mount loads the year, builds the period options, and defaults to the first séquence:

```elixir
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []
      terms = if year, do: Academics.list_terms(year), else: []

      {:ok,
       socket
       |> assign(
         cg: cg,
         form_master: Academics.form_master(cg),
         year: year,
         sequences: sequences,
         terms: terms
       )
       |> select_period(nil)}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, select_period(socket, params["period"])}

  def handle_event("select_period", %{"period" => param}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/school/classes/#{socket.assigns.cg.id}/results?period=#{param}")}
  end

  defp select_period(socket, param) do
    year = socket.assigns.year

    period =
      (year && param && Academics.resolve_period(year, param)) ||
        default_period(socket.assigns.sequences)

    results = period && Academics.class_results_for_period(socket.assigns.cg, period)
    roster = Academics.list_roster(socket.assigns.cg)

    assign(socket,
      period: period,
      period_param: period && Academics.period_param(period),
      results: results,
      roster: roster,
      rows: ranked_rows(results, roster)
    )
  end

  defp default_period([]), do: nil
  defp default_period([seq | _]), do: {:sequence, seq}
```

- [ ] **Step 4: Replace the séquence `<select>` with a period selector**

In `render/1`, replace the `#results-seq-form` block in `<:actions>` with:

```elixir
            <form :if={@sequences != []} id="results-period-form" phx-change="select_period">
              <.input
                type="select"
                id="results-period-select"
                name="period"
                value={@period_param}
                options={[
                  {gettext("Séquences"),
                   for(s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", "seq:#{s.id}"})},
                  {gettext("Trimestres"),
                   for(t <- @terms, do: {gettext("Trimestre") <> " #{t.position}", "trim:#{t.id}"})},
                  {gettext("Année"), [{gettext("Année scolaire"), "annee"}]}
                ]}
              />
            </form>
```

(`Phoenix.HTML.Form`'s select renders `{group_label, [{opt_label, val}]}` tuples as `<optgroup>`s. The `Année` group has one option.)

- [ ] **Step 5: Update the empty-state guard, bulletin links, and print link to use the period**

Replace `@seq == nil` guards with `@period == nil`; replace the two `?seq=#{@seq.id}` URL params:
- The bulletin link in the results table row:
  ```elixir
                    navigate={
                      ~p"/school/classes/#{@cg.id}/students/#{row.enrollment.id}/bulletin?period=#{@period_param}"
                    }
  ```
- The whole-class print link:
  ```elixir
              href={~p"/school/classes/#{@cg.id}/bulletin/print?period=#{@period_param}"}
  ```

Any remaining `@seq` references become `@period`/`@period_param`. The `@results == nil` empty state stays as-is.

- [ ] **Step 6: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/school/results_live_test.exs`
Expected: PASS (existing séquence tests still pass — the default period is séquence 1 — plus the new trimester test).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/school/results_live.ex test/teacher_assistant_web/live/school/results_live_test.exs
git commit -m "feat(school): period selector on the results page (P2.6)"
```

---

### Task 4: Individual bulletin — period selector + breakdown columns

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex`
- Test: `test/teacher_assistant_web/live/school/bulletin_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Academics.resolve_period/2`, `period_param/1`, `period_kind/1`, `class_results_for_period/2`, `list_terms/1`.
- Produces: bulletin page resolves a `period` from `params["period"]`, shows the period selector, and renders component columns (`components.sequences` for trimester, `components.trimesters` for annual) in the per-subject table.

- [ ] **Step 1: Write the failing test**

Add to `test/teacher_assistant_web/live/school/bulletin_live_test.exs`. The setup grades séquence 1 only; grade séquence 2 as well so the trimester has two components:

```elixir
  test "the bulletin shows séquence breakdown columns for a trimester", %{
    conn: conn,
    cg: cg,
    enr: enr,
    seq: seq,
    school: school
  } do
    # grade a second séquence in the same term so the trimester has two components
    year = TeacherAssistant.Academics.current_academic_year(school)
    [s1, s2 | _] = TeacherAssistant.Academics.list_sequences(year)
    [term1 | _] = TeacherAssistant.Academics.list_terms(year)
    _ = seq

    [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)

    {:ok, a2} =
      TeacherAssistant.Academics.create_assessment(tc, s2, %{
        label: "D2",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: student}] = TeacherAssistant.Academics.list_roster(cg)
    :ok = TeacherAssistant.Academics.upsert_marks(a2, [%{student_id: student.id, score: Decimal.new(17)}])

    {:ok, _view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=trim:#{term1.id}")

    assert html =~ "Séq 1"
    assert html =~ "Séq 2"
    assert html =~ "Moy. trim."
    _ = s1
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs`
Expected: FAIL — bulletin does not accept `period=` / no breakdown columns.

- [ ] **Step 3: Resolve the period in mount and compute period results**

In `lib/teacher_assistant_web/live/school/bulletin_live.ex`, replace the séquence resolution with period resolution (keep the P2.5 authz `with` shape):

```elixir
  def mount(%{"id" => id, "enrollment_id" => eid} = params, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg),
         roster = Academics.list_roster(cg),
         %{student: student, enrollment: enrollment} <-
           Enum.find(roster, &(&1.enrollment.id == eid)) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []
      terms = if year, do: Academics.list_terms(year), else: []

      period =
        (year && Academics.resolve_period(year, params["period"])) ||
          case sequences do
            [seq | _] -> {:sequence, seq}
            [] -> nil
          end

      results = period && Academics.class_results_for_period(cg, period)
      data = results && results.per_student[student.id]

      {:ok,
       assign(socket,
         cg: cg,
         student: student,
         enrollment: enrollment,
         year: year,
         sequences: sequences,
         terms: terms,
         period: period,
         period_param: period && Academics.period_param(period),
         period_kind: period && Academics.period_kind(period),
         effectif: (results && results.effectif) || 0,
         data: data
       )}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      nil -> {:ok, push_navigate(socket, to: ~p"/school/classes/#{id}/results")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end
```

- [ ] **Step 4: Add the period selector and breakdown columns to the template**

In `render/1`:

(a) Replace the séquence display in the identity `dl` — change the "Séquence" cell to a "Période" cell showing `@period_heading` (add the helper below), and add a period selector next to the print button in `<:actions>`:

```elixir
            <form :if={@sequences != []} id="bulletin-period-form" phx-change="select_period" class="inline">
              <.input
                type="select"
                id="bulletin-period-select"
                name="period"
                value={@period_param}
                options={[
                  {gettext("Séquences"),
                   for(s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", "seq:#{s.id}"})},
                  {gettext("Trimestres"),
                   for(t <- @terms, do: {gettext("Trimestre") <> " #{t.position}", "trim:#{t.id}"})},
                  {gettext("Année"), [{gettext("Année scolaire"), "annee"}]}
                ]}
              />
            </form>
```

(b) In the per-subject table, insert component columns before the `Note/20` column, conditioned on `@period_kind`. Header:

```elixir
                <tr>
                  <th>{gettext("Matière")}</th>
                  <th>{gettext("Coefficient")}</th>
                  <%= case @period_kind do %>
                    <% :trimester -> %>
                      <th>{gettext("Séq 1")}</th>
                      <th>{gettext("Séq 2")}</th>
                      <th>{gettext("Moy. trim.")}</th>
                    <% :annual -> %>
                      <th>{gettext("Trim 1")}</th>
                      <th>{gettext("Trim 2")}</th>
                      <th>{gettext("Trim 3")}</th>
                      <th>{gettext("Moy. ann.")}</th>
                    <% _ -> %>
                      <th>{gettext("Note")}/20</th>
                  <% end %>
                  <th>{gettext("Note×Coef")}</th>
                  <th>{gettext("Cote classe")}</th>
                </tr>
```

Body row (`row <- @data.subjects`), matching cells:

```elixir
                  <td>{row.label}</td>
                  <td class="ta-num">{fmt(row.coefficient)}</td>
                  <%= case @period_kind do %>
                    <% :trimester -> %>
                      <td class="ta-num">{fmt(component_at(row, :sequences, 0))}</td>
                      <td class="ta-num">{fmt(component_at(row, :sequences, 1))}</td>
                      <td class="ta-num">{fmt(row.average)}</td>
                    <% :annual -> %>
                      <td class="ta-num">{fmt(component_at(row, :trimesters, 0))}</td>
                      <td class="ta-num">{fmt(component_at(row, :trimesters, 1))}</td>
                      <td class="ta-num">{fmt(component_at(row, :trimesters, 2))}</td>
                      <td class="ta-num">{fmt(row.average)}</td>
                    <% _ -> %>
                      <td class="ta-num">{fmt(row.average)}</td>
                  <% end %>
                  <td class="ta-num">{fmt(row.note_x_coef)}</td>
                  <td class="ta-num">{fmt(row.class_min)} – {fmt(row.class_max)}</td>
```

- [ ] **Step 5: Add the `handle_event`, `component_at/3`, and `period_heading/1` helpers**

Add to `bulletin_live.ex`:

```elixir
  def handle_event("select_period", %{"period" => param}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/school/classes/#{socket.assigns.cg.id}/students/#{socket.assigns.enrollment.id}/bulletin?period=#{param}"
     )}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp component_at(row, key, idx) do
    case row.components do
      %{^key => list} -> Enum.at(list, idx, %{})[:average]
      _ -> nil
    end
  end

  defp period_heading(%{period: {:sequence, seq}}), do: "#{gettext("Séquence")} #{seq.number}"
  defp period_heading(%{period: {:trimester, term}}), do: "#{gettext("Trimestre")} #{term.position}"
  defp period_heading(%{period: {:annual, _}}), do: gettext("Année scolaire")
  defp period_heading(_), do: "—"
```

Wait — `handle_event("select_period", …)` triggers a `push_patch`, which re-invokes `mount`? No — `push_patch` on the same LiveView calls `handle_params`, NOT `mount`. Since `mount` resolved the period, move the period resolution used by both `mount` and patch into a shared function and call it from `handle_params`. Simplest: in `handle_params`, re-resolve and recompute:

```elixir
  def handle_params(%{"period" => _} = params, _uri, socket) do
    year = socket.assigns.year

    period =
      (year && Academics.resolve_period(year, params["period"])) || socket.assigns.period

    results = period && Academics.class_results_for_period(socket.assigns.cg, period)

    {:noreply,
     assign(socket,
       period: period,
       period_param: period && Academics.period_param(period),
       period_kind: period && Academics.period_kind(period),
       effectif: (results && results.effectif) || 0,
       data: results && results.per_student[socket.assigns.student.id]
     )}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}
```

Use `period_heading(assigns)` in the identity `dl` "Période" cell: `{period_heading(assigns)}`.

- [ ] **Step 6: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs`
Expected: PASS (existing séquence bulletin test still green — default period is séquence 1 and the single Note/20 column renders — plus the new trimester-breakdown test).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/school/bulletin_live.ex test/teacher_assistant_web/live/school/bulletin_live_test.exs
git commit -m "feat(school): period selector + breakdown columns on the bulletin (P2.6)"
```

---

### Task 5: Bulletin print — `period=` param, header, breakdown columns

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex`
- Test: `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` (extend)

**Interfaces:**
- Consumes: `Academics.resolve_period/2`, `class_results_for_period/2`, `period_kind/1`; period heading rendering.
- Produces: both print routes accept `period=`; the cartouche shows the period heading; each bulletin renders the same breakdown columns as the on-screen bulletin.

- [ ] **Step 1: Write the failing test**

Add to `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`:

```elixir
  test "the whole-class print renders a trimester with séquence columns", %{
    conn: conn,
    cg: cg,
    seq: seq,
    school: school
  } do
    year = TeacherAssistant.Academics.current_academic_year(school)
    [_s1, s2 | _] = TeacherAssistant.Academics.list_sequences(year)
    [term1 | _] = TeacherAssistant.Academics.list_terms(year)
    _ = seq

    [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)

    {:ok, a2} =
      TeacherAssistant.Academics.create_assessment(tc, s2, %{
        label: "D2",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    for %{student: s} <- TeacherAssistant.Academics.list_roster(cg),
        do: TeacherAssistant.Academics.upsert_marks(a2, [%{student_id: s.id, score: Decimal.new(15)}])

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term1.id}")
    body = html_response(conn, 200)
    assert body =~ "Trimestre 1"
    assert body =~ "Séq 1"
    assert body =~ "Awa Ngo"
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: FAIL — the controller keys off `seq`, not `period`.

- [ ] **Step 3: Switch `with_class/4` to resolve a period**

In `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`, replace the séquence resolution + `class_results` with period resolution + `class_results_for_period`, and pass period metadata to the render:

```elixir
  defp with_class(conn, id, params, fun) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    with %{} = user <- user,
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg),
         year when not is_nil(year) <- scope.current_academic_year,
         period when not is_nil(period) <- Academics.resolve_period(year, params["period"]) do
      fun.(scope, cg, period, Academics.class_results_for_period(cg, period))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
```

Update `show/2` and `class/2` to pass `period` through their `fun` (rename the `seq` param to `period`), and `render_bulletins/6` to accept `period` and pass `period_kind` + `period_heading` to the template:

```elixir
  defp render_bulletins(conn, scope, cg, period, results, entries) do
    bundles =
      Enum.map(entries, fn %{student: student, enrollment: enrollment} ->
        %{
          student: student,
          enrollment: enrollment,
          data: results && results.per_student[student.id]
        }
      end)

    fm = Academics.form_master(cg)

    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show,
      etablissement: scope.current_workspace.name,
      annee: scope.current_academic_year && scope.current_academic_year.name,
      professeur_principal: fm && fm.email,
      cg: cg,
      period_kind: Academics.period_kind(period),
      period_heading: period_heading(period),
      effectif: (results && results.effectif) || 0,
      bundles: bundles
    )
  end

  defp period_heading({:sequence, seq}), do: "#{gettext("Séquence")} #{seq.number}"
  defp period_heading({:trimester, term}), do: "#{gettext("Trimestre")} #{term.position}"
  defp period_heading({:annual, _}), do: gettext("Année scolaire")
```

Remove the now-unused `seq:` assign from the template (see next step). The `show/2` roster lookup and `class/2` roster sort are unchanged; only the `fun.(scope, cg, seq, results)` arity label changes to `period`.

- [ ] **Step 4: Render the period heading and breakdown columns in the print template**

In `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex`:

(a) Replace the cartouche cell that currently prints the séquence (it references `@seq`) with `{@period_heading}`. Search for the `@seq` reference in the header/cartouche and replace with `{@period_heading}`.

(b) In each bundle's per-subject table, add the same conditional columns as the on-screen bulletin. Header row:

```heex
              <th><%= gettext("Matière") %></th>
              <th><%= gettext("Coef") %></th>
              <%= case @period_kind do %>
                <% :trimester -> %>
                  <th><%= gettext("Séq 1") %></th>
                  <th><%= gettext("Séq 2") %></th>
                  <th><%= gettext("Moy. trim.") %></th>
                <% :annual -> %>
                  <th><%= gettext("Trim 1") %></th>
                  <th><%= gettext("Trim 2") %></th>
                  <th><%= gettext("Trim 3") %></th>
                  <th><%= gettext("Moy. ann.") %></th>
                <% _ -> %>
                  <th><%= gettext("Note") %>/20</th>
              <% end %>
              <th><%= gettext("N×C") %></th>
```

Body row (per subject `row`), matching the header (use a local `component_at` — define it in the HTML module or inline with `Enum.at`):

```heex
              <td><%= row.label %></td>
              <td><%= fmt(row.coefficient) %></td>
              <%= case @period_kind do %>
                <% :trimester -> %>
                  <td><%= fmt(comp(row, :sequences, 0)) %></td>
                  <td><%= fmt(comp(row, :sequences, 1)) %></td>
                  <td><%= fmt(row.average) %></td>
                <% :annual -> %>
                  <td><%= fmt(comp(row, :trimesters, 0)) %></td>
                  <td><%= fmt(comp(row, :trimesters, 1)) %></td>
                  <td><%= fmt(comp(row, :trimesters, 2)) %></td>
                  <td><%= fmt(row.average) %></td>
                <% _ -> %>
                  <td><%= fmt(row.average) %></td>
              <% end %>
              <td><%= fmt(row.note_x_coef) %></td>
```

Adjust the surrounding markup to match the existing print table (this file already has a `fmt/1` helper in its HTML module; add `comp/3` beside it):

```elixir
  defp comp(row, key, idx) do
    case row.components do
      %{^key => list} -> Enum.at(list, idx, %{})[:average]
      _ -> nil
    end
  end
```

If the existing table has a fixed column count elsewhere (e.g. a totals `tfoot` with a hard-coded colspan), leave the totals row as-is — the breakdown adds leading columns only; verify the print still renders (visual correctness is covered by the assertion on "Séq 1").

- [ ] **Step 5: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: PASS (existing single + whole-class séquence tests still green — those requests carry `period=seq:<id>` now? No: the existing tests still pass `?seq=`; UPDATE those two existing requests to `?period=seq:#{seq.id}`). Update the two pre-existing print tests' URLs from `?seq=#{seq.id}` to `?period=seq:#{seq.id}`, and the single-bulletin test likewise, since the param was renamed.

- [ ] **Step 6: Update the séquence print links already emitted elsewhere**

The on-screen bulletin's "Imprimer" link and the results page's whole-class print link were updated in Tasks 3–4 to `period=`. Confirm no `?seq=` print URL remains:

Run: `grep -rn "bulletin/print?seq=" lib/ ; grep -rn "?seq=" lib/teacher_assistant_web`
Expected: no matches (all print/bulletin links now use `period=`).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/controllers/bulletin_print_controller.ex lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs
git commit -m "feat(school): period-aware bulletin print + breakdown columns (P2.6)"
```

---

### Task 6: gettext extract + FR/EN + final gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/fr/LC_MESSAGES/default.po`, `priv/gettext/en/LC_MESSAGES/default.po`

**Interfaces:**
- Consumes: all msgids added in Tasks 3–5.

- [ ] **Step 1: Extract and merge**

Run: `mix gettext.extract --merge`

- [ ] **Step 2: Fill every new msgid in BOTH locales**

New msgids (French source). FR msgstr mirrors the source; EN msgstr as below:

| msgid | FR msgstr | EN msgstr |
|---|---|---|
| `Séquences` | `Séquences` | `Sequences` |
| `Trimestres` | `Trimestres` | `Terms` |
| `Trimestre` | `Trimestre` | `Term` |
| `Année` | `Année` | `Year` |
| `Année scolaire` (if newly extracted) | `Année scolaire` | `School year` |
| `Période` | `Période` | `Period` |
| `Séq 1` | `Séq 1` | `Seq 1` |
| `Séq 2` | `Séq 2` | `Seq 2` |
| `Moy. trim.` | `Moy. trim.` | `Term avg.` |
| `Trim 1` | `Trim 1` | `Term 1` |
| `Trim 2` | `Trim 2` | `Term 2` |
| `Trim 3` | `Trim 3` | `Term 3` |
| `Moy. ann.` | `Moy. ann.` | `Annual avg.` |
| `N×C` (if new) | `N×C` | `M×C` |

Fill any other newly-empty msgid the extract surfaced from P2.6 work. Do NOT touch pre-existing unrelated fuzzy/empty entries.

Verify none of the new ids is empty in either locale:
```bash
grep -n "Trimestre\|Séquences\|Période\|Moy. \|Trim 1\|Séq 1\|Année" priv/gettext/en/LC_MESSAGES/default.po
```

- [ ] **Step 3: Run the full gate**

Run: `mix precommit`
Expected: compile clean, deps.unlock clean, format clean, full suite green. If it fails ONLY with a `users_unique_email_index` collision, re-run `mix test --seed 0` to confirm the known fixture flake; report both. Commit any format-only rewrites the `format` step produced.

- [ ] **Step 4: Commit**

```bash
git add priv/gettext lib test
git commit -m "chore(i18n): extract + FR/EN for P2.6 trimester/annual bulletins"
```

---

## Self-Review

**Spec coverage:**
- Methodology (trimester = mean of séquences; annual = mean of séquences; excl. ungraded) → Task 2 `period_result` + `mean_present`, tested in Task 2 ✓
- Engine architecture (extract `aggregate`, behavior-preserving; `components` on rows) → Task 1 ✓
- Data loading (`class_results_for_period`, `resolve_period`, components) → Task 2 ✓
- UI period selector + results table single-number + bulletin breakdown (selection C) → Tasks 3 (results) & 4 (bulletin) ✓
- Print period param + header + breakdown → Task 5 ✓
- Form-master access unchanged → Tasks 3–5 keep the `admin_or_form_master?` gate; Task 4 test note covers a form master reaching a trimester bulletin (add to the bulletin test if not already: the existing P2.5 access tests still run) ✓
- i18n + gate → Task 6 ✓

**Placeholder scan:** No TBD/TODO; every code step carries complete code. Two spots defer to "match the existing table markup" (Task 5 template) — acceptable because the exact surrounding HEEx is in the file and the inserted blocks are given verbatim.

**Type consistency:** `aggregate/2`, `class_results_for_period/2`, `resolve_period/2`, `period_param/1`, `period_kind/1`, `list_terms/1` are defined in Tasks 1–2 and consumed with matching signatures in 3–5. `components` shape (`%{sequences: [%{number, average}]}` / `%{trimesters: [%{position, average}]}`) is produced in Task 2 and read by `component_at/3` / `comp/3` in Tasks 4–5. The spec's `compile_period/2` is realized as the shared `aggregate/2` called directly by the loader (no redundant wrapper) — intent preserved, YAGNI.

**Known deviation from spec wording:** spec §1 names `compile_period/2`; the plan uses `aggregate/2` as the single shared core the loader calls, avoiding a delegate-only function. Behavior and reuse are identical.
