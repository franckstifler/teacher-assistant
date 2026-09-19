# prepare_source retrofit report

Branch: `refactor/idiomatic-ash-sweep`. Goal: move server-controlled ids/arguments
off the submitted form params and onto the changeset via `prepare_source`,
matching `lib/teacher_assistant_web/live/onboarding/create_school_live.ex`.

## Forms converted

### 1. `lib/teacher_assistant_web/live/school/classes_live.ex` — `create_class` (was line 152)

- Action: `TeacherAssistant.Academics.ClassGroup` `:create`
  (`accept [:label, :level, :serie, :subsystem, :workspace_id, :academic_year_id]`)
- Moved: `workspace_id`, `academic_year_id` — both **accepted attributes**, not
  arguments → `Ash.Changeset.change_attribute/3`.
- Before: `Map.merge(params, %{"workspace_id" => ..., "academic_year_id" => ...})`
  passed to `AshPhoenix.Form.submit(socket.assigns.class_form, params: submit_params)`.
- After: a fresh form is built in the handler (mirrors the reference file's
  pattern — `create_school_live.ex` also builds its submit-time form fresh
  rather than reusing the assign) with
  `prepare_source: fn changeset -> changeset |> change_attribute(:workspace_id, ...) |> change_attribute(:academic_year_id, ...) end`,
  and `AshPhoenix.Form.submit(form, params: submit_params)` where
  `submit_params` is now just `drop_blank_serie(params)` — no id keys.
- Confirmed: submitted params no longer contain `workspace_id`/`academic_year_id`.
- Left as-is: `drop_blank_serie/1` (nullifies an empty `"serie"` selection) —
  a genuine value transform, not a server-controlled id.

### 2. `lib/teacher_assistant_web/live/school/settings_live.ex` — `create_year` (was line 372)

- Action: `TeacherAssistant.Academics.AcademicYear` `:create_for_workspace`
  (`accept [:name, :start_date, :end_date, :active, :workspace_id]`)
- Moved: `workspace_id` (accepted attribute, the owning school) and `active`
  (accepted attribute; server-computed — `true` only when this is the
  workspace's first year — not user input, so it belongs in `prepare_source`
  alongside the id) → both via `Ash.Changeset.change_attribute/3`.
- Before: `Map.merge(params, %{"workspace_id" => ..., "active" => ...})`.
- After: form built with
  `prepare_source: fn changeset -> changeset |> change_attribute(:workspace_id, ...) |> change_attribute(:active, ...) end`,
  submitted with the raw `params` (no injected keys).
- Confirmed: submitted params no longer contain `workspace_id`/`active`.

### 3. `lib/teacher_assistant_web/live/school/settings_live.ex` — `create_subject` (was line 424)

- Action: `TeacherAssistant.Academics.Subject` `:create`
  (`accept [:name, :code, :default_coefficient, :category, :position, :active?, :workspace_id]`)
- Moved: `workspace_id` (accepted attribute) → `Ash.Changeset.change_attribute/3`.
- Before: `Map.put(params, "workspace_id", ws.id)`.
- After: form built with
  `prepare_source: fn changeset -> Ash.Changeset.change_attribute(changeset, :workspace_id, ws.id) end`,
  submitted with raw `params`.
- Confirmed: submitted params no longer contain `workspace_id`.
- Left as-is: the separate `update_subject` handler (`settings_live.ex:465` in
  the pre-existing numbering) — it `Map.put`s a *parsed* `default_coefficient`
  value (from `Curriculum.parse_coefficient/1`) into the params for an
  existing record's `for_update`. That's a value transform of user input, not
  an injected server-controlled id — left untouched, per instructions.

### 4. `lib/teacher_assistant_web/live/teacher/marks_live.ex` — `new_solo_assessment/2` (was line 212)

- Action: `TeacherAssistant.Academics.Assessment` `:create`
  (`accept [:label, :weight, :max_score, :given_on, :teaching_context_id, :sequence_id]`)
- Moved: `teaching_context_id`, `sequence_id` — both **accepted attributes**
  → `Ash.Changeset.change_attribute/3`.
- Before: `Map.merge(params, %{"teaching_context_id" => ..., "sequence_id" => ...})`
  submitted through the toolbar's persistent `new_assessment_form` assign.
- After: `new_solo_assessment/2` now builds its own form at submit time (the
  toolbar's `assessment_form/0` scaffold is unchanged and still renders the
  `:label` field) with
  `prepare_source: fn changeset -> changeset |> change_attribute(:teaching_context_id, ...) |> change_attribute(:sequence_id, ...) end`,
  submitted with the raw `params` (just `%{"label" => ...}`).
- Confirmed: submitted params no longer contain `teaching_context_id`/`sequence_id`.
- Updated the two doc comments above `assessment_form/0` and
  `new_solo_assessment/2` that described the old "merged in at submit time"
  behavior, to describe the `prepare_source` approach instead.

## Setter choice note

The task brief's pseudocode used `Ash.Changeset.set_attribute/3`; the actual
Ash 3 API for this is `Ash.Changeset.change_attribute/3` (`set_attribute/3`
does not exist — confirmed via `mix compile --warnings-as-errors`, which
flagged it as undefined). All four conversions use `change_attribute/3`
since in every case the field is an **accepted attribute** of the action
(verified against each resource's `actions do ... end` block), never an
action `argument`. No case in this sweep needed `set_argument/3` or
`manage_relationship`.

## Scanned, left unconverted (no id-injection into submitted params)

- `lib/teacher_assistant_web/live/school/periods_live.ex` — `update_period`:
  `for_update(period, ...)` already carries the record's own id; the only
  `Map.put` is `normalize_time_param/2` widening `"HH:MM"` to `"HH:MM:SS"`
  for the `:time` type — a value transform, not an id.
- `lib/teacher_assistant_web/live/school/settings_live.ex` — `save`,
  `save_profile`, `update_subject`: all `for_update` on a record that already
  carries its own id; `update_subject`'s only injected value is the parsed
  coefficient (value transform).
- `lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex` — both
  `for_update` forms (`header_form`, `step_form`) operate on records that
  already carry their own id; nothing injected into params.
- `lib/teacher_assistant_web/live/teacher/roster_live.ex` — `class_form`/
  `student_form` are scaffolds; `create_class`/`add_student` handlers call
  `Enrollment.create_class_group/3` and `Enrollment.add_student/2` directly,
  never `AshPhoenix.Form.submit`.
- `lib/teacher_assistant_web/live/school/members_live.ex` — `invite_form` is
  a scaffold; `invite` handler calls `Accounts.invite_member/3` directly.
- `lib/teacher_assistant_web/live/teacher/setup_live.ex` — `setup_form` is a
  scaffold spanning two resources; `save` handler calls
  `Organization.create_academic_year/2` + `Curriculum.create_teaching_context/3`
  directly.
- `lib/teacher_assistant_web/live/teacher/log_live.ex` — `log_form` is a
  scaffold; `save` handler calls `Curriculum.log_teaching/2` directly.
- `lib/teacher_assistant_web/live/teacher/fiche_live.ex` — `module_form`,
  `targets_form`, `entry_form_for/1` are all scaffolds; every handler
  (`add-module`, `save-targets`, `add-entry`, etc.) calls a `Curriculum.*`
  domain function directly, never `AshPhoenix.Form.submit`.
- `lib/teacher_assistant_web/live/teacher/marks_live.ex` — the marks-grid
  `Map.put`/`Map.merge` calls (`stash_current/1`, `restore_scores/2`,
  `restore_combined_scores/2`) build in-memory score caches keyed by
  assessment/student id; they don't touch any `AshPhoenix.Form` params at
  all, and are explicitly called out as not-to-convert in the task brief.

No `for_update` form in the sweep injected an id into params — in every case
the record itself (already carrying its id) was the form's subject.

## Tests

- No test asserted the old (id-containing) params shape, so no test edits
  were needed.
- `mix compile --warnings-as-errors`: clean.
- `mix test`: **643 tests, 0 failures** — same count as the stated baseline.

## Concerns

None. Every conversion is a mechanical move of a server-controlled id from
the submitted-params map to `prepare_source`, using `change_attribute/3`
because in every case Ash accepts the field as an attribute on the action
(never as an argument) — verified by reading each resource's action
definition before converting.
