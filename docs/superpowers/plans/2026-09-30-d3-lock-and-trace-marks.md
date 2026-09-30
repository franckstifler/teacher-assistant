# D3 — Lock and Trace Marks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every mark change is journaled; marks lock after the sequence's grade-entry deadline; a locked mark changes only through a teacher's correction request approved by the Censeur.

**Architecture:** All enforcement lives in the `Mark` / `Assessment` resources (a journaling change + a lock validation), so no UI path can bypass it. Two new resources in the `TeacherAssistant.Assessment` domain: `MarkEvent` (append-only journal) and `MarkCorrection` (request → approve/refuse). Approval writes the mark through the normal `Mark` actions with a `mark_correction_id` context that the lock validation verifies against a pending correction.

**Tech Stack:** Elixir, Phoenix LiveView 1.8, Ash 3 + AshPostgres (attribute multitenancy on `workspace_id`), daisyUI, Gettext (FR source strings).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`, section "D3 — Lock and trace marks".

## Global Constraints

- Never write migrations by hand: `mix ash.codegen --dev <name>` then `mix ash.migrate` (AGENTS.md).
- Never bare `:atom` attributes: every closed set is an `Ash.Type.Enum` (see `lib/teacher_assistant/academics/mark_status.ex`).
- Policies are real (spec C): no `authorize?: false` except the one documented journal write in Task 1.
- Scope-first domain functions: `fun(%Scope{} = scope, ...)`, called with `scope: scope`.
- UI strings are French `gettext` sources; run `mix gettext.extract --merge` and fill `en` entries.
- LiveViews start with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`.
- No real school data exists: schema changes need no backfill.
- Finish with `mix precommit`, but it does NOT fail on warnings — also check `mix compile --warnings-as-errors`.
- One branch `d3-lock-trace-marks`; commit per task.

## Review Focus

1. A save of an unchanged grid writes **no** journal rows (Decimal `12` vs `12.0` must compare equal) — Task 1.
2. A stale approval: the mark changed (or was deleted) after the request → approval refused, nothing written — Task 5.
3. Deadline day itself is still open; locked starts the day after, in Cameroon time (UTC+1), not server UTC — Tasks 2–3.
4. A combined-course save (`upsert_marks_all_or_nothing`) with one locked class rejects the whole save, nothing written — Task 3.
5. An admin (Censeur) calling the grid save on a locked assessment is refused like a teacher — Task 3.

---

## File Structure

- Create `lib/teacher_assistant/academics/mark_event.ex` — journal resource (append-only).
- Create `lib/teacher_assistant/academics/mark_event_action.ex` — enum.
- Create `lib/teacher_assistant/academics/mark/journal.ex` — Ash change writing a `MarkEvent` after a mark write.
- Create `lib/teacher_assistant/academics/lock.ex` — `locked?/2`.
- Create `lib/teacher_assistant/academics/mark/assessment_open.ex`, `lib/teacher_assistant/academics/assessment/sequence_open.ex` — lock validations.
- Create `lib/teacher_assistant/academics/mark_correction.ex`, `mark_correction_status.ex`, `mark_correction_motive.ex`.
- Create `lib/teacher_assistant_web/live/school/corrections_live.ex` (teacher) and `lib/teacher_assistant_web/live/school/correction_review_live.ex` (Censeur, incl. Journal tab).
- Modify `mark.ex`, `assessment.ex` (resource), `lib/teacher_assistant/assessment.ex` (domain), `reference.ex`, `sequence/grade_entry_deadline.ex`, `accounts/school_profile.ex`, `evaluations_live.ex`, `teacher/marks_live.ex`, `spaces.ex`, `components/layouts.ex`, `router.ex`.

---

### Task 1: Marks journal (N04 data)

**Files:**
- Create: `lib/teacher_assistant/academics/mark_event_action.ex`, `lib/teacher_assistant/academics/mark_event.ex`, `lib/teacher_assistant/academics/mark/journal.ex`
- Modify: `lib/teacher_assistant/academics/mark.ex`, `lib/teacher_assistant/assessment.ex` (register resource + `list_mark_events/2`)
- Test: `test/teacher_assistant/academics/mark_journal_test.exs`

**Interfaces:**
- Produces: `MarkEvent` fields `action, actor_user_id, assessment_id, student_id, before_status, before_score, after_status, after_score, batch_id, mark_correction_id, inserted_at`; action `:record` (internal only); `Assessment.list_mark_events(scope, opts \\ [])` newest first, loads `[:actor, assessment: [:teaching_context], student: []]`; Mark changesets read `context[:mark_batch_id]` and `context[:mark_correction_id]`.

- [ ] **Step 1: Write the failing tests**

Use the fixtures already used by `test/teacher_assistant_web/live/teacher/marks_combined_test.exs` (school scope, teacher context, assessment, students). Tests:

```elixir
defmodule TeacherAssistant.Academics.MarkJournalTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment

  # setup: head scope, a teaching context with teacher scope `t`, an assessment `a`
  # in an OPEN sequence, two students s1, s2 (copy setup from marks_combined_test.exs)

  test "a save journals one row per changed mark, sharing a batch id", ctx do
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: 12}, %{student_id: ctx.s2.id, score: 9}])
    [e1, e2] = Assessment.list_mark_events(ctx.head)
    assert e1.batch_id == e2.batch_id
    assert e1.action == :saisie and e1.actor_user_id == ctx.t.current_user.id
    assert e1.before_status == nil
  end

  test "re-saving the same values journals nothing (12 == 12.0)", ctx do
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: 12}])
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new("12.0")}])
    assert length(Assessment.list_mark_events(ctx.head)) == 1
  end

  test "clearing a mark journals before -> blank", ctx do
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: 12}])
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: nil}])
    [latest | _] = Assessment.list_mark_events(ctx.head)
    assert latest.before_status == :graded and latest.after_status == nil
  end

  test "the journal cannot be written or read by a plain teacher", ctx do
    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(TeacherAssistant.Academics.MarkEvent, %{action: :saisie}, action: :record, scope: ctx.head)
    assert Assessment.list_mark_events(ctx.t) == []
  end
end
```

(Check the real `upsert_marks/…` arity at `lib/teacher_assistant/assessment.ex:158` and adapt the calls.)

- [ ] **Step 2: Run to verify failure** — `mix test test/teacher_assistant/academics/mark_journal_test.exs` → FAIL (`list_mark_events` undefined).

- [ ] **Step 3: Enum**

```elixir
defmodule TeacherAssistant.Academics.MarkEventAction do
  @moduledoc "What a marks-journal row records (spec D3a)."
  use Ash.Type.Enum,
    values: [:saisie, :correction_demandee, :correction_approuvee, :correction_refusee]
end
```

- [ ] **Step 4: Resource** — model it on `subject_exemption.ex` (same `postgres`/`references`/`multitenancy` shape, domain `TeacherAssistant.Assessment`).

```elixir
  actions do
    defaults [:read]

    create :record do
      accept [:action, :actor_user_id, :assessment_id, :student_id, :before_status,
              :before_score, :after_status, :after_score, :batch_id, :mark_correction_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    # Written only by `Mark.Journal` / `MarkCorrection` with `authorize?: false`:
    # nobody may record, edit or delete journal rows through an action.
    policy action(:record) do
      forbid_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :action, TeacherAssistant.Academics.MarkEventAction, allow_nil?: false, public?: true
    attribute :actor_user_id, :uuid, public?: true            # nil = system
    attribute :before_status, TeacherAssistant.Academics.MarkStatus, public?: true  # nil = blank
    attribute :before_score, :decimal, public?: true
    attribute :after_status, TeacherAssistant.Academics.MarkStatus, public?: true
    attribute :after_score, :decimal, public?: true
    attribute :batch_id, :uuid, public?: true
    attribute :mark_correction_id, :uuid, public?: true
    create_timestamp :inserted_at
  end
```

Relationships: `belongs_to :assessment`, `:student`, `:workspace` (as in Mark), `belongs_to :actor, TeacherAssistant.Accounts.User, source_attribute: :actor_user_id, define_attribute?: false`. Do NOT add `on_delete: :delete` on assessment/student references (the journal must survive; if an FK blocks deleting a student/assessment, use `on_delete: :nilify` and make those columns nullable). No update/destroy actions.

- [ ] **Step 5: The change**

```elixir
defmodule TeacherAssistant.Academics.Mark.Journal do
  @moduledoc "Journals a mark write (spec D3a) in the same transaction; no row when nothing changed."
  use Ash.Resource.Change
  alias TeacherAssistant.Academics.MarkEvent

  @impl true
  def change(changeset, _opts, context) do
    before = if changeset.action_type == :create, do: nil, else: snapshot(changeset.data)

    Ash.Changeset.after_action(changeset, fn changeset, mark ->
      now = if changeset.action_type == :destroy, do: nil, else: snapshot(mark)

      if now != before do
        correction_id = changeset.context[:mark_correction_id]

        MarkEvent
        |> Ash.Changeset.for_create(:record, %{
          action: if(correction_id, do: :correction_approuvee, else: :saisie),
          actor_user_id: context.actor && context.actor.id,
          assessment_id: mark.assessment_id,
          student_id: mark.student_id,
          before_status: before && before.status,
          before_score: before && before.score,
          after_status: now && now.status,
          after_score: now && now.score,
          batch_id: changeset.context[:mark_batch_id],
          mark_correction_id: correction_id
        })
        # The one sanctioned bypass: `:record` forbids every caller (append-only journal).
        |> Ash.create!(tenant: mark.workspace_id, authorize?: false)
      end

      {:ok, mark}
    end)
  end

  defp snapshot(mark),
    do: %{status: mark.status, score: mark.score && Decimal.normalize(mark.score)}
end
```

- [ ] **Step 6: Wire into Mark** — in `mark.ex` replace `defaults [:read, :destroy, create: [...]]` with explicit actions:

```elixir
    defaults [:read]

    create :create do
      primary? true
      accept [:score, :status, :assessment_id, :student_id]
      change TeacherAssistant.Academics.Mark.Journal
    end

    update :update do
      accept [:score, :status]
      require_atomic? false
      change TeacherAssistant.Academics.Mark.Journal
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      change TeacherAssistant.Academics.Mark.Journal
    end
```

In `:upsert_all`'s `run fn`, generate `batch = Ash.UUIDv7.generate()` once and pass it to `upsert_group(assessment_id, entries, scope, batch)`; add `context: %{mark_batch_id: batch}` to the `for_create`, `for_update` and `Ash.destroy(mark, ..., context: %{mark_batch_id: batch})` calls.

- [ ] **Step 7: Domain** — register `resource TeacherAssistant.Academics.MarkEvent` in `lib/teacher_assistant/assessment.ex` and add:

```elixir
  @doc "The marks journal, newest first (admins only; others get [])."
  def list_mark_events(%Scope{} = scope, opts \\ []) do
    MarkEvent
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(Keyword.get(opts, :limit, 200))
    |> Ash.Query.load([:actor, :student, assessment: [:teaching_context]])
    |> Ash.read(scope: scope)
    |> case do
      {:ok, events} -> events
      {:error, %Ash.Error.Forbidden{}} -> []
    end
  end
```

(If read policies filter rather than forbid, the teacher gets `{:ok, []}` — both are fine.)

- [ ] **Step 8: Migrate & test** — `mix ash.codegen --dev mark_events && mix ash.migrate && mix test test/teacher_assistant/academics/mark_journal_test.exs test/teacher_assistant_web/live/teacher` → PASS.

- [ ] **Step 9: Commit** — `git commit -m "feat: marks journal records every mark change"`

---

### Task 2: Grace-days setting and Cameroon "today" (N02 prerequisites)

**Files:**
- Modify: `lib/teacher_assistant/academics/reference.ex`, `lib/teacher_assistant/accounts/school_profile.ex`, `lib/teacher_assistant/academics/sequence/grade_entry_deadline.ex`, `lib/teacher_assistant_web/live/school/evaluations_live.ex`, `lib/teacher_assistant/assessment.ex` (`save_entry_grace_days/2`)
- Test: `test/teacher_assistant/academics/grading_rules_test.exs` (extend), `test/teacher_assistant_web/live/school/evaluations_live_test.exs` (extend; create if absent)

**Interfaces:**
- Produces: `Reference.today/0 :: Date.t()` (UTC+1, WAT has no DST); `SchoolProfile.entry_grace_days :: integer 0..30, default 5`; `grade_entry_deadline` uses the school's value; `Assessment.save_entry_grace_days(scope, "7") :: {:ok, profile} | {:error, form_or_error}`.

- [ ] **Step 1: Failing tests**

```elixir
test "the deadline uses the school's grace days", ctx do
  {:ok, _} = Assessment.save_entry_grace_days(ctx.head, "7")
  [seq | _] = TeacherAssistant.Organization.list_sequences(ctx.head, ctx.year)  # adapt to the real lister
  assert seq.grade_entry_deadline == Date.add(seq.end_date, 7)
end

test "grace days outside 0..30 are refused", ctx do
  assert {:error, _} = Assessment.save_entry_grace_days(ctx.head, "31")
  assert {:error, _} = Assessment.save_entry_grace_days(ctx.head, "abc")
end

test "a teacher cannot change grace days", ctx do
  assert {:error, _} = Assessment.save_entry_grace_days(ctx.teacher, "7")
end
```

LiveView test: admin sees `#entry-grace-days-form`, submits `7`, flash shown; a teacher does not see the form.

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`reference.ex`: keep `entry_grace_days/0` as the default and add

```elixir
  @doc "Today's date in Cameroon (WAT, UTC+1, no DST) — the lock's clock."
  def today, do: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_date()
```

`school_profile.ex`: attribute `:entry_grace_days, :integer, allow_nil?: false, default: 5, public?: true, constraints: [min: 0, max: 30]`; add it to the update action's `accept` list (next to `:default_max_score`).

`grade_entry_deadline.ex`: read the school's value per workspace:

```elixir
  @impl true
  def load(_query, _opts, _context), do: [:entry_deadline, :end_date, :workspace_id]

  @impl true
  def calculate(records, _opts, _context) do
    grace =
      records
      |> Enum.map(& &1.workspace_id)
      |> Enum.uniq()
      |> Map.new(fn ws -> {ws, grace_days(ws)} end)

    Enum.map(records, fn seq ->
      seq.entry_deadline || Date.add(seq.end_date, grace[seq.workspace_id])
    end)
  end

  # A school setting, not member data: read without an actor so every caller
  # (policies, the lock validation) sees the same deadline.
  defp grace_days(workspace_id) do
    TeacherAssistant.Accounts.SchoolProfile
    |> Ash.Query.for_read(:for_workspace, %{workspace_id: workspace_id})
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{entry_grace_days: n}} -> n
      _ -> Reference.entry_grace_days()
    end
  end
```

(This is a second documented `authorize?: false`; add it to the Global Constraints note in the PR description.)

Domain `save_entry_grace_days/2`: parse with `Integer.parse/1` (reject non-integer → `{:error, :invalid}`), then update the profile via the same update action `save_default_max` uses in `evaluations_live.ex` (follow that function's code path exactly).

`evaluations_live.ex`: a form `id="entry-grace-days-form"` `phx-submit="save_entry_grace_days"`, `<.input type="number" name="entry_grace_days" min="0" max="30" label={gettext("Délai de saisie après la fin de séquence (jours)")} />`, shown only when the page's existing admin flag is true (same flag as the default-max form). Flash `gettext("Délai de saisie enregistré.")`.

- [ ] **Step 4: Codegen, migrate, run tests** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: grace days for the grade-entry deadline are a school setting"`

---

### Task 3: The lock (N02 enforcement)

**Files:**
- Create: `lib/teacher_assistant/academics/lock.ex`, `lib/teacher_assistant/academics/mark/assessment_open.ex`, `lib/teacher_assistant/academics/assessment/sequence_open.ex`
- Modify: `mark.ex` (validation), `lib/teacher_assistant/academics/assessment.ex` (validation)
- Test: `test/teacher_assistant/academics/mark_lock_test.exs`

**Interfaces:**
- Produces: `Lock.locked?(%Sequence{grade_entry_deadline: Date}, today \\ Reference.today()) :: boolean`; Mark writes on a locked assessment fail with field error `:assessment_id` message `"locked"` unless `context.mark_correction_id` names a **pending** `MarkCorrection` for the same assessment and student (that resource arrives in Task 5 — until then the validation treats any correction id as invalid).

- [ ] **Step 1: Failing tests** (a sequence is locked by setting its `entry_deadline` to yesterday via `Organization.update_calendar/3`, or directly with a test-only `Ash.update` as the head)

```elixir
test "deadline day is open, the day after is locked" do
  seq = %TeacherAssistant.Academics.Sequence{grade_entry_deadline: ~D[2026-10-02]}
  refute Lock.locked?(seq, ~D[2026-10-02])
  assert Lock.locked?(seq, ~D[2026-10-03])
end

test "no one can save, clear or delete marks of a locked assessment", ctx do
  lock!(ctx.seq)
  assert {:error, _} = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: 10}])
  assert {:error, _} = Assessment.upsert_marks(ctx.head, ctx.a, [%{student_id: ctx.s1.id, score: 10}])
end

test "a combined save with one locked class writes nothing", ctx do
  # one open and one locked assessment in `upsert_marks_all_or_nothing/2`
  assert {:error, _} = Assessment.upsert_marks_all_or_nothing(ctx.t, [open_entries, locked_entries])
  assert marks_for(ctx.open_a) == []
end

test "assessments of a locked sequence cannot be created, edited or deleted", ctx do
  lock!(ctx.seq)
  assert {:error, _} = Assessment.create_assessment(ctx.t, %{...same params as existing tests..., sequence_id: ctx.seq.id})
  assert {:error, _} = Ash.destroy(ctx.a, scope: ctx.t)
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```elixir
defmodule TeacherAssistant.Academics.Lock do
  @moduledoc "Marks lock the day after their sequence's grade-entry deadline (spec D3b)."
  alias TeacherAssistant.Academics.Reference

  def locked?(%{grade_entry_deadline: %Date{} = deadline}, today \\ Reference.today()),
    do: Date.after?(today, deadline)
end
```

`Mark.AssessmentOpen` (a `Ash.Resource.Validation`, registered like `ScoreWithinMax` with `on: [:create, :update, :destroy], before_action?: true`): fetch the assessment by `Ash.Changeset.get_attribute(changeset, :assessment_id)` (or `changeset.data.assessment_id`) with `load: [sequence: [:grade_entry_deadline]]`, using the changeset's actor/tenant exactly as `ScoreWithinMax` does. If not locked → `:ok`. If locked → `:ok` only when `approved_correction?(changeset)`, else `{:error, field: :assessment_id, message: "locked"}`.

```elixir
  # Task 5 replaces this with a real pending-correction lookup.
  defp approved_correction?(_changeset), do: false
```

`Assessment.SequenceOpen`: same shape on the `Assessment` resource for its create/update/destroy actions, loading the sequence by `sequence_id`.

- [ ] **Step 4: Run** the new file plus `mix test test/teacher_assistant test/teacher_assistant_web/live/teacher` → PASS (fix any existing test that relied on editing marks of a sequence whose deadline is in the past — give its fixture a future `entry_deadline`).
- [ ] **Step 5: Commit** — `git commit -m "feat: marks and assessments lock after the grade-entry deadline"`

---

### Task 4: Locked columns on the marks page (N02 UI)

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/marks_lock_test.exs`

**Interfaces:**
- Consumes: `Lock.locked?/1`, `@seq.grade_entry_deadline` (already loaded, see `marks_live.ex:648`).
- Produces: assign `@locked?`; element ids `#locked-banner`, `#locked-request-link` (→ `~p"/school/corrections/new?assessment=#{id}"`, route added in Task 6).

- [ ] **Step 1: Failing test** — with a locked sequence: page shows `#locked-banner` with "verrouillée", score inputs have `disabled`, no save button (`refute has_element?(view, "#marks-save")` — use the page's real save button id), "new assessment" form hidden; `render_submit` of `"save"` returns a flash error and writes nothing. With an open sequence, none of that.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — `assign(:locked?, Lock.locked?(seq))` wherever `@seq` is assigned (`select_seq` and mount). In the template: banner `<div :if={@locked?} id="locked-banner" class="alert">{gettext("Séquence verrouillée depuis le %{date} : les notes ne se modifient plus que par une demande de correction.", date: ...)} <.link id="locked-request-link" navigate={...}>{gettext("Nouvelle demande")}</.link></div>`; `disabled={@locked?}` on inputs; `:if={!@locked?}` on the save button and the new-assessment form; column header suffix `· verrouillée`. In `handle_event("save", ...)` and `"new_assessment"`: if `@locked?`, `put_flash(:error, gettext("Séquence verrouillée."))` and no write (the resource refuses anyway).
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -m "feat: the marks page shows locked sequences read-only"`

---

### Task 5: Correction requests (N03 domain)

**Files:**
- Create: `lib/teacher_assistant/academics/mark_correction.ex`, `mark_correction_status.ex`, `mark_correction_motive.ex`
- Modify: `mark/assessment_open.ex` (real `approved_correction?/1`), `lib/teacher_assistant/assessment.ex` (register + functions)
- Test: `test/teacher_assistant/academics/mark_correction_test.exs`

**Interfaces:**
- Produces:
  - `MarkCorrectionStatus` `[:pending, :approved, :refused]`; `MarkCorrectionMotive` `[:erreur_saisie, :copie_mal_corrigee, :reclamation_eleve, :note_rattrapage]` with `label/1` → "Erreur de saisie", "Copie mal corrigée", "Réclamation de l'élève", "Note de rattrapage".
  - `MarkCorrection` fields: `assessment_id, student_id, requested_status (MarkStatus, nil = blank), requested_score, current_status, current_score, motive, status, requester_user_id, decider_user_id, decided_at, seen_at`.
  - Domain: `request_correction(scope, %{assessment_id, student_id, requested_status, requested_score, motive}) :: {:ok, c} | {:error, e}`; `approve_correction(scope, c)`; `refuse_correction(scope, c)`; `list_my_corrections(scope)`; `list_corrections(scope, :pending | :decided)`; `mark_corrections_seen(scope)`; `pending_corrections_count(scope)`; `unseen_decisions_count(scope)`; `can_decide_corrections?(scope)` (= `Ash.can?({MarkCorrection, :approve}, scope)`-style check, as `Accounts.can_manage_staff?/1` does).

- [ ] **Step 1: Failing tests**

```elixir
test "the course teacher requests a correction on a locked mark", ctx do
  lock!(ctx.seq)
  assert {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, score: 14))
  assert c.status == :pending and c.current_score == Decimal.new(12)
  assert [%{action: :correction_demandee}| _] = Assessment.list_mark_events(ctx.head)
end

test "requests are refused on open assessments, from another teacher, and twice", ctx do
  assert {:error, _} = Assessment.request_correction(ctx.t, req(ctx, score: 14))   # open
  lock!(ctx.seq)
  assert {:error, _} = Assessment.request_correction(ctx.other_teacher, req(ctx, score: 14))
  {:ok, _} = Assessment.request_correction(ctx.t, req(ctx, score: 14))
  assert {:error, _} = Assessment.request_correction(ctx.t, req(ctx, score: 15))  # one pending per mark
end

test "approval writes the mark and journals it; only admins decide", ctx do
  lock!(ctx.seq)
  {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, score: 14))
  assert {:error, _} = Assessment.approve_correction(ctx.t, c)
  assert {:ok, %{status: :approved}} = Assessment.approve_correction(ctx.censeur, c)
  assert mark_of(ctx).score == Decimal.new(14)
  assert Enum.any?(Assessment.list_mark_events(ctx.head), &(&1.action == :correction_approuvee))
end

test "a stale request cannot be approved", ctx do
  lock!(ctx.seq)
  {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, score: 14))
  unlock!(ctx.seq)                                   # entry_deadline = tomorrow
  :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: 9}])
  lock!(ctx.seq)
  assert {:error, _} = Assessment.approve_correction(ctx.censeur, c)
  assert mark_of(ctx).score == Decimal.new(9)
end

test "refusing leaves the mark and journals the refusal", ctx do
  lock!(ctx.seq)
  {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, score: 14))
  assert {:ok, %{status: :refused}} = Assessment.refuse_correction(ctx.censeur, c)
  assert mark_of(ctx).score == Decimal.new(12)
  assert [%{action: :correction_refusee} | _] = Assessment.list_mark_events(ctx.head)
end

test "a correction id on a direct write does not unlock", ctx do
  lock!(ctx.seq)
  {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, score: 14))
  mark = mark_of(ctx)
  assert {:error, _} = Ash.update(mark, %{score: 3}, scope: ctx.t, context: %{mark_correction_id: c.id})
end
```

Last test: approval must also require the actor to be allowed to decide — the direct write above is by the teacher, whose correction is pending; `approved_correction?/1` must require that the write happens *inside* `:approve` (see Step 3).

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

Resource (shape of `subject_exemption.ex`). Actions:

```elixir
    defaults [:read]

    create :request do
      accept [:assessment_id, :student_id, :requested_status, :requested_score, :motive]
      change set_attribute(:requester_user_id, actor(:id))
      change set_attribute(:status, :pending)
      change TeacherAssistant.Academics.MarkCorrection.Request   # snapshot current mark, require locked, journal :correction_demandee
    end

    update :approve do
      require_atomic? false
      change TeacherAssistant.Academics.MarkCorrection.Decide, decision: :approved
    end

    update :refuse do
      require_atomic? false
      change TeacherAssistant.Academics.MarkCorrection.Decide, decision: :refused
    end

    update :mark_seen do
      change set_attribute(:seen_at, &DateTime.utc_now/0)
    end
```

Policies: read → admin axis OR `expr(requester_user_id == ^actor(:id))`; `:request` → `forbid_unless {Checks.SchoolRole, any_of: :member}` then `authorize_if expr(assessment.teaching_context.teacher_user_id == ^actor(:id))` (mirrors `mark.ex:131`; use a `relates_to_actor_via` / create-safe check if Ash refuses filter checks on create — the Mark policy already does this on create, so copy it); `:approve`/`:refuse` → admin axis; `:mark_seen` → requester.

Identity: `identity :one_pending_per_mark, [:assessment_id, :student_id], where: expr(status == :pending)` + in `postgres` block `identity_wheres_to_sql one_pending_per_mark: "status = 'pending'"`.

`Request` change (before_action): load the assessment's sequence, return error `"not locked"` unless `Lock.locked?`; read the current mark (nil → blank) and set `current_status`/`current_score`; after_action: record `MarkEvent` `:correction_demandee` (before = current, after = requested, `mark_correction_id`), `authorize?: false` as in Task 1.

`Decide` change (before_action): error unless `changeset.data.status == :pending`; for `:approved`, re-read the current mark and compare with the snapshot (normalized Decimals) → error `"stale"` on mismatch; then write the mark as the actor through the normal Mark action with `context: %{mark_correction_id: data.id, mark_correction_deciding?: true}`: create if none, update if exists, destroy if requested blank. The Mark write happens in the same transaction (the update action is transactional). Set `status`, `decider_user_id: actor.id`, `decided_at: DateTime.utc_now()`. For `:refused`, record `MarkEvent :correction_refusee` directly (no mark write).

`AssessmentOpen.approved_correction?/1`: true only when `changeset.context[:mark_correction_deciding?] == true` AND a `MarkCorrection` with id `context[:mark_correction_id]`, `status == :pending`, same `assessment_id` and `student_id` exists (read with `authorize?: false`, tenant = changeset tenant). Because `mark_correction_deciding?` is set only by `Decide`, and `Decide` runs only inside the admin-only `:approve`, a teacher passing context cannot unlock (a teacher could pass both keys — so ALSO require the actor to be admin: `Ash.can?({MarkCorrection, :approve}, actor, tenant: ...)` or check `Checks.SchoolRole` admin axis for the actor). Keep this function short and commented.

Domain functions: thin wrappers with `scope: scope` and loads `[:student, assessment: [teaching_context: [:class_group, :subject]]]`; counts via `Ash.count`.

- [ ] **Step 4: Codegen, migrate, run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: correction requests are the only way to change a locked mark"`

---

### Task 6: Teacher "Corrections de notes" page (N03 teacher UI)

**Files:**
- Create: `lib/teacher_assistant_web/live/school/corrections_live.ex`
- Modify: `router.ex` (`live "/school/corrections", School.CorrectionsLive, :index` and `live "/school/corrections/new", School.CorrectionsLive, :new` in the `:school_workspace` session)
- Test: `test/teacher_assistant_web/live/school/corrections_live_test.exs`

**Interfaces:**
- Consumes: Task 5 domain functions; query param `assessment` on `:new` preselects it.
- Produces: ids `#corrections-list`, `#correction-<id>`, `#new-correction-form`, `#correction-submit`.

- [ ] **Step 1: Failing tests** — teacher with a locked assessment: list shows own requests with "En attente/Approuvée/Refusée" and `12 → 14`; `:new` form offers only locked assessments of the teacher's courses, the students of that class, value field (0–20, `abs`, `abj`, empty = blank, comma accepted — reuse the marks page's parser), motive chips; submit → flash "Demande envoyée au censeur." and row appears; invalid value → inline error, nothing created; visiting the page calls `mark_corrections_seen/1`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — header eyebrow `gettext("Démarches · notes verrouillées")`, title `gettext("Corrections de notes")`, side `"%{n} en attente"`. Table columns Date · Élève · Classe · Avant → après · Statut (mono for numbers; status colors: pending `badge-warning`, approved `badge-success`, refused `badge-error`). Form: `<.form for={@form} id="new-correction-form" phx-change="validate" phx-submit="request">` with `<.input type="select">` for assessment and student, `<.input name="value">`, motive radio group styled as chips; button `id="correction-submit"` label `gettext("Envoyer au censeur")`. Note under the form: `gettext("Chaque demande et chaque décision sont inscrites au journal.")`.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -m "feat: teachers request corrections of locked marks"`

---

### Task 7: Censeur review page with the Journal (N03 decision UI + N04 UI)

**Files:**
- Create: `lib/teacher_assistant_web/live/school/correction_review_live.ex`
- Modify: `router.ex` (`live "/school/corrections/review", School.CorrectionReviewLive, :index`)
- Test: `test/teacher_assistant_web/live/school/correction_review_live_test.exs`

**Interfaces:**
- Consumes: `list_corrections/2`, `approve_correction/2`, `refuse_correction/2`, `list_mark_events/2`, `can_decide_corrections?/1`, `Assessment.summarize/…` for the student's resulting sequence average.
- Produces: ids `#review-tab-pending`, `#review-tab-decided`, `#review-tab-journal`, `#correction-detail`, `#approve-correction`, `#refuse-correction`, `#journal`.

- [ ] **Step 1: Failing tests** — non-admin is redirected to `/school` with a flash (like `periods_live.ex:14`); admin sees pending list (Date · Enseignant · Élève · classe · Évaluation · Avant → après); selecting shows detail (Note actuelle, Note demandée, Motif, Moyenne S1 de l'élève after the change); approve → row moves to "Traitées", flash; refuse likewise; a stale approval shows `gettext("La note a changé depuis la demande : demande à refaire.")`; Journal tab lists Horodatage · Auteur (`Système` when nil) · Action (FR labels) · Détail (`Élève · classe · matière · 12 → 14`), grouped by `batch_id` for `saisie` rows ("Devoir 1 · 4e B · 7 notes"), plus one derived "Verrouillage" line per locked sequence of the current year at its deadline.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — mount guard `if Assessment.can_decide_corrections?(scope)`, tabs via `handle_params` `?tab=`, detail via `phx-click="select"`. Header eyebrow `gettext("Censorat · intégrité des notes")`. Journal grouping: `Enum.chunk_by(events, &(&1.batch_id || &1.id))`, render one line per chunk (single-mark chunks show the before → after). Derived lock lines: for each sequence of `scope.current_academic_year` where `Lock.locked?`, a `%{when: deadline+1, who: gettext("Système"), what: gettext("Verrouillage"), detail: "S#{n} · toutes les classes (date limite dépassée)"}` merged into the list by date.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -m "feat: the censeur decides corrections and reads the marks journal"`

---

### Task 8: Menu items and badges

**Files:**
- Modify: `lib/teacher_assistant_web/spaces.ex`, `lib/teacher_assistant_web/components/layouts.ex` (`rail_link` gets optional `badge` attr)
- Test: `test/teacher_assistant_web/spaces_test.exs`, `test/teacher_assistant_web/live/role_spaces_test.exs`

**Interfaces:**
- Consumes: `pending_corrections_count/1`, `unseen_decisions_count/1`.
- Produces: `facts` gain `pending_corrections` (admins; else 0) and `decided_corrections` (teachers; else 0); items `nav-school-corrections` (Enseignant, section "Démarches") and `nav-school-correction-review` (Proviseur + Censeur, in "Pilotage" / "Suivi pédagogique"); item map gains `badge: integer | nil`.

- [ ] **Step 1: Failing tests** — Enseignant space has a "Démarches" section with "Corrections de notes" (badge = unseen decisions when > 0); Censeur/Proviseur have "Corrections de notes" with the pending count; Surveillant does not.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — in `facts/1` add the two counts (only compute each when the member's roles/teaching make it relevant, to avoid queries for others). `rail_link`: `attr :badge, :integer, default: nil` → `<span :if={@badge && @badge > 0} class="badge badge-warning badge-sm ml-auto">{@badge}</span>`; pass `badge={item[:badge]}` from the nav loop.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -m "feat: corrections in the role menus, with counts"`

---

### Task 9: Translations and final check

- [ ] `mix gettext.extract --merge`; fill `priv/gettext/en/LC_MESSAGES/default.po` for every new msgid (no new fuzzy entries left: `grep -c "#, fuzzy"` must not increase versus main).
- [ ] `mix compile --warnings-as-errors` → no warnings in changed files.
- [ ] `mix precommit` → all tests pass.
- [ ] Commit `chore: D3 translations`; update the memory note and the roadmap table (D3 done).
