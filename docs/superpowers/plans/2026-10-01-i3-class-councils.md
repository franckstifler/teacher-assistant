# I3 — Class councils (N11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Censeur or Proviseur holds each class's trimester council in the app — per-student distinction, conduct warning and appreciation, a printable procès-verbal — and its outcome is frozen onto the published report cards.

**Architecture:** Two resources (`ClassCouncil` per class × term, `CouncilDecision` per council × student) and a plain module `TeacherAssistant.Councils` (read with defaults, save, hold, reopen, lock, outcomes). `ReportCards.live_view/3` adds a `council` entry for trimesters and `publish/3` requires a held council. Two LiveViews (council list, council page), a print controller for the procès-verbal, and the report card / print / Bulletins screens read the council outcome.

**Tech Stack:** Elixir, Phoenix LiveView 1.8, Ash 3 (attribute multitenancy, policies, upsert), AshPostgres, Tailwind v4 + daisyUI, Gettext (French source strings).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`, section "I3 — Class councils (spec)". Mockup logic: `docs/superpowers/mockups/i3-conseils-de-classe.html`.

## Global Constraints

- Trimester councils only; annual councils are I4.
- Writes (header, decisions, hold, reopen): admin axis only (Proviseur, Censeur). Council screens and the procès-verbal: admin axis only.
- While the class's trimester is published (I2), every council write returns `{:error, :locked}`; the UI shows "Conseil verrouillé : bulletins publiés".
- `distinction_choice` nil = keep the I1 proposal; `:none` = no distinction. Appreciation trimmed, ≤ 300 characters.
- Publishing a trimester requires the council to be `:held` → `{:error, :council_not_held}`; annual publishing unchanged.
- New snapshots carry `council: %{held?, held_on, outcomes}` for trimesters (nil otherwise) and `snapshot_version: 2`; renderers read it with `Map.get(view, :council)` so version-1 snapshots still render.
- Scope-first domain functions, `scope: scope` on every Ash call, never `authorize?: false`; fixed value sets are `Ash.Type.Enum`.
- Migrations: `mix ash.codegen --dev`, then `mix ash.codegen class_councils`, then `mix ash.migrate`.
- UI strings French gettext sources; `mix gettext.extract --merge`, fill new `en` msgstrs, and fix any NEW fuzzy entries in en AND fr (merge fuzzy-matches new msgids to old ones).
- LiveViews start with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`.
- Work in worktree `.claude/worktrees/i3` (branch `i3-class-councils`); tests with `MIX_TEST_PARTITION=2`; stage explicit paths (never `commit -a`).
- Finish with `mix precommit` and `mix compile --warnings-as-errors`.

## Review Focus

1. Two admins saving the same student's decision at once: last write wins, no crash, still one decision row — Task 1 (upsert).
2. A student who joined the class after a decision was recorded, or left it: the page lists the current roster; outcomes ignore decisions for students not in the results — Task 1.
3. Editing a council whose term is published (stale page): refused with the lock message, nothing written — Task 1 and Task 3.
4. Holding a council for a class with no subjects (results nil): allowed, the procès-verbal prints with "—" statistics — Task 4.
5. A version-1 snapshot (published before I3) renders without crashing (no `council` key) — Task 4.

---

### Task 1: Council resources and the Councils module

**Files:**
- Create: `lib/teacher_assistant/academics/council_status.ex`, `conduct_warning.ex`, `council_distinction_choice.ex`, `class_council.ex`, `council_decision.ex`
- Create: `lib/teacher_assistant/councils.ex`
- Modify: `lib/teacher_assistant/assessment.ex` (alias list + `resource ClassCouncil`, `resource CouncilDecision`)
- Generated: migration `*_class_councils.exs`, snapshots
- Test: `test/teacher_assistant/councils_test.exs`

**Interfaces — Produces:**
- Enums: `CouncilStatus` (`:open | :held`), `ConductWarning` (`:avertissement_conduite | :blame_conduite`, `label/1`), `CouncilDistinctionChoice` (`Distinction.values() ++ [:none]`, `label/1`: `:none` → "Aucune", else `Distinction.label/1`).
- `Councils.council(scope, cg, term) :: %ClassCouncil{}` — the stored council with `decisions` loaded, or an unsaved default (`status: :open`, `held_on: term.class_council_date`, `decisions: []`, `id: nil`).
- `Councils.save_header(scope, cg, term, %{"held_on", "chair", "attendees", "observations"}) :: {:ok, council} | {:error, :locked | Ash.Error.t()}`
- `Councils.set_decision(scope, cg, term, student_id, %{"distinction_choice" => "" | value, "conduct_warning" => "" | value, "appreciation" => text}) :: {:ok, decision} | {:error, :locked | :invalid_choice | Ash.Error.t()}`
- `Councils.hold(scope, cg, term)`, `Councils.reopen(scope, cg, term) :: {:ok, council} | {:error, :locked | Ash.Error.t()}` (hold on a held council is `{:ok, council}`)
- `Councils.held?(scope, cg, term) :: boolean`, `Councils.locked?(scope, cg, term) :: boolean`
- `Councils.outcomes(council, results) :: %{student_id => %{distinction: atom | nil, conduct_warning: atom | nil, appreciation: String.t() | nil}}` (pure; `results` = `Bulletins.aggregate` map or nil → `%{}`)
- `Councils.default_term(terms, today) :: Term.t() | nil`
- `Councils.for_term(scope, term) :: %{class_group_id => ClassCouncil}` (one query)

- [ ] **Step 1: failing tests** — `test/teacher_assistant/councils_test.exs` (DataCase): setup a school with year, class "6e C" with two students (Awa 17 in Maths → Félicitations proposal; Bob 7 → Avertissement travail), a Maths course coefficient 1, an assessment in the term's first séquence. Tests:
  1. `council/3` default: `status == :open`, `held_on == term.class_council_date`, `id == nil`, `decisions == []`.
  2. `save_header` creates then updates (chair, attendees, observations, held_on parsed from "2026-01-15"); a second call keeps one council (`for_term` has one entry).
  3. `set_decision` upserts: choose `"encouragements"` for Awa, then `"none"`, then `""` → one row, last value `nil`; appreciation of 301 characters → `{:error, %Ash.Error.Invalid{}}`; `"bogus"` choice → `{:error, :invalid_choice}`; conduct warning `"blame_conduite"` stored.
  4. `outcomes/2` with results from `Assessment.class_results_for_period(scope, cg, {:trimester, term})`: no decision → I1 proposal (Awa `:felicitations`, Bob `:avertissement_travail`); choice `:encouragements` → `:encouragements`; `:none` → nil; a decision for a student id not in the results is ignored; `outcomes(council, nil) == %{}`.
  5. `hold` → `held?` true, `held_by_user_id` set; hold again ok; `reopen` → open.
  6. Lock: hold, publish the trimester (`ReportCards.publish`), then `save_header`, `set_decision`, `reopen` → `{:error, :locked}`; `locked?` true; after `ReportCards.withdraw` → writes succeed again.
  7. A plain teacher member (`TeacherFixtures.member_scope_fixture`) → `save_header` / `set_decision` / `hold` return `{:error, %Ash.Error.Forbidden{}}`.
  8. `default_term/2`: the term whose séquences contain the date, else the first; `[]` → nil.

- [ ] **Step 2: run, expect FAIL (`Councils` undefined).**

- [ ] **Step 3: implement.**

Enums (each `use Ash.Type.Enum`; labels via `use Gettext, backend: TeacherAssistantWeb.Gettext`):

```elixir
defmodule TeacherAssistant.Academics.CouncilStatus do
  @moduledoc "A class council is open (being prepared) or held (spec I3)."
  use Ash.Type.Enum, values: [:open, :held]
end

defmodule TeacherAssistant.Academics.ConductWarning do
  @moduledoc "A conduct warning given by the class council (spec I3)."
  use Ash.Type.Enum, values: [:avertissement_conduite, :blame_conduite]
  use Gettext, backend: TeacherAssistantWeb.Gettext
  def label(:avertissement_conduite), do: gettext("Avertissement de conduite")
  def label(:blame_conduite), do: gettext("Blâme de conduite")
end

defmodule TeacherAssistant.Academics.CouncilDistinctionChoice do
  @moduledoc "The council's work-distinction choice: one of the I1 distinctions, or none (spec I3)."
  use Ash.Type.Enum,
    values: [:felicitations, :encouragements, :tableau_honneur, :avertissement_travail, :blame_travail, :none]
  use Gettext, backend: TeacherAssistantWeb.Gettext
  def label(:none), do: gettext("Aucune")
  def label(value), do: TeacherAssistant.Academics.Distinction.label(value)
end
```

`ClassCouncil` (pattern of `BulletinPublication`: domain `TeacherAssistant.Assessment`, AshPostgres, policies, attribute multitenancy on `workspace_id`; table `class_councils`; references `class_group` (on_delete delete, match_with workspace, full, index), `term` (on_delete delete), `held_by` (nilify), `workspace`):
- attributes: `status` CouncilStatus default `:open` not null; `held_on :date`; `chair :string`; `attendees :string` (constraints `max_length: 2000`); `observations :string` (`max_length: 4000`); `held_at :utc_datetime_usec`; timestamps.
- relationships: belongs_to `class_group`, `term`, `held_by` (User, `held_by_user_id`), `workspace`; `has_many :decisions, CouncilDecision` (destination_attribute `class_council_id`).
- identity `:one_per_class_term [:class_group_id, :term_id]`.
- actions: `defaults [:read]`; `read :for_class_term` (args class_group_id, term_id; `get? true`; prepare load decisions); `read :for_term` (arg term_id); `create :open` accept `[:class_group_id, :term_id, :held_on, :chair, :attendees, :observations]`; `update :edit` accept `[:held_on, :chair, :attendees, :observations]`; `update :hold` (status held, `held_at` now, `held_by_user_id` actor); `update :reopen` (status open, held_at nil, held_by_user_id nil).
- policies: `action_type(:read)` → member; others → admin.

`CouncilDecision` (table `council_decisions`; references `class_council` delete+index, `student` delete, `workspace`):
- attributes: `distinction_choice` CouncilDistinctionChoice (nullable); `conduct_warning` ConductWarning (nullable); `appreciation :string` (`max_length: 300`, trimmed by default); timestamps.
- belongs_to `class_council` (allow_nil false), `student` (`TeacherAssistant.Academics.Student`, allow_nil false), `workspace`.
- identity `:one_per_student [:class_council_id, :student_id]`.
- actions: `defaults [:read]`; `create :record` accept `[:class_council_id, :student_id, :distinction_choice, :conduct_warning, :appreciation]`, `upsert? true`, `upsert_identity :one_per_student`, `upsert_fields [:distinction_choice, :conduct_warning, :appreciation, :updated_at]`.
- policies: read → member; `:record` → admin.

`lib/teacher_assistant/councils.ex`:

```elixir
defmodule TeacherAssistant.Councils do
  @moduledoc """
  Trimester class councils (spec I3): the council's header, a decision per student
  (distinction choice, conduct warning, appreciation), holding and reopening. A council
  is created by its first save. While the class's trimester is published (I2), every
  write is refused with `{:error, :locked}`.
  """
  require Ash.Query

  alias TeacherAssistant.Academics.{ClassCouncil, ClassGroup, CouncilDecision, Term}
  alias TeacherAssistant.{ReportCards, Scope}

  @doc "The stored council (decisions loaded) or an unsaved default."
  def council(%Scope{} = scope, %ClassGroup{} = cg, %Term{} = term) do
    stored(scope, cg, term) ||
      %ClassCouncil{
        class_group_id: cg.id,
        term_id: term.id,
        status: :open,
        held_on: term.class_council_date,
        decisions: []
      }
  end

  @doc "The term's councils by class, in one query."
  def for_term(%Scope{} = scope, %Term{id: term_id}) do
    ClassCouncil
    |> Ash.Query.for_read(:for_term, %{term_id: term_id}, scope: scope)
    |> Ash.read!()
    |> Map.new(&{&1.class_group_id, &1})
  end

  def held?(scope, cg, term), do: match?(%ClassCouncil{status: :held}, stored(scope, cg, term))

  def locked?(scope, cg, term),
    do: ReportCards.current_publication(scope, cg, {:trimester, term}) != nil

  def save_header(scope, cg, term, params) do
    attrs = Map.take(params, ~w(held_on chair attendees observations))

    with :ok <- unlocked(scope, cg, term),
         {:ok, council} <- ensure(scope, cg, term) do
      council |> Ash.Changeset.for_update(:edit, attrs, scope: scope) |> Ash.update()
    end
  end

  def set_decision(scope, cg, term, student_id, params) do
    with :ok <- unlocked(scope, cg, term),
         {:ok, choice} <- cast(TeacherAssistant.Academics.CouncilDistinctionChoice, params["distinction_choice"]),
         {:ok, warning} <- cast(TeacherAssistant.Academics.ConductWarning, params["conduct_warning"]),
         {:ok, council} <- ensure(scope, cg, term) do
      CouncilDecision
      |> Ash.Changeset.for_create(
        :record,
        %{
          class_council_id: council.id,
          student_id: student_id,
          distinction_choice: choice,
          conduct_warning: warning,
          appreciation: params["appreciation"]
        },
        scope: scope
      )
      |> Ash.create()
    end
  end

  def hold(scope, cg, term) do
    with :ok <- unlocked(scope, cg, term),
         {:ok, council} <- ensure(scope, cg, term) do
      if council.status == :held,
        do: {:ok, council},
        else: council |> Ash.Changeset.for_update(:hold, %{}, scope: scope) |> Ash.update()
    end
  end

  def reopen(scope, cg, term) do
    with :ok <- unlocked(scope, cg, term),
         %ClassCouncil{} = council <- stored(scope, cg, term) || {:ok, council(scope, cg, term)} do
      council |> Ash.Changeset.for_update(:reopen, %{}, scope: scope) |> Ash.update()
    end
  end

  @doc "Each graded student's council outcome: the council's choice or the I1 proposal."
  def outcomes(_council, nil), do: %{}

  def outcomes(%ClassCouncil{} = council, %{per_student: per_student}) do
    decisions = Map.new(council.decisions || [], &{&1.student_id, &1})

    Map.new(per_student, fn {student_id, data} ->
      d = Map.get(decisions, student_id)

      {student_id,
       %{
         distinction: distinction(d, data.distinction),
         conduct_warning: d && d.conduct_warning,
         appreciation: d && d.appreciation
       }}
    end)
  end

  @doc "The trimester whose séquences cover `today`, else the first; nil without terms."
  def default_term([], _today), do: nil

  def default_term([first | _] = terms, %Date{} = today) do
    Enum.find(terms, first, fn term ->
      Enum.any?(term.sequences, fn s ->
        Date.compare(s.start_date, today) != :gt and Date.compare(today, s.end_date) != :gt
      end)
    end)
  end

  defp distinction(%CouncilDecision{distinction_choice: :none}, _proposal), do: nil
  defp distinction(%CouncilDecision{distinction_choice: nil}, proposal), do: proposal
  defp distinction(%CouncilDecision{distinction_choice: choice}, _proposal), do: choice
  defp distinction(nil, proposal), do: proposal

  defp stored(scope, cg, term) do
    ClassCouncil
    |> Ash.Query.for_read(:for_class_term, %{class_group_id: cg.id, term_id: term.id}, scope: scope)
    |> Ash.read_one!()
  end

  defp ensure(scope, cg, term) do
    case stored(scope, cg, term) do
      %ClassCouncil{} = council ->
        {:ok, council}

      nil ->
        ClassCouncil
        |> Ash.Changeset.for_create(
          :open,
          %{class_group_id: cg.id, term_id: term.id, held_on: term.class_council_date},
          scope: scope
        )
        |> Ash.create()
        |> case do
          # Created concurrently by another page.
          {:error, %Ash.Error.Invalid{}} = error -> (c = stored(scope, cg, term)) && {:ok, c} || error
          other -> other
        end
    end
  end

  defp unlocked(scope, cg, term), do: if(locked?(scope, cg, term), do: {:error, :locked}, else: :ok)

  defp cast(_enum, value) when value in [nil, ""], do: {:ok, nil}

  defp cast(enum, value) when is_binary(value) do
    case Enum.find(enum.values(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_choice}
      atom -> {:ok, atom}
    end
  end

  defp cast(enum, value) when is_atom(value),
    do: if(value in enum.values(), do: {:ok, value}, else: {:error, :invalid_choice})
end
```

(Fix the `reopen/3` `with` clause when implementing: reopen a stored council; with none stored, return `{:ok, council(scope, cg, term)}` — nothing to reopen. Fix the `ensure/3` race branch into a readable `case`.)

Register both resources in `TeacherAssistant.Assessment`. Generate and apply the migration; check it creates both tables with the two unique indexes.

- [ ] **Step 4: run Task 1 tests → PASS. Step 5: commit** (`feat: class councils with per-student decisions`).

---

### Task 2: Report cards carry the council; publishing needs a held council

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (`live_view/3` council entry; `publish/3` gate; `outcome/2`, `final_distinction/3`, `published_class_ids/2`; `entry_rate` via `class_rates`)
- Modify: `lib/teacher_assistant/academics/bulletin_publication.ex` (`snapshot_version` 2)
- Modify: `lib/teacher_assistant/academics/entry_progress.ex` (`class_rates/3`; `class_rate/4` delegates)
- Modify: `test/support/fixtures/teacher_fixtures.ex` (`publish_trimester/3`)
- Modify every test that publishes a trimester (`grep -rn "publish(.*{:trimester" test`) to use `TeacherFixtures.publish_trimester(scope, cg, term)`
- Test: add to `test/teacher_assistant/report_cards_test.exs`, `test/teacher_assistant/academics/entry_progress_test.exs`

**Interfaces — Produces:**
- `view.council :: nil | %{held?: boolean, held_on: Date.t() | nil, outcomes: map}` (trimester only).
- `ReportCards.outcome(view, student_id) :: outcome | nil`; `ReportCards.final_distinction(view, student_id, data) :: atom | nil` (outcome's distinction when there is an outcome, else `data.distinction`).
- `ReportCards.publish/3` → `{:error, :council_not_held}` for a trimester without a held council.
- `ReportCards.published_class_ids(scope, period) :: MapSet.t()` (one query).
- `EntryProgress.class_rates(scope, year, sequences) :: %{class_group_id => rate | nil}` (one grid per séquence).
- `TeacherFixtures.publish_trimester(scope, cg, term)` — holds the council (ignoring the result) then returns `ReportCards.publish(scope, cg, {:trimester, term})`.

- [ ] **Step 1: failing tests:**
  - report_cards_test: "publishing a trimester needs a held council" (`{:error, :council_not_held}`, then hold → `{:ok, _}`; annual still publishes without a council); "the snapshot freezes the council" (decision Awa → `"tableau_honneur"` + appreciation "Bon trimestre" + hold + publish; then reopen is locked; withdraw, change the appreciation, republish → new snapshot shows the new text; the first stays in history with the old one: `hd(tl(history)).snapshot.council.outcomes[id].appreciation == "Bon trimestre"`); "final_distinction uses the council's choice" (choice `none` → nil although the proposal exists; no council (séquence view) → `data.distinction`); `snapshot_version == 2`.
  - entry_progress_test: `class_rates/3` returns the same per-class values as `class_rate/4` for `cg`, `cg2`, `empty_cg`.
- [ ] **Step 2: run → FAIL.**
- [ ] **Step 3: implement:**
  - `live_view/3`: add `council: council_entry(scope, cg, period, results)`, where `council_entry(scope, cg, {:trimester, term}, results)` = `c = Councils.council(scope, cg, term)`, `%{held?: c.status == :held, held_on: c.held_on, outcomes: Councils.outcomes(c, results)}` (compute `results` once and reuse it for `:results`), and `nil` for other periods.
  - `publish/3` trimester: before creating, `if not Councils.held?(scope, cg, term), do: {:error, :council_not_held}` (after the already-published check).
  - helpers:

```elixir
  @doc "The council outcome of a student in a view, or nil (no council, version-1 snapshot)."
  def outcome(view, student_id) do
    case Map.get(view, :council) do
      %{outcomes: outcomes} -> Map.get(outcomes, student_id)
      _ -> nil
    end
  end

  @doc "The distinction to show: the council's outcome when there is one, else the computed one."
  def final_distinction(view, student_id, data) do
    case outcome(view, student_id) do
      %{distinction: d} -> d
      nil -> data && data.distinction
    end
  end

  @doc "Classes whose report cards for `period` are published, in one query."
  def published_class_ids(%Scope{} = scope, period) do
    key = Organization.period_param(period)

    BulletinPublication
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.Query.filter(period_key == ^key and status == :published)
    |> Ash.read!()
    |> MapSet.new(& &1.class_group_id)
  end
```

  - `EntryProgress.class_rates/3`: build `grid/3` once per séquence, collect per row `cells` pcts into `%{cg_id => [pct]}`, then mean (div) per class, nil when empty; `class_rate/4` = `class_rates(scope, year, sequences) |> Map.get(cg_id)`.
  - snapshot_version 2 in `BulletinPublication :publish`.
  - fixture `publish_trimester/3`; rewrite the trimester publish calls in the existing tests to it. `bulletins_live_test` "incomplete entry asks for confirmation, then publishes": hold the council first with `TeacherAssistant.Councils.hold(ctx.scope, ctx.cg, ctx.term)`.
- [ ] **Step 4: full suite → PASS. Step 5: commit** (`feat: published report cards carry the class council; publishing needs it held`).

---

### Task 3: Council screens

**Files:**
- Create: `lib/teacher_assistant_web/live/school/councils_live.ex` (`/school/councils`), `lib/teacher_assistant_web/live/school/council_live.ex` (`/school/councils/:class_id`)
- Modify: `lib/teacher_assistant_web/router.ex` (both routes next to `/school/bulletins`), `lib/teacher_assistant_web/spaces.ex` (`councils()` after `bulletins()` for Proviseur and Censeur; helper `item("councils", gettext("Conseils de classe"), "hero-user-group", ~p"/school/councils")`)
- Test: `test/teacher_assistant_web/live/school/councils_live_test.exs`; update `test/teacher_assistant_web/spaces_test.exs` if it lists exact items

**Interfaces — Consumes:** `Councils.*`, `ReportCards.entry_rate`, `published_class_ids`, `EntryProgress.class_rates`, `Assessment.class_results_for_period`, `Enrollment.list_roster`. **Produces DOM ids:** list: `#councils-table`, `#council-row-<cg id>`, `#councils-ready`, `#term-<term id>`; page: `#council-header-form`, `#council-stats`, `#decision-<student id>` (form per row: selects `distinction_choice`, `conduct_warning`, input `appreciation`), `#saved-<student id>`, `#hold-council`, `#hold-confirm`, `#confirm-hold`, `#reopen-council`, `#council-status`, `#council-locked`, `#print-pv`.

- [ ] **Step 1: failing tests** (ConnCase, `register_and_log_in_user`; class 4e B with Djoumessi 15 and Tchinda 7 in Maths in the first term's first séquence):
  1. list shows the class with its rate and status "Saisie incomplète" (second séquence empty); `#councils-ready` "0 /"; clicking the row navigates to the council page.
  2. page: header form saves (chair "M. Fotso" persisted); `#council-stats` shows the class average; rows by rank with the I1 proposal (Djoumessi "Encouragements", Tchinda "Avertissement travail").
  3. changing Tchinda's row (`conduct_warning` = `avertissement_conduite`, appreciation "Doit se ressaisir") saves: `#saved-<id>` shown, `Councils.council` has the decision.
  4. hold below 100 % asks for confirmation; confirm → `#council-status` "Tenu"; `#reopen-council` → "Ouvert".
  5. after publishing the trimester (`TeacherFixtures.publish_trimester`), the page shows `#council-locked` and no `#hold-council`; a forced `decision` event returns the lock flash and writes nothing.
  6. a plain teacher member is redirected to `/school` from both routes; the menu has `a[href='/school/councils']` for the head.
- [ ] **Step 2: run → FAIL (no route).**
- [ ] **Step 3: implement** both LiveViews:
  - `CouncilsLive`: mount — admin axis (`ReportCards.can_publish?/1`) and a current year, else navigate `/school`; terms = `Organization.list_terms`; `handle_params` term from `?term=` or `Councils.default_term(terms, Reference.today())`; rows = `Enrollment.list_class_groups` with council (`Councils.for_term`), rate (`EntryProgress.class_rates(scope, year, term.sequences)`), published (`ReportCards.published_class_ids(scope, {:trimester, term})`); status: published → "Publié", held → "Tenu", rate == 100 → "Prêt", else "Saisie incomplète"; council date = council `held_on` or `term.class_council_date`; rows `navigate` to `/school/councils/<cg id>?term=<term id>`; header "n / N classes prêtes" (n = rate 100 or held or published).
  - `CouncilLive`: mount — admin axis, `Enrollment.fetch_owned_class_group`, terms; `handle_params` term; `load/1`: council (`Councils.council`), results (`Assessment.class_results_for_period(scope, cg, {:trimester, term})`), roster, outcomes, rate, locked (`Councils.locked?`); rows sorted by rank then name; events `save_header`, `decision` (params `student_id`, `distinction_choice`, `conduct_warning`, `appreciation`; `{:error, :locked}` → flash "Conseil verrouillé : bulletins publiés." and reload; ok → assign `saved: student_id` and reload council), `hold` (rate == 100 → hold; else `confirm_hold?: true`), `confirm_hold`, `cancel`, `reopen`. Disable every input and hide hold/reopen when locked. Selects: distinction `[{"Proposition", ""} | CouncilDistinctionChoice values with labels]`, conduct `[{"Aucun", ""}, …ConductWarning]`; appreciation input `maxlength="300"` `phx-debounce="blur"`. Statistics from `results` (class_average, pass_rate, by_sex), "—" when results nil.
- [ ] **Step 4: tests + spaces tests → PASS. Step 5: commit** (`feat: class council screens`).

---

### Task 4: Procès-verbal, report card, print and Bulletins show the council

**Files:**
- Create: `lib/teacher_assistant_web/controllers/council_print_controller.ex`, `council_print_html.ex`, `council_print_html/show.html.heex`
- Modify: router (`get "/school/councils/:class_id/print", CouncilPrintController, :show` in the `[:browser, :school]` scope next to the bulletin prints)
- Modify: `bulletin_live.ex` (final distinction; `#bulletin-council` with conduct warning and appreciation), `bulletin_print_html/show.html.heex` + `bulletin_print_controller.ex` (bundle `outcome`; appreciation text in the ruled block; conduct warning; final distinction), `bulletins_live.ex` (Distinction column and panel use `final_distinction`; for a trimester draft with the council not held, `#publish` is disabled and `#council-not-held` says "Conseil de classe non tenu"; `{:error, :council_not_held}` → that flash)
- Test: `test/teacher_assistant_web/controllers/council_print_controller_test.exs`; additions to `bulletin_live_test.exs`, `bulletin_print_controller_test.exs`, `bulletins_live_test.exs`

**Interfaces — Consumes:** `ReportCards.outcome/2`, `final_distinction/3`, `Councils.*`, `ConductWarning.label/1`.

- [ ] **Step 1: failing tests:**
  - PV: head gets 200 with the class label, "PROJET" while open, the chair, a student's appreciation and "Avertissement de conduite"; after hold no "PROJET"; a plain teacher is redirected to `/school`; a class with no subjects prints "—" statistics.
  - report card (trimester): with a decision (choice `none`, conduct `blame_conduite`, appreciation "Trimestre fragile") `#bulletin-council` shows "Blâme de conduite" and "Trimestre fragile", and `#bulletin-distinction` is empty although the proposal exists.
  - print (trimester): the appreciation text appears; séquence print unchanged; a version-1 snapshot renders (insert a publication whose snapshot has no `:council` key by publishing, then `Ash.Changeset.for_update(:update…)` is not available — instead call `ReportCards.outcome(Map.delete(view, :council), id) == nil` in a unit test and rely on `Map.get` in the templates).
  - Bulletins: trimester without held council → `#publish[disabled]` and `#council-not-held`; after `Councils.hold` the button is enabled; Distinction column shows the council's choice.
- [ ] **Step 2: run → FAIL.**
- [ ] **Step 3: implement.** PV controller: admin axis (`ReportCards.can_publish?`) + verified school + class + `?term=` resolved in `Organization.list_terms` (else redirect `/school/councils`); assigns school name, year, class, term, council (`Councils.council`), results, roster rows by rank with outcome, stats, distinction groups from outcomes (`Distinction.values()` order + conduct warnings), `draft?: council.status != :held`; layout off like the bulletin print; A4 CSS reused from the bulletin print (copy the `@page`/table styles). Report card / print: use `ReportCards.outcome(view, student.id)` (bundle key `outcome` in the print controller) and `final_distinction`.
- [ ] **Step 4: full suite → PASS. Step 5: commit** (`feat: procès-verbal and the council on report cards`).

---

### Task 5: Translations, checks, status

- [ ] `mix gettext.extract --merge`; fill new `en` msgstrs (Conseils de classe → "Class councils", Conseil de classe non tenu → "Class council not held", Conseil verrouillé : bulletins publiés. → "Council locked: report cards published.", Marquer le conseil tenu → "Mark the council as held", Rouvrir le conseil → "Reopen the council", Imprimer le procès-verbal → "Print the minutes", PROJET → "DRAFT", Avertissement de conduite → "Conduct warning", Blâme de conduite → "Conduct reprimand", Aucune / Aucun → "None", Proposition → "Proposal", Tenu → "Held", Ouvert → "Open", Prêt → "Ready", Saisie incomplète → "Entry incomplete", Président → "Chair", Présents → "Present", Observations générales → "General remarks", Le président du conseil → "Chair of the council", Le professeur principal → "Form master", Enregistré → "Saved", others literally); fix NEW fuzzy entries (compare with main) in en and fr.
- [ ] `MIX_TEST_PARTITION=2 mix precommit`, `mix compile --warnings-as-errors`, full suite green.
- [ ] Roadmap I3 status → implemented (branch `i3-class-councils`, this plan); commit `chore: I3 translations and status`.
