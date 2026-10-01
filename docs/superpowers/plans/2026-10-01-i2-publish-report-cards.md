# I2 — Publish and freeze report cards (N13) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Proviseur or Censeur publishes a class's trimester or annual report cards, which freezes them; teachers of the class can then read them; a "Bulletins" screen drives it all.

**Architecture:** A new resource `BulletinPublication` stores, per class and period, a snapshot (an exact Erlang term) of the very map the screens render. A plain module `TeacherAssistant.ReportCards` builds that map live (`live_view/3`), publishes/withdraws, and answers "what may this user see" (`view_for/3`). The report card, class results and print switch from the calculators to `view_for/3`; a new `BulletinsLive` lists, previews, prints, publishes and withdraws.

**Tech Stack:** Elixir, Phoenix LiveView 1.8, Ash 3 (attribute multitenancy, policies, partial identity), AshPostgres, Tailwind v4 + daisyUI, Gettext (French source strings).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`, section "I2 — Publish and freeze report cards". **Mockup excerpt:** `docs/superpowers/mockups/i2-bulletins-publication.html` (generic list + detail markup; Censeur "Bulletins" logic: table Rang / Élève / Moy. gén. / Mention, detail panel lines per subject "Matière · coef n", Moyenne générale, Rang "n / effectif", Absences "n h", status Brouillon/Publié).

## Global Constraints

- Only `:trimester` and `:annual` periods are published; séquence periods are always live and never published.
- Publish and withdraw: admin axis only (Proviseur, Censeur). Withdrawal reason is required (trimmed, non-empty).
- At most one published publication per class and period; withdrawn rows stay as history; republishing creates a new row with a fresh snapshot.
- The snapshot is plain maps, Decimals and atoms only — no Ash records, no `%Ash.NotLoaded{}`.
- Drafts (live trimester/annual figures) are visible only to class managers (`Enrollment.class_manager?/2`: admin axis or the class's form master). Teachers with a course in the class see published periods only. Nobody else sees anything.
- Publishing below 100 % mark entry asks « Saisie incomplète : n %. Publier quand même ? » first.
- Scope-first domain functions, `scope: scope` on every Ash call, never `authorize?: false`.
- Migrations: `mix ash.codegen --dev`, then `mix ash.codegen bulletin_publications`, then `mix ash.migrate`. Never hand-written.
- New attributes with fixed values use `Ash.Type.Enum` (never bare `:atom`).
- UI strings are French `gettext` sources; finish with `mix gettext.extract --merge` and fill every new `en` msgstr.
- LiveViews start with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`; `<.input>` for inputs; `<.icon>` for icons; theme colors only (`primary`, `warning`, `error`, `success`, `base-*`).
- Dates shown as `dd/mm/yyyy` in school time (WAT = UTC+1): `published_at |> DateTime.add(3600) |> DateTime.to_date()`.
- Finish with `mix precommit` AND `mix compile --warnings-as-errors`; commit after precommit (its formatter rewrites files).
- Branch `i2-publish-report-cards`; one commit per task.

## Review Focus

1. Two clicks (or two admins) publishing the same class and period: the second gets « Bulletins déjà publiés. », no crash, still one published row — Task 1.
2. A student enrolled after publication: the published list does not include them and their report card page shows « Absent des bulletins publiés de cette période. » instead of crashing — Task 3.
3. A teacher opening a draft trimester, a séquence or the print URL by hand: no live figures are computed for them (no forbidden error), they see « Pas encore publiés » or are redirected — Task 3.
4. A withdrawal reason of only spaces is refused and the class stays published — Task 1.
5. A mark, coefficient or appreciation-band change after publishing leaves the published card unchanged; withdraw + republish picks the change up — Task 1.

---

### Task 1: Publication resource and ReportCards core (snapshot, publish, withdraw, history)

**Files:**
- Create: `lib/teacher_assistant/academics/publication_period_kind.ex`, `lib/teacher_assistant/academics/publication_status.ex`, `lib/teacher_assistant/academics/bulletin_publication.ex`
- Create: `lib/teacher_assistant/report_cards.ex`
- Modify: `lib/teacher_assistant/assessment.ex:36-40` (register the resource in the domain's `resources do` block and its alias list at the top)
- Generated: `priv/repo/migrations/*_bulletin_publications.exs`, `priv/resource_snapshots/repo/bulletin_publications/*.json`
- Test: `test/teacher_assistant/report_cards_test.exs`

**Interfaces:**
- Produces:
  - `TeacherAssistant.Academics.PublicationPeriodKind` (`:trimester | :annual`), `PublicationStatus` (`:published | :withdrawn`, `label/1`).
  - `BulletinPublication` fields: `class_group_id`, `academic_year_id`, `term_id` (nil for annual), `period_kind`, `period_key` (`Organization.period_param/1`: `"trim:<id>"` or `"annee"`), `status`, `snapshot`, `snapshot_version` (1), `published_at`, `published_by_user_id`, `withdrawn_at`, `withdrawn_by_user_id`, `withdrawal_reason`; relationships `published_by`, `withdrawn_by` (User). Actions `:publish`, `:withdraw` (argument `reason`), read `:for_class` (argument `class_group_id`, newest first, loads `:published_by, :withdrawn_by`).
  - `ReportCards.live_view(scope, cg, period) :: view` where `view :: %{results: map | nil, roster: [%{student: %{id, full_name, matricule, sex}, enrollment: %{id, repeater}}], conduct: %{enrollment_id => map}, discipline: %{enrollment_id => %{sanctions: [map], consignes_count, note_de_conduite}}, form_master: %{name, email} | nil, group_subtotals?: boolean}`
  - `ReportCards.class_view(scope, cg, period) :: {:published, BulletinPublication.t(), view} | {:draft, view}`
  - `ReportCards.current_publication(scope, cg, period) :: BulletinPublication.t() | nil`
  - `ReportCards.history(scope, cg, period) :: [BulletinPublication.t()]` (newest first)
  - `ReportCards.publish(scope, cg, period) :: {:ok, pub} | {:error, :already_published | :not_publishable | Ash.Error.t()}`
  - `ReportCards.withdraw(scope, pub, reason) :: {:ok, pub} | {:error, Ash.Error.t()}`
  - `ReportCards.published_on(pub) :: Date.t()` (school-local date)

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant/report_cards_test.exs`:

```elixir
defmodule TeacherAssistant.ReportCardsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    [term | _] = Organization.list_terms(scope, year)
    [seq | _] = term.sequences
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M1"})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(2)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: st}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new(15)}])

    %{scope: scope, year: year, term: term, seq: seq, cg: cg, a: a, st: st, head: head}
  end

  defp moyenne({_, view}), do: moyenne(view)
  defp moyenne({_, _pub, view}), do: moyenne(view)
  defp moyenne(%{results: r, roster: [%{student: %{id: id}} | _]}), do: r.per_student[id].moyenne_generale

  test "a draft is live; a séquence is always a draft", %{scope: scope, cg: cg, term: term, seq: seq} do
    assert {:draft, view} = ReportCards.class_view(scope, cg, {:trimester, term})
    assert [%{student: %{full_name: "Awa", matricule: "M1"}, enrollment: %{repeater: false}}] =
             view.roster

    assert Decimal.equal?(moyenne(view), 15)
    assert {:error, :not_publishable} = ReportCards.publish(scope, cg, {:sequence, seq})
    assert {:draft, _} = ReportCards.class_view(scope, cg, {:sequence, seq})
  end

  test "publishing freezes the report cards", ctx do
    %{scope: scope, cg: cg, term: term, a: a, st: st} = ctx
    assert {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert pub.status == :published
    assert pub.period_key == "trim:" <> term.id
    assert pub.published_by_user_id == scope.current_user.id

    # changes after publication: a mark, the averaging rounding, the appreciation scale
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new(4)}])
    {:ok, _} = Assessment.update_grading_rules(scope, %{"average_rounding" => "quarter"})

    {:ok, _} =
      Assessment.update_appreciation_bands(scope, [%{from: "0", label: "X"}, %{from: "10", label: "Y"}])

    assert {:published, ^pub, view} = ReportCards.class_view(scope, cg, {:trimester, term})
    assert Decimal.equal?(moyenne(view), 15)
    [%{student: %{id: id}}] = view.roster
    assert view.results.per_student[id].mention.label == "Bien"

    # withdraw + republish picks the change up
    assert {:ok, withdrawn} = ReportCards.withdraw(scope, pub, "Erreur de saisie en maths")
    assert withdrawn.status == :withdrawn
    assert withdrawn.withdrawal_reason == "Erreur de saisie en maths"
    assert {:draft, live} = ReportCards.class_view(scope, cg, {:trimester, term})
    assert Decimal.equal?(moyenne(live), 4)

    assert {:ok, republished} = ReportCards.publish(scope, cg, {:trimester, term})
    assert [first, second] = ReportCards.history(scope, cg, {:trimester, term})
    assert first.id == republished.id
    assert first.status == :published
    assert second.status == :withdrawn
  end

  test "publishing twice is refused; annual is its own period", %{scope: scope, cg: cg, term: term, year: year} do
    assert {:ok, _} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:error, :already_published} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:ok, annual} = ReportCards.publish(scope, cg, {:annual, year})
    assert annual.period_key == "annee"
    assert annual.term_id == nil
    assert length(ReportCards.history(scope, cg, {:trimester, term})) == 1
  end

  test "a withdrawal needs a reason", %{scope: scope, cg: cg, term: term} do
    {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:error, %Ash.Error.Invalid{}} = ReportCards.withdraw(scope, pub, "   ")
    assert {:published, _, _} = ReportCards.class_view(scope, cg, {:trimester, term})
  end

  test "only the admin axis publishes and withdraws", %{scope: scope, cg: cg, term: term} do
    teacher_scope = TeacherFixtures.member_scope_fixture(scope)
    teacher_scope = %{teacher_scope | current_academic_year: scope.current_academic_year}
    assert {:error, %Ash.Error.Forbidden{}} = ReportCards.publish(teacher_scope, cg, {:trimester, term})

    {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert {:error, %Ash.Error.Forbidden{}} = ReportCards.withdraw(teacher_scope, pub, "Non")
  end

  test "published_on is the school-local date", %{scope: scope, cg: cg, term: term} do
    {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})
    assert %Date{} = ReportCards.published_on(pub)
    assert ReportCards.published_on(%{pub | published_at: ~U[2026-01-10 23:30:00Z]}) == ~D[2026-01-11]
  end
end
```

(If `school_fixture/0` leaves `current_academic_year` nil, the `%{scope | current_academic_year: year}` line above sets it; `member_scope_fixture/2` builds a scope without a year, hence the same fix there.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant/report_cards_test.exs`
Expected: FAIL — `ReportCards` undefined.

- [ ] **Step 3: Implement the resource**

`lib/teacher_assistant/academics/publication_period_kind.ex`:

```elixir
defmodule TeacherAssistant.Academics.PublicationPeriodKind do
  @moduledoc "The period a report-card publication covers (spec I2): a trimester or the year."
  use Ash.Type.Enum, values: [:trimester, :annual]
end
```

`lib/teacher_assistant/academics/publication_status.ex`:

```elixir
defmodule TeacherAssistant.Academics.PublicationStatus do
  @moduledoc "A report-card publication is in force (`:published`) or was withdrawn (spec I2)."
  use Ash.Type.Enum, values: [:published, :withdrawn]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:published), do: gettext("Publié")
  def label(:withdrawn), do: gettext("Retiré")
end
```

`lib/teacher_assistant/academics/bulletin_publication.ex`:

```elixir
defmodule TeacherAssistant.Academics.BulletinPublication do
  @moduledoc """
  A class's report cards for a trimester or the year, published (spec I2). The
  `snapshot` is exactly what the report card, class results and print render
  (`TeacherAssistant.ReportCards.live_view/3`), stored as an Erlang term so decimals
  and atoms come back unchanged: nothing later changes a published card. A withdrawal
  keeps the row as history; republishing creates a new row.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "bulletin_publications"
    repo TeacherAssistant.Repo

    identity_wheres_to_sql one_published_per_period: "status = 'published'"

    references do
      reference :class_group,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full

      reference :term, on_delete: :delete
      reference :published_by, on_delete: :nilify
      reference :withdrawn_by, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    read :for_class do
      argument :class_group_id, :uuid, allow_nil?: false
      filter expr(class_group_id == ^arg(:class_group_id))
      prepare build(sort: [published_at: :desc], load: [:published_by, :withdrawn_by])
    end

    create :publish do
      accept [:class_group_id, :academic_year_id, :term_id, :period_kind, :period_key, :snapshot]
      change set_attribute(:status, :published)
      change set_attribute(:snapshot_version, 1)
      change set_attribute(:published_at, &DateTime.utc_now/0)
      change set_attribute(:published_by_user_id, actor(:id))
    end

    update :withdraw do
      require_atomic? false
      argument :reason, :string, allow_nil?: false
      validate attribute_equals(:status, :published)
      change set_attribute(:status, :withdrawn)
      change set_attribute(:withdrawal_reason, arg(:reason))
      change set_attribute(:withdrawn_at, &DateTime.utc_now/0)
      change set_attribute(:withdrawn_by_user_id, actor(:id))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action([:publish, :withdraw]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :period_kind, TeacherAssistant.Academics.PublicationPeriodKind,
      allow_nil?: false,
      public?: true

    # `Organization.period_param/1` of the period: "trim:<term id>" or "annee".
    attribute :period_key, :string, allow_nil?: false, public?: true

    attribute :status, TeacherAssistant.Academics.PublicationStatus,
      allow_nil?: false,
      default: :published,
      public?: true

    attribute :snapshot, :term, allow_nil?: false, public?: true
    attribute :snapshot_version, :integer, allow_nil?: false, default: 1, public?: true
    attribute :published_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :withdrawn_at, :utc_datetime_usec, public?: true
    attribute :withdrawal_reason, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :term, TeacherAssistant.Academics.Term do
      source_attribute :term_id
      public? true
    end

    belongs_to :published_by, TeacherAssistant.Accounts.User do
      source_attribute :published_by_user_id
      public? true
    end

    belongs_to :withdrawn_by, TeacherAssistant.Accounts.User do
      source_attribute :withdrawn_by_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_published_per_period, [:class_group_id, :period_key],
      where: expr(status == :published)
  end
end
```

Register it in `lib/teacher_assistant/assessment.ex`: add `BulletinPublication` to the `alias TeacherAssistant.Academics.{…}` list and `resource BulletinPublication` after `resource MarkCorrection`. (Check the module paths of `ClassGroup`, `AcademicYear`, `Term`, `Workspace` in `lib/teacher_assistant/academics/` match the `belongs_to` targets; they are the ones `MarkCorrection` and `Enrollment` use.)

Generate and apply:

```bash
mix ash.codegen --dev
mix ash.codegen bulletin_publications
mix ash.migrate
```

Check the migration creates `bulletin_publications` with a `bytea` `snapshot` and the partial unique index `WHERE status = 'published'`.

- [ ] **Step 4: Implement ReportCards**

`lib/teacher_assistant/report_cards.ex`:

```elixir
defmodule TeacherAssistant.ReportCards do
  @moduledoc """
  Report-card publication (spec I2). A class's trimester or annual report cards are a
  draft (live figures) until the Proviseur or Censeur publishes them; publishing stores
  `live_view/3` as a snapshot, which every screen then renders instead of live figures.
  Séquence report cards are always live.
  """
  require Ash.Query

  alias TeacherAssistant.{Accounts, Assessment, Attendance, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{BulletinPublication, ClassGroup, Term}
  alias TeacherAssistant.Scope

  @doc "What the report card, class results and print render, computed now."
  def live_view(%Scope{} = scope, %ClassGroup{} = cg, period) do
    fm = Enrollment.form_master(scope, cg)

    %{
      results: Assessment.class_results_for_period(scope, cg, period),
      roster: scope |> Enrollment.list_roster(cg) |> Enum.map(&plain_entry/1),
      conduct: Attendance.class_conduct(scope, cg, period),
      discipline:
        scope
        |> Discipline.class_discipline(cg, period)
        |> Map.new(fn {id, summary} -> {id, plain_discipline(summary)} end),
      form_master: fm && %{name: fm.name, email: to_string(fm.email)},
      group_subtotals?: group_subtotals?(scope)
    }
  end

  @doc "The published snapshot when there is one, else the live draft."
  def class_view(%Scope{} = scope, %ClassGroup{} = cg, period) do
    case current_publication(scope, cg, period) do
      nil -> {:draft, live_view(scope, cg, period)}
      pub -> {:published, pub, pub.snapshot}
    end
  end

  @doc "The publication in force for the class and period, or nil (always nil for a séquence)."
  def current_publication(_scope, _cg, {:sequence, _}), do: nil

  def current_publication(%Scope{} = scope, %ClassGroup{} = cg, period),
    do: scope |> history(cg, period) |> Enum.find(&(&1.status == :published))

  @doc "Every publication of the class for the period, newest first."
  def history(_scope, _cg, {:sequence, _}), do: []

  def history(%Scope{} = scope, %ClassGroup{id: cg_id}, period) do
    key = Organization.period_param(period)

    BulletinPublication
    |> Ash.Query.for_read(:for_class, %{class_group_id: cg_id}, scope: scope)
    |> Ash.Query.filter(period_key == ^key)
    |> Ash.read!()
  end

  @doc "Publishes (freezes) the class's report cards for a trimester or the year."
  def publish(_scope, _cg, {:sequence, _}), do: {:error, :not_publishable}

  def publish(%Scope{} = scope, %ClassGroup{} = cg, {kind, _} = period)
      when kind in [:trimester, :annual] do
    if current_publication(scope, cg, period) do
      {:error, :already_published}
    else
      BulletinPublication
      |> Ash.Changeset.for_create(
        :publish,
        %{
          class_group_id: cg.id,
          academic_year_id: cg.academic_year_id,
          term_id: term_id(period),
          period_kind: kind,
          period_key: Organization.period_param(period),
          snapshot: live_view(scope, cg, period)
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        # A concurrent publish won the race: the partial unique identity refused this one.
        {:error, %Ash.Error.Invalid{}} = error ->
          if current_publication(scope, cg, period), do: {:error, :already_published}, else: error

        other ->
          other
      end
    end
  end

  @doc "Withdraws a publication; `reason` is required."
  def withdraw(%Scope{} = scope, %BulletinPublication{} = pub, reason) do
    pub
    |> Ash.Changeset.for_update(:withdraw, %{reason: reason}, scope: scope)
    |> Ash.update()
  end

  @doc "The school-local (WAT, UTC+1) date of a publication."
  def published_on(%{published_at: at}), do: at |> DateTime.add(3600) |> DateTime.to_date()

  defp term_id({:trimester, %Term{id: id}}), do: id
  defp term_id(_), do: nil

  defp plain_entry(%{student: s, enrollment: e}) do
    %{
      student: %{id: s.id, full_name: s.full_name, matricule: s.matricule, sex: s.sex},
      enrollment: %{id: e.id, repeater: e.repeater}
    }
  end

  defp plain_discipline(summary) do
    %{
      summary
      | sanctions:
          Enum.map(summary.sanctions, &Map.take(&1, [:id, :type, :date, :reason, :duration_days]))
    }
  end

  defp group_subtotals?(scope) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> profile.bulletin_group_subtotals?
      _ -> false
    end
  end
end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/teacher_assistant/report_cards_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant priv/repo priv/resource_snapshots test/teacher_assistant/report_cards_test.exs
git commit -m "feat: publish and freeze a class's report cards"
```

---

### Task 2: Who sees what, visible classes, mark-entry rate

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (access functions, `entry_rate/3`, `periods/2`)
- Modify: `lib/teacher_assistant/academics/entry_progress.ex` (add `class_rate/4`)
- Test: `test/teacher_assistant/report_cards_access_test.exs`; add a test to `test/teacher_assistant/academics/entry_progress_test.exs`

**Interfaces:**
- Consumes: Task 1 `class_view/3`, `current_publication/3`.
- Produces:
  - `ReportCards.access(scope, cg) :: :full | :published | :none` — `:full` = `Enrollment.class_manager?/2`; `:published` = a course (`TeachingContext.teacher_user_id`, solo or combined) in the class this year; else `:none`.
  - `ReportCards.view_for(scope, cg, period) :: {:published, pub, view} | {:draft, view} | :not_published | :forbidden` — never computes live figures for a `:published`-access user.
  - `ReportCards.can_publish?(scope) :: boolean` (admin axis).
  - `ReportCards.visible_classes(scope, year) :: [ClassGroup.t()]` — all classes for the admin axis; else the classes the user is form master of or teaches.
  - `ReportCards.periods(scope, year) :: [{param :: String.t(), label :: String.t(), period}]` — the year's terms ("Trimestre n", `"trim:<id>"`) then `{"annee", "Année", {:annual, year}}`.
  - `ReportCards.entry_rate(scope, cg, period) :: non_neg_integer | nil` — the class's courses × the period's séquences, mean of the cells' % (F's rules: a course with students but no assessment in a séquence is 0 %), rounded down; nil when the class has no course.
  - `EntryProgress.class_rate(scope, year, cg, sequences) :: non_neg_integer | nil`

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant/report_cards_access_test.exs`:

```elixir
defmodule TeacherAssistant.ReportCardsAccessTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "5e B", level: "5ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    %{teacher: teacher, scope: tscope, teaching_context: tc} =
      TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg})

    tscope = %{tscope | current_academic_year: year}
    [term | _] = Organization.list_terms(scope, year)
    %{scope: scope, tscope: tscope, teacher: teacher, tc: tc, cg: cg, other: other, term: term, year: year}
  end

  test "access: admin full, teacher of the class published, others none", ctx do
    assert ReportCards.access(ctx.scope, ctx.cg) == :full
    assert ReportCards.access(ctx.tscope, ctx.cg) == :published
    assert ReportCards.access(ctx.tscope, ctx.other) == :none
    assert ReportCards.can_publish?(ctx.scope)
    refute ReportCards.can_publish?(ctx.tscope)
  end

  test "a teacher sees only published periods, never live figures", ctx do
    period = {:trimester, ctx.term}
    assert ReportCards.view_for(ctx.tscope, ctx.cg, period) == :not_published
    [seq | _] = ctx.term.sequences
    assert ReportCards.view_for(ctx.tscope, ctx.cg, {:sequence, seq}) == :not_published
    assert ReportCards.view_for(ctx.tscope, ctx.other, period) == :forbidden

    assert {:draft, _} = ReportCards.view_for(ctx.scope, ctx.cg, period)
    {:ok, pub} = ReportCards.publish(ctx.scope, ctx.cg, period)
    assert {:published, %{id: id}, _view} = ReportCards.view_for(ctx.tscope, ctx.cg, period)
    assert id == pub.id
  end

  test "visible classes", ctx do
    assert ctx.scope |> ReportCards.visible_classes(ctx.year) |> Enum.map(& &1.id) |> Enum.member?(ctx.other.id)
    assert ctx.tscope |> ReportCards.visible_classes(ctx.year) |> Enum.map(& &1.id) == [ctx.cg.id]
  end

  test "periods are the terms then the year", ctx do
    params = ctx.scope |> ReportCards.periods(ctx.year) |> Enum.map(&elem(&1, 0))
    assert List.last(params) == "annee"
    assert length(params) == length(Organization.list_terms(ctx.scope, ctx.year)) + 1
    assert hd(params) == "trim:" <> ctx.term.id
  end

  test "entry rate over the term's séquences", ctx do
    period = {:trimester, ctx.term}
    assert ReportCards.entry_rate(ctx.scope, ctx.cg, period) == 0

    [seq | _] = ctx.term.sequences

    {:ok, a} =
      Assessment.create_assessment(ctx.scope, ctx.tc, seq, %{
        label: "D",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: st}] = Enrollment.list_roster(ctx.scope, ctx.cg)
    :ok = Assessment.upsert_marks(ctx.scope, a, [%{student_id: st.id, score: Decimal.new(12)}])
    # first séquence complete, second séquence has no assessment yet (0 %)
    assert ReportCards.entry_rate(ctx.scope, ctx.cg, period) == 50

    for seq <- tl(ctx.term.sequences) do
      {:ok, b} =
        Assessment.create_assessment(ctx.scope, ctx.tc, seq, %{
          label: "D",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      :ok = Assessment.upsert_marks(ctx.scope, b, [%{student_id: st.id, score: Decimal.new(12)}])
    end

    assert ReportCards.entry_rate(ctx.scope, ctx.cg, period) == 100
  end
end
```

In `test/teacher_assistant/academics/entry_progress_test.exs`, add a test for `class_rate/4` reusing the file's existing setup and its two-student class: one course, an assessment in the first of two séquences with one of the two students marked (cell 50 %), nothing in the second séquence (cell 0 %) → `class_rate(scope, year, cg, [seq1, seq2]) == 25`; and a class with no course → `nil`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant/report_cards_access_test.exs test/teacher_assistant/academics/entry_progress_test.exs`
Expected: FAIL — `access/2` undefined.

- [ ] **Step 3: Implement**

In `lib/teacher_assistant/academics/entry_progress.ex` (add `ClassGroup` to the `alias TeacherAssistant.Academics.{…}` list):

```elixir
  @doc """
  One class's mark-entry rate over `sequences` (spec I2: a trimester's or the year's
  séquences): the mean of its course cells' % across those séquences, with the cell
  rules of `grid/3` (a course with students but no assessment is 0 %); rounded down,
  nil when no cell has a %.
  """
  def class_rate(%Scope{} = scope, %AcademicYear{} = year, %ClassGroup{id: cg_id}, sequences) do
    pcts =
      Enum.flat_map(sequences, fn seq ->
        scope
        |> grid(year, seq)
        |> Map.fetch!(:rows)
        |> Enum.find(&(&1.class_group.id == cg_id))
        |> case do
          nil -> []
          row -> row.cells |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.map(& &1.pct)
        end
      end)
      |> Enum.reject(&is_nil/1)

    case pcts do
      [] -> nil
      _ -> div(Enum.sum(pcts), length(pcts))
    end
  end
```

In `lib/teacher_assistant/report_cards.ex` add (aliases: `Curriculum`, `TeacherAssistant.Academics.{AcademicYear, EntryProgress}`, `TeacherAssistant.Accounts.Checks`; `use Gettext, backend: TeacherAssistantWeb.Gettext` for the period labels):

```elixir
  @doc "`:full` (drafts and published), `:published` (published only) or `:none`."
  def access(%Scope{} = scope, %ClassGroup{} = cg) do
    cond do
      Enrollment.class_manager?(scope, cg) -> :full
      teaches_class?(scope, cg) -> :published
      true -> :none
    end
  end

  @doc """
  What `scope` may see of the class's report cards for `period`. Live figures are only
  ever computed for `:full` access.
  """
  def view_for(%Scope{} = scope, %ClassGroup{} = cg, period) do
    case access(scope, cg) do
      :none ->
        :forbidden

      :full ->
        class_view(scope, cg, period)

      :published ->
        case current_publication(scope, cg, period) do
          nil -> :not_published
          pub -> {:published, pub, pub.snapshot}
        end
    end
  end

  @doc "Whether the scope may publish and withdraw (Proviseur, Censeur)."
  def can_publish?(%Scope{current_user: %{} = user, current_workspace: %{id: ws_id}}),
    do: Checks.SchoolRole.holds?(user, ws_id, :admin)

  def can_publish?(_scope), do: false

  @doc "The classes whose report cards the scope may open this year."
  def visible_classes(%Scope{current_user: user} = scope, %AcademicYear{} = year) do
    classes = Enrollment.list_class_groups(scope, year)

    if can_publish?(scope) do
      classes
    else
      taught = taught_class_ids(scope, year)
      Enum.filter(classes, &(&1.form_master_user_id == user.id or MapSet.member?(taught, &1.id)))
    end
  end

  @doc "The publishable periods of the year: its trimesters, then the year."
  def periods(%Scope{} = scope, %AcademicYear{} = year) do
    terms =
      scope
      |> Organization.list_terms(year)
      |> Enum.map(fn t ->
        period = {:trimester, t}
        {Organization.period_param(period), gettext("Trimestre %{n}", n: t.position), period}
      end)

    terms ++ [{"annee", gettext("Année"), {:annual, year}}]
  end

  @doc "The class's mark-entry rate over the period's séquences (rounded down; nil = nothing expected)."
  def entry_rate(%Scope{} = scope, %ClassGroup{} = cg, {:trimester, %Term{} = term}) do
    EntryProgress.class_rate(scope, year_of(scope, cg), cg, term.sequences)
  end

  def entry_rate(%Scope{} = scope, %ClassGroup{} = cg, {:annual, %AcademicYear{} = year}) do
    EntryProgress.class_rate(scope, year, cg, Organization.list_sequences(scope, year))
  end

  defp year_of(%Scope{current_academic_year: %AcademicYear{id: id} = year}, %ClassGroup{academic_year_id: id}),
    do: year

  defp year_of(_scope, %ClassGroup{academic_year_id: id, workspace_id: ws}),
    do: %AcademicYear{id: id, workspace_id: ws}

  defp teaches_class?(%Scope{current_academic_year: %AcademicYear{} = year} = scope, cg),
    do: MapSet.member?(taught_class_ids(scope, year), cg.id)

  defp teaches_class?(_scope, _cg), do: false

  defp taught_class_ids(%Scope{current_user: %{} = user} = scope, year) do
    scope
    |> Curriculum.list_assignments_for_user(year, user)
    |> MapSet.new(& &1.class_group_id)
  end

  defp taught_class_ids(_scope, _year), do: MapSet.new()
```

(`term.sequences` must be loaded: `Organization.list_terms/2` and `Organization.resolve_period/3` load them through `Term`'s `:for_academic_year` read. If `EntryProgress.grid/3` needs more than the year's id from the `%AcademicYear{}` built in `year_of/2`, pass `scope.current_academic_year` instead — check what `grid/3` reads from `year`.)

Append to the module's moduledoc: "`view_for/3` decides what a user may see: class managers see drafts and publications, teachers of the class publications only."

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/teacher_assistant/report_cards_access_test.exs test/teacher_assistant/academics/entry_progress_test.exs test/teacher_assistant/report_cards_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant test/teacher_assistant
git commit -m "feat: report-card access, visible classes and period entry rate"
```

---

### Task 3: Report card, class results and print read through `view_for/3`

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex` (mount, handle_params, render: published line, not-published and absent states)
- Modify: `lib/teacher_assistant_web/live/school/results_live.ex` (mount, `select_period/2`, render)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` (access, view, assigns)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex` (watermark, published line)
- Test: `test/teacher_assistant_web/live/school/bulletin_live_test.exs`, `test/teacher_assistant_web/live/school/results_live_test.exs`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`

**Interfaces:**
- Consumes: `ReportCards.view_for/3`, `access/2`, `published_on/1`, `publish/3` (tests); the `view` map (Task 1).
- Produces: DOM ids `#bulletin-published`, `#bulletin-not-published`, `#bulletin-absent`, `#results-published`, `#results-not-published`; print CSS classes `.watermark`, `.published`.

- [ ] **Step 1: Write the failing tests**

In `bulletin_live_test.exs` (its setup has the head `scope`, class `cg`, Awa's `enr`, `seq`; terms come from `Organization.list_terms(scope, scope.current_academic_year || year)` — the setup creates `year`; return it from the setup map if it is not already returned):

```elixir
  describe "publication" do
    setup %{scope: scope, cg: cg} do
      year = TeacherAssistant.Organization.current_academic_year(scope)
      [term | _] = Organization.list_terms(scope, year)
      scope = %{scope | current_academic_year: year}
      %{term: term, scope: scope}
    end

    test "a published trimester shows its publication date and stays frozen", ctx do
      %{conn: conn, cg: cg, enr: enr, term: term, scope: scope} = ctx
      {:ok, pub} = TeacherAssistant.ReportCards.publish(scope, cg, {:trimester, term})

      {:ok, view, _} =
        live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=trim:#{term.id}")

      assert render(element(view, "#bulletin-published")) =~
               Calendar.strftime(TeacherAssistant.ReportCards.published_on(pub), "%d/%m/%Y")
    end

    test "a teacher of the class reads published cards only", ctx do
      %{cg: cg, enr: enr, term: term, scope: scope, seq: seq} = ctx

      %{teacher: teacher} =
        TeacherAssistant.TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "SVT"})

      tconn =
        build_conn()
        |> log_in_user(teacher)
        |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

      {:ok, view, _} =
        live(tconn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=trim:#{term.id}")

      assert has_element?(view, "#bulletin-not-published")
      refute has_element?(view, "#bulletin-subjects")

      {:ok, view, _} =
        live(tconn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

      assert has_element?(view, "#bulletin-not-published")

      {:ok, _} = TeacherAssistant.ReportCards.publish(scope, cg, {:trimester, term})

      {:ok, view, _} =
        live(tconn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=trim:#{term.id}")

      assert has_element?(view, "#bulletin-subjects")
      assert has_element?(view, "#bulletin-published")
    end

    test "a student enrolled after publication is absent from it", ctx do
      %{conn: conn, cg: cg, term: term, scope: scope} = ctx
      {:ok, _} = TeacherAssistant.ReportCards.publish(scope, cg, {:trimester, term})
      {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Zoé Late", sex: :f})
      %{enrollment: late} = Enum.find(Enrollment.list_roster(scope, cg), &(&1.student.full_name == "Zoé Late"))

      {:ok, view, _} =
        live(conn, ~p"/school/classes/#{cg.id}/students/#{late.id}/bulletin?period=trim:#{term.id}")

      assert has_element?(view, "#bulletin-absent")
    end
  end
```

In `results_live_test.exs`, using that file's setup (head conn, a class with marks): a test that publishes the first term, opens `/school/classes/:id/results?period=trim:<id>` and asserts `#results-published`; and a plain-teacher test (same `school_teacher_fixture` + `tconn` as above) asserting `#results-not-published` on the unpublished term and the results table after publishing. Also: a plain member with no course in the class is redirected — `{:error, {:live_redirect, %{to: "/school"}}} = live(other_conn, ~p"/school/classes/#{cg.id}/results")` (use `TeacherFixtures.member_scope_fixture(scope)`'s user for `other_conn`).

In `bulletin_print_controller_test.exs`, using its setup:

```elixir
  test "a draft trimester prints with the BROUILLON watermark; a published one with its date", ctx do
    %{conn: conn, cg: cg, scope: scope} = ctx
    year = TeacherAssistant.Organization.current_academic_year(scope)
    [term | _] = TeacherAssistant.Organization.list_terms(scope, year)

    html = conn |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}") |> html_response(200)
    assert html =~ "BROUILLON"

    {:ok, pub} = TeacherAssistant.ReportCards.publish(%{scope | current_academic_year: year}, cg, {:trimester, term})
    html = conn |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}") |> html_response(200)
    refute html =~ "BROUILLON"
    assert html =~ Calendar.strftime(TeacherAssistant.ReportCards.published_on(pub), "%d/%m/%Y")
  end

  test "a séquence print has no watermark", ctx do
    %{conn: conn, cg: cg, seq: seq} = ctx
    html = conn |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}") |> html_response(200)
    refute html =~ "BROUILLON"
  end

  test "a teacher cannot print an unpublished period", ctx do
    %{cg: cg, scope: scope} = ctx
    year = TeacherAssistant.Organization.current_academic_year(scope)
    [term | _] = TeacherAssistant.Organization.list_terms(scope, year)
    %{teacher: teacher} = TeacherAssistant.TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "SVT"})

    tconn =
      build_conn()
      |> log_in_user(teacher)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    conn = get(tconn, ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}")
    assert redirected_to(conn) == ~p"/school/classes/#{cg.id}/results?period=trim:#{term.id}"
  end
```

(Adapt variable names to what the setups return — e.g. `seq`, `cg`, `scope`; add them to the setup's returned map when missing.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/live/school/results_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the report card**

In `bulletin_live.ex` (add `alias TeacherAssistant.ReportCards`):

Mount: replace `true <- Enrollment.class_manager?(scope, cg),` with `access when access != :none <- ReportCards.access(scope, cg),` (the `else false ->` branch becomes `:none ->`, still navigating to `/school`). Replace the `results/data/conduct/discipline` lines and the big `assign` with:

```elixir
      {:ok,
       socket
       |> assign(
         cg: cg,
         student: student,
         enrollment: enrollment,
         year: year,
         sequences: sequences,
         terms: terms
       )
       |> load_period(period)}
```

Replace `handle_params(%{"period" => _} = params, …)` body with:

```elixir
    year = socket.assigns.year

    period =
      (year && Organization.resolve_period(socket.assigns.current_scope, year, params["period"])) ||
        socket.assigns.period

    {:noreply, load_period(socket, period)}
```

Add:

```elixir
  # One place decides what is shown: a published snapshot, a live draft (class
  # managers only) or nothing yet (teachers before publication).
  defp load_period(socket, period) do
    %{current_scope: scope, cg: cg, student: student, enrollment: enrollment} = socket.assigns

    {status, publication, view} =
      case period && ReportCards.view_for(scope, cg, period) do
        {:published, pub, view} -> {:published, pub, view}
        {:draft, view} -> {:draft, nil, view}
        _ -> {:not_published, nil, nil}
      end

    results = view && view.results

    assign(socket,
      period: period,
      period_param: period && Organization.period_param(period),
      period_kind: period && Organization.period_kind(period),
      status: if(period, do: status, else: :draft),
      publication: publication,
      in_view?: is_nil(view) or Enum.any?(view.roster, &(&1.student.id == student.id)),
      effectif: (results && results.effectif) || 0,
      data: results && results.per_student[student.id],
      conduct: view && view.conduct[enrollment.id],
      discipline: view && view.discipline[enrollment.id],
      group_subtotals?: (view && view.group_subtotals?) || false
    )
  end
```

Delete the now-unused private `group_subtotals?/1` in this module (and the `Attendance`, `Discipline`, `Assessment` aliases if unused — `mix compile --warnings-as-errors` will tell).

Render: after `#bulletin-identity`, add:

```heex
        <p :if={@status == :published} id="bulletin-published" class="badge badge-success gap-1">
          <.icon name="hero-check-badge" class="size-4" />
          {gettext("Publié le %{date}",
            date: Calendar.strftime(ReportCards.published_on(@publication), "%d/%m/%Y")
          )}
        </p>

        <.empty_state
          :if={@status == :not_published}
          id="bulletin-not-published"
          icon="hero-lock-closed"
          title={gettext("Pas encore publiés")}
          message={gettext("Les bulletins de cette période n'ont pas encore été publiés.")}
        />

        <.empty_state
          :if={@status != :not_published and not @in_view?}
          id="bulletin-absent"
          icon="hero-user-minus"
          title={gettext("Absent des bulletins publiés")}
          message={gettext("Absent des bulletins publiés de cette période.")}
        />
```

and change the existing "Aucune donnée" empty state's condition to `:if={@status != :not_published and @in_view? and is_nil(@data)}`. Hide the print button for `:not_published`: `:if={@period && @status != :not_published}`. (If `<.empty_state>` has no `id` attr, wrap each in `<div id="…">`.)

- [ ] **Step 4: Implement class results**

In `results_live.ex` (alias `TeacherAssistant.ReportCards`): mount check `access when access != :none <- ReportCards.access(scope, cg)` (else `:none -> push_navigate(socket, to: ~p"/school")`). Replace `select_period/2`'s `results = …` and `roster = …` with:

```elixir
    {status, publication, view} =
      case period && ReportCards.view_for(socket.assigns.current_scope, socket.assigns.cg, period) do
        {:published, pub, view} -> {:published, pub, view}
        {:draft, view} -> {:draft, nil, view}
        _ -> {:not_published, nil, nil}
      end

    results = view && view.results
    roster = (view && view.roster) || []
```

and add `status: status, publication: publication` to the `assign`. `ranked_rows/2` and `names/2` work unchanged on the plain roster maps (they read `student.id`, `student.full_name`, `enrollment.id`). The `form_master` assign stays live (header only).

Render: above the stats, add `#results-published` (same badge markup as the report card) when `@status == :published`, and a `#results-not-published` empty state (same texts) when `@status == :not_published`; the existing results block keeps its own `:if` on `@results` and so disappears for `:not_published`. Hide `#print-whole-class` when `@status == :not_published`.

- [ ] **Step 5: Implement print**

In `bulletin_print_controller.ex` (alias `TeacherAssistant.ReportCards`; remove now-unused aliases):

```elixir
  def show(conn, %{"id" => id, "enrollment_id" => eid} = params) do
    with_view(conn, id, params, fn scope, cg, period, status, pub, view ->
      case Enum.find(view.roster, &(&1.enrollment.id == eid)) do
        %{} = entry -> render_bulletins(conn, scope, cg, period, status, pub, view, [entry])
        nil -> redirect(conn, to: ~p"/school/classes/#{id}/results")
      end
    end)
  end

  def class(conn, %{"id" => id} = params) do
    with_view(conn, id, params, fn scope, cg, period, status, pub, view ->
      entries = Enum.sort_by(view.roster, &String.downcase(&1.student.full_name))
      render_bulletins(conn, scope, cg, period, status, pub, view, entries)
    end)
  end

  defp with_view(conn, id, params, fun) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         {:operating, true} <- {:operating, TeacherAssistant.Scope.school_verified?(scope)},
         year when not is_nil(year) <- scope.current_academic_year,
         period when not is_nil(period) <-
           Organization.resolve_period(scope, year, params["period"]) do
      case ReportCards.view_for(scope, cg, period) do
        {:published, pub, view} -> fun.(scope, cg, period, :published, pub, view)
        {:draft, view} -> fun.(scope, cg, period, :draft, nil, view)
        :not_published ->
          conn
          |> put_flash(:error, gettext("Pas encore publiés"))
          |> redirect(to: ~p"/school/classes/#{cg.id}/results?period=#{params["period"]}")

        :forbidden ->
          redirect(conn, to: ~p"/school")
      end
    else
      {:operating, false} ->
        conn
        |> put_flash(:error, gettext("École en attente de vérification — impression indisponible."))
        |> redirect(to: ~p"/school")

      _ ->
        redirect(conn, to: ~p"/school")
    end
  end

  defp render_bulletins(conn, scope, cg, period, status, pub, view, entries) do
    results = view.results

    bundles =
      Enum.map(entries, fn %{student: student, enrollment: enrollment} ->
        %{
          student: student,
          enrollment: enrollment,
          data: results && results.per_student[student.id],
          conduct: view.conduct[enrollment.id],
          discipline: view.discipline[enrollment.id]
        }
      end)

    kind = Organization.period_kind(period)

    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show,
      etablissement: scope.current_workspace.name,
      annee: scope.current_academic_year && scope.current_academic_year.name,
      professeur_principal: view.form_master && view.form_master.email,
      cg: cg,
      period_kind: kind,
      period_heading: period_heading(period),
      effectif: (results && results.effectif) || 0,
      bundles: bundles,
      group_subtotals?: view.group_subtotals?,
      draft?: status == :draft and kind in [:trimester, :annual],
      published_on: pub && Calendar.strftime(ReportCards.published_on(pub), "%d/%m/%Y")
    )
  end
```

Delete the controller's private `group_subtotals?/1` (now in the view).

In `show.html.heex`: add to the `<style>` block

```css
      .bulletin-page { position: relative; }
      .watermark {
        position: absolute; inset: 35% 0 auto 0; text-align: center;
        font-size: 96px; font-weight: 700; letter-spacing: 0.2em;
        color: rgba(0, 0, 0, 0.08); transform: rotate(-24deg); pointer-events: none;
      }
      .published { font-size: 11px; text-align: right; margin: 0 0 4px; }
```

(if `.bulletin-page` already has rules, add `position: relative;` to them instead), and as the first children of `<section :for={b <- @bundles} class="bulletin-page">`:

```heex
      <div :if={@draft?} class="watermark">{gettext("BROUILLON")}</div>
      <p :if={@published_on} class="published">{gettext("Publié le %{date}", date: @published_on)}</p>
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test`
Expected: PASS (the whole suite — existing report card, results and print tests must still pass for séquences and drafts).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web
git commit -m "feat: report cards, results and print show published snapshots"
```

---

### Task 4: The "Bulletins" screen and menus

**Files:**
- Create: `lib/teacher_assistant_web/live/school/bulletins_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route in the `:school_workspace` live session, next to `/school/sequences`)
- Modify: `lib/teacher_assistant_web/spaces.ex` (item `bulletins()` in Proviseur "Pilotage" and Censeur "Suivi pédagogique" after `sequences()`; Enseignant after `courses()` when `facts.teaches? or facts.form_master?`)
- Test: `test/teacher_assistant_web/live/school/bulletins_live_test.exs`; update `test/teacher_assistant_web/spaces_test.exs` / `test/teacher_assistant_web/live/role_spaces_test.exs` if they list exact items

**Interfaces:**
- Consumes: `ReportCards.visible_classes/2`, `periods/2`, `view_for/3`, `can_publish?/1`, `entry_rate/3`, `publish/3`, `withdraw/3`, `history/3`, `current_publication/3`, `published_on/1`; `Distinction.label/1`, `<.mention_badge>`, `<.distinction_badge>`.
- Produces: route `/school/bulletins?class=<id>&period=<trim:id|annee>&student=<student id>`; DOM ids: `#bulletins-classes`, `#class-<id>`, `#period-<param>` (`:` replaced by `-`), `#bulletins-status`, `#bulletins-rate`, `#bulletins-table`, `#bulletins-row-<student id>`, `#print-<student id>`, `#student-panel`, `#publish`, `#publish-confirm`, `#confirm-publish`, `#print-class`, `#ask-withdraw`, `#withdraw-form`, `#bulletins-history`, `#bulletins-not-published`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/school/bulletins_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.BulletinsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, actor: head} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "4e B", level: "4ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Djoumessi Arnaud", sex: :m})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Tchinda Rodrigue", sex: :m})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    [term | _] = Organization.list_terms(scope, year)
    [seq1, seq2] = term.sequences
    roster = Enrollment.list_roster(scope, cg)

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq1, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    # Djoumessi 15, Tchinda not marked: entry incomplete; nothing in séquence 2
    [dj, tch] = roster
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: dj.student.id, score: Decimal.new(15)}])

    %{scope: scope, cg: cg, term: term, seq2: seq2, tc: tc, dj: dj, tch: tch}
  end

  defp url(cg, term), do: ~p"/school/bulletins?class=#{cg.id}&period=trim:#{term.id}"

  test "lists the class with rank, average, appreciation and distinction; first student in the panel", ctx do
    {:ok, view, _} = live(ctx.conn, url(ctx.cg, ctx.term))
    assert has_element?(view, "#bulletins-status", "Brouillon")
    assert has_element?(view, "#bulletins-row-#{ctx.dj.student.id}", "15")
    assert has_element?(view, "#bulletins-row-#{ctx.dj.student.id}", "Encouragements")
    assert has_element?(view, "#student-panel", "Djoumessi Arnaud")
    assert has_element?(view, "#student-panel", "Maths · coef 4")
    assert has_element?(view, "#print-#{ctx.dj.student.id}[href*='/bulletin/print?period=trim:']")
    assert has_element?(view, "#print-class")
  end

  test "selecting a student updates the side panel", ctx do
    {:ok, view, _} = live(ctx.conn, url(ctx.cg, ctx.term))
    view |> element("#bulletins-row-#{ctx.tch.student.id} a[data-role=select]") |> render_click()
    assert has_element?(view, "#student-panel", "Tchinda Rodrigue")
  end

  test "incomplete entry asks for confirmation, then publishes", ctx do
    {:ok, view, _} = live(ctx.conn, url(ctx.cg, ctx.term))
    assert render(element(view, "#bulletins-rate")) =~ "%"
    view |> element("#publish") |> render_click()
    assert has_element?(view, "#publish-confirm", "Saisie incomplète")
    assert ReportCards.current_publication(ctx.scope, ctx.cg, {:trimester, ctx.term}) == nil

    view |> element("#confirm-publish") |> render_click()
    assert render(view) =~ "Bulletins publiés."
    assert has_element?(view, "#bulletins-status", "Publié le")
    assert ReportCards.current_publication(ctx.scope, ctx.cg, {:trimester, ctx.term})
  end

  test "withdraw needs a reason and is kept in the history", ctx do
    {:ok, _} = ReportCards.publish(ctx.scope, ctx.cg, {:trimester, ctx.term})
    {:ok, view, _} = live(ctx.conn, url(ctx.cg, ctx.term))
    view |> element("#ask-withdraw") |> render_click()

    view |> form("#withdraw-form", %{reason: "  "}) |> render_submit()
    assert has_element?(view, "#bulletins-status", "Publié le")

    view |> form("#withdraw-form", %{reason: "Note de maths erronée"}) |> render_submit()
    assert render(view) =~ "Bulletins dépubliés."
    assert has_element?(view, "#bulletins-status", "Brouillon")
    assert has_element?(view, "#bulletins-history", "Note de maths erronée")
  end

  test "a teacher of the class sees published periods only, read-only", ctx do
    %{teacher: teacher} =
      TeacherFixtures.school_teacher_fixture(ctx.scope, %{class_group: ctx.cg, subject: "SVT"})

    tconn =
      build_conn()
      |> log_in_user(teacher)
      |> Plug.Conn.put_session(:workspace_id, ctx.scope.current_workspace.id)

    {:ok, view, _} = live(tconn, url(ctx.cg, ctx.term))
    assert has_element?(view, "#bulletins-not-published")
    refute has_element?(view, "#publish")
    refute has_element?(view, "#bulletins-rate")

    {:ok, _} = ReportCards.publish(ctx.scope, ctx.cg, {:trimester, ctx.term})
    {:ok, view, _} = live(tconn, url(ctx.cg, ctx.term))
    assert has_element?(view, "#bulletins-row-#{ctx.dj.student.id}")
    refute has_element?(view, "#ask-withdraw")
    refute has_element?(view, "#publish")
  end

  test "someone with no class to see is sent home", ctx do
    other = TeacherFixtures.member_scope_fixture(ctx.scope)

    oconn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(oconn, ~p"/school/bulletins")
  end

  test "the menu has Bulletins for the head", ctx do
    {:ok, view, _} = live(ctx.conn, url(ctx.cg, ctx.term))
    assert has_element?(view, "a[href='/school/bulletins']")
  end
end
```

(If `live/2` returns `{:error, {:redirect, …}}` rather than `:live_redirect` for the push_navigate in mount, match what the existing redirect tests in this repo use — e.g. `evaluations_live_test.exs`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant_web/live/school/bulletins_live_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Implement routes and menus**

Router (in the `:school_workspace` live session, next to `/school/sequences`):

```elixir
      live "/school/bulletins", School.BulletinsLive, :index
```

`spaces.ex`: add `bulletins()` after `sequences()` in the Proviseur "Pilotage" and Censeur "Suivi pédagogique" sections; in the Enseignant items list add `(facts.teaches? or facts.form_master?) && bulletins(),` after `facts.teaches? && courses(),`; and the helper:

```elixir
  defp bulletins,
    do: item("bulletins", gettext("Bulletins"), "hero-document-text", ~p"/school/bulletins")
```

- [ ] **Step 4: Implement BulletinsLive**

`lib/teacher_assistant_web/live/school/bulletins_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.BulletinsLive do
  @moduledoc """
  Bulletins (spec I2, mockup Censeur → "Bulletins"): one class and one period
  (a trimester or the year) at a time — the ranked list, a side panel with the
  selected student's report card in short, print buttons, and for the Proviseur and
  Censeur the mark-entry rate, publishing (with a confirmation below 100 %),
  withdrawal with a reason and the history. Teachers of the class see published
  periods only, read-only.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.ReportCards
  alias TeacherAssistant.Academics.PublicationStatus

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} = year <- scope.current_academic_year,
         [_ | _] = classes <- ReportCards.visible_classes(scope, year) do
      {:ok,
       assign(socket,
         year: year,
         classes: classes,
         periods: ReportCards.periods(scope, year),
         can_publish?: ReportCards.can_publish?(scope),
         confirm?: false,
         withdrawing?: false
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    %{classes: classes, periods: periods} = socket.assigns
    cg = Enum.find(classes, &(&1.id == params["class"])) || hd(classes)

    {param, _label, period} =
      Enum.find(periods, &(elem(&1, 0) == params["period"])) || default_period(periods)

    {:noreply,
     socket
     |> assign(cg: cg, period: period, period_param: param, confirm?: false, withdrawing?: false)
     |> load(params["student"])}
  end

  # The trimester whose séquences cover today, else the first one.
  defp default_period(periods) do
    today = TeacherAssistant.Academics.Reference.today()

    Enum.find(periods, fn
      {_, _, {:trimester, term}} ->
        Enum.any?(term.sequences, fn s ->
          Date.compare(s.start_date, today) != :gt and Date.compare(today, s.end_date) != :gt
        end)

      _ ->
        false
    end) || hd(periods)
  end

  defp load(socket, student_id) do
    %{current_scope: scope, cg: cg, period: period, can_publish?: can_publish?} = socket.assigns

    {status, publication, view} =
      case ReportCards.view_for(scope, cg, period) do
        {:published, pub, view} -> {:published, pub, view}
        {:draft, view} -> {:draft, nil, view}
        _ -> {:not_published, nil, nil}
      end

    rows = rows(view)

    assign(socket,
      status: status,
      publication: publication,
      view: view,
      rows: rows,
      selected: Enum.find(rows, &(&1.student.id == student_id)) || List.first(rows),
      rate: if(can_publish?, do: ReportCards.entry_rate(scope, cg, period)),
      history: if(can_publish?, do: ReportCards.history(scope, cg, period), else: [])
    )
  end

  defp rows(nil), do: []
  defp rows(%{results: nil}), do: []

  defp rows(%{results: results, roster: roster}) do
    roster
    |> Enum.flat_map(fn %{student: s, enrollment: e} ->
      case results.per_student[s.id] do
        nil -> []
        data -> [%{student: s, enrollment: e, data: data}]
      end
    end)
    |> Enum.sort_by(&{&1.data.rank || 9_999, String.downcase(&1.student.full_name)})
  end

  def handle_event("publish", _params, %{assigns: %{rate: 100}} = socket), do: publish(socket)
  def handle_event("publish", _params, socket), do: {:noreply, assign(socket, confirm?: true)}
  def handle_event("confirm_publish", _params, socket), do: publish(socket)
  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, confirm?: false, withdrawing?: false)}

  def handle_event("ask_withdraw", _params, socket),
    do: {:noreply, assign(socket, withdrawing?: true)}

  def handle_event("withdraw", %{"reason" => reason}, socket) do
    case ReportCards.withdraw(socket.assigns.current_scope, socket.assigns.publication, reason) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(withdrawing?: false)
         |> load(selected_id(socket))
         |> put_flash(:info, gettext("Bulletins dépubliés."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Le motif est obligatoire."))}
    end
  end

  defp publish(socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    case ReportCards.publish(scope, cg, period) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(confirm?: false)
         |> load(selected_id(socket))
         |> put_flash(:info, gettext("Bulletins publiés."))}

      {:error, :already_published} ->
        {:noreply,
         socket
         |> assign(confirm?: false)
         |> load(selected_id(socket))
         |> put_flash(:error, gettext("Bulletins déjà publiés."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Publication impossible."))}
    end
  end

  defp selected_id(socket), do: socket.assigns.selected && socket.assigns.selected.student.id

  defp patch_to(assigns, overrides) do
    query =
      %{class: assigns.cg.id, period: assigns.period_param}
      |> Map.merge(overrides)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    ~p"/school/bulletins?#{query}"
  end

  defp print_one(assigns, row),
    do:
      ~p"/school/classes/#{assigns.cg.id}/students/#{row.enrollment.id}/bulletin/print?period=#{assigns.period_param}"

  defp dom_id(param), do: String.replace(param, ":", "-")
  defp date(pub), do: Calendar.strftime(ReportCards.published_on(pub), "%d/%m/%Y")
  defp date_of(%DateTime{} = at), do: at |> DateTime.add(3600) |> Calendar.strftime("%d/%m/%Y")
  defp who(nil), do: "—"
  defp who(user), do: user.name || to_string(user.email)

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp hours(nil), do: "—"
  defp hours(c), do: c.justified_hours |> Decimal.add(c.unjustified_hours) |> fmt()

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="bulletins" class="space-y-4">
        <.page_header
          eyebrow={if @can_publish?, do: gettext("Censorat · bulletins"), else: gettext("Bulletins · lecture seule")}
          title={gettext("Bulletins · %{class}", class: @cg.label)}
        />

        <div id="bulletins-classes" class="flex flex-wrap gap-2">
          <.link
            :for={cg <- @classes}
            id={"class-#{cg.id}"}
            patch={patch_to(assigns, %{class: cg.id})}
            class={["btn btn-sm rounded-full", if(cg.id == @cg.id, do: "btn-primary", else: "btn-ghost border-base-300")]}
          >
            {cg.label}
          </.link>
        </div>

        <div role="tablist" class="tabs tabs-box w-fit">
          <.link
            :for={{param, label, _} <- @periods}
            id={"period-#{dom_id(param)}"}
            role="tab"
            patch={patch_to(assigns, %{period: param})}
            class={["tab", param == @period_param && "tab-active"]}
          >
            {label}
          </.link>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <span id="bulletins-status" class={["badge", if(@status == :published, do: "badge-success", else: "badge-warning")]}>
            {if @status == :published,
              do: gettext("Publié le %{date} par %{who}", date: date(@publication), who: who(@publication.published_by)),
              else: gettext("Brouillon")}
          </span>
          <span :if={@can_publish?} id="bulletins-rate" class="ta-num text-sm text-base-content/70">
            {gettext("Saisie des notes : %{rate}", rate: if(@rate, do: "#{@rate} %", else: "—"))}
          </span>
        </div>

        <.empty_state
          :if={@status == :not_published}
          id="bulletins-not-published"
          icon="hero-lock-closed"
          title={gettext("Pas encore publiés")}
          message={gettext("Les bulletins de cette période n'ont pas encore été publiés.")}
        />

        <div :if={@status != :not_published} class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="bulletins-table" class="table">
              <thead>
                <tr>
                  <th>{gettext("Rang")}</th>
                  <th>{gettext("Élève")}</th>
                  <th class="text-right">{gettext("Moy. gén.")}</th>
                  <th>{gettext("Appréciation")}</th>
                  <th>{gettext("Distinction")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @rows}
                  id={"bulletins-row-#{row.student.id}"}
                  class={[@selected && @selected.student.id == row.student.id && "bg-primary/10"]}
                >
                  <td class="ta-num">{row.data.rank || "—"}</td>
                  <td>
                    <.link data-role="select" patch={patch_to(assigns, %{student: row.student.id})} class="link link-hover">
                      {row.student.full_name}
                    </.link>
                  </td>
                  <td class="ta-num text-right font-semibold">{fmt(row.data.moyenne_generale)}</td>
                  <td><.mention_badge :if={row.data.mention} mention={row.data.mention} /></td>
                  <td><.distinction_badge distinction={row.data.distinction} /></td>
                  <td>
                    <a
                      id={"print-#{row.student.id}"}
                      href={print_one(assigns, row)}
                      target="_blank"
                      class="btn btn-ghost btn-xs"
                      aria-label={gettext("Imprimer")}
                    >
                      <.icon name="hero-printer" class="size-4" />
                    </a>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <aside
            :if={@selected}
            id="student-panel"
            class="rounded-box border border-primary/40 bg-base-100 p-4 space-y-3 self-start"
          >
            <p class="ta-eyebrow">{gettext("Bulletin")} · {Enum.find_value(@periods, fn {p, l, _} -> p == @period_param && l end)} · {@cg.label}</p>
            <h2 class="text-lg font-semibold">{@selected.student.full_name}</h2>
            <dl class="divide-y divide-base-300 text-sm">
              <div :for={s <- @selected.data.subjects} class="flex justify-between py-1">
                <dt>{s.label} · {gettext("coef")} {fmt(s.coefficient)}</dt>
                <dd class="ta-num">{fmt(s.average)}</dd>
              </div>
              <div class="flex justify-between py-1 font-semibold">
                <dt>{gettext("Moyenne générale")}</dt>
                <dd class="ta-num">{fmt(@selected.data.moyenne_generale)}</dd>
              </div>
              <div class="flex justify-between py-1">
                <dt>{gettext("Rang")}</dt>
                <dd class="ta-num">{@selected.data.rank || "—"} / {@view.results.effectif}</dd>
              </div>
              <div class="flex justify-between py-1">
                <dt>{gettext("Absences")}</dt>
                <dd class="ta-num">{hours(@view.conduct[@selected.enrollment.id])} {gettext("h")}</dd>
              </div>
            </dl>
            <div class="flex flex-wrap gap-2">
              <.mention_badge :if={@selected.data.mention} mention={@selected.data.mention} />
              <.distinction_badge distinction={@selected.data.distinction} />
            </div>
            <div class="flex flex-wrap gap-2">
              <.link
                navigate={~p"/school/classes/#{@cg.id}/students/#{@selected.enrollment.id}/bulletin?period=#{@period_param}"}
                class="btn btn-ghost btn-sm"
              >
                {gettext("Ouvrir le bulletin")}
              </.link>
              <a href={print_one(assigns, @selected)} target="_blank" class="btn btn-ghost btn-sm gap-1">
                <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer")}
              </a>
            </div>
          </aside>
        </div>

        <div :if={@status != :not_published} class="flex flex-wrap items-center gap-2">
          <a
            id="print-class"
            href={~p"/school/classes/#{@cg.id}/bulletin/print?period=#{@period_param}"}
            target="_blank"
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer toute la classe")}
          </a>
          <button
            :if={@can_publish? and @status == :draft}
            id="publish"
            type="button"
            phx-click="publish"
            class="btn btn-primary btn-sm"
          >
            {gettext("Publier les bulletins de la classe")}
          </button>
          <button
            :if={@can_publish? and @status == :published and not @withdrawing?}
            id="ask-withdraw"
            type="button"
            phx-click="ask_withdraw"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Dépublier")}
          </button>
        </div>

        <div :if={@confirm?} id="publish-confirm" class="alert alert-warning">
          <span>
            {gettext("Saisie incomplète : %{rate}. Publier quand même ?", rate: if(@rate, do: "#{@rate} %", else: "—"))}
          </span>
          <div class="flex gap-2">
            <button id="confirm-publish" type="button" phx-click="confirm_publish" class="btn btn-sm btn-warning">
              {gettext("Publier quand même")}
            </button>
            <button type="button" phx-click="cancel" class="btn btn-sm btn-ghost">{gettext("Annuler")}</button>
          </div>
        </div>

        <.form :if={@withdrawing?} for={%{}} id="withdraw-form" phx-submit="withdraw" class="flex flex-wrap items-end gap-2">
          <.input name="reason" value="" label={gettext("Motif du retrait")} class="input input-sm w-80" required />
          <button type="submit" class="btn btn-sm btn-error">{gettext("Dépublier")}</button>
          <button type="button" phx-click="cancel" class="btn btn-sm btn-ghost">{gettext("Annuler")}</button>
        </.form>

        <ul :if={@history != []} id="bulletins-history" class="space-y-1 text-sm text-base-content/70">
          <li :for={pub <- @history}>
            {gettext("Publié le %{date} par %{who}", date: date(pub), who: who(pub.published_by))}
            <span :if={pub.status == :withdrawn}>
              · {gettext("Retiré le %{date} par %{who} : %{reason}",
                date: date_of(pub.withdrawn_at),
                who: who(pub.withdrawn_by),
                reason: pub.withdrawal_reason
              )}
            </span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
```

Notes for the implementer:
- `PublicationStatus` alias is only needed if you render `PublicationStatus.label/1`; remove the alias if unused (warnings fail the build).
- The `required` attribute on the reason input stops empty submits in the browser; the server still refuses a reason of spaces (the test submits `"  "`, which LiveViewTest sends regardless).
- `.empty_state` with an `id`: if the component has no `id` attr, wrap it in `<div id="bulletins-not-published">`.
- `@view.results` is nil when the class has no subjects: then `@rows` is `[]` and `@selected` nil, so the panel and rank line never render.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/teacher_assistant_web/live/school/bulletins_live_test.exs test/teacher_assistant_web/spaces_test.exs test/teacher_assistant_web/live/role_spaces_test.exs`
Expected: PASS. If a spaces test lists exact items, add `"bulletins"` where it now appears.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web
git commit -m "feat: Bulletins screen to publish, withdraw, preview and print report cards"
```

---

### Task 5: Translations, checks and roadmap status

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/fr/LC_MESSAGES/default.po`
- Modify: `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` (I2 status line)

- [ ] **Step 1: Extract and translate**

Run: `mix gettext.extract --merge`
Fill every new empty `msgstr` in `priv/gettext/en/LC_MESSAGES/default.po`, e.g.: Publié → "Published", Retiré → "Withdrawn", Brouillon → "Draft", BROUILLON → "DRAFT", Publié le %{date} → "Published on %{date}", Publié le %{date} par %{who} → "Published on %{date} by %{who}", Retiré le %{date} par %{who} : %{reason} → "Withdrawn on %{date} by %{who}: %{reason}", Pas encore publiés → "Not published yet", Les bulletins de cette période n'ont pas encore été publiés. → "Report cards for this period have not been published yet.", Absent des bulletins publiés → "Not in the published report cards", Publier les bulletins de la classe → "Publish the class's report cards", Dépublier → "Unpublish", Saisie incomplète : %{rate}. Publier quand même ? → "Mark entry incomplete: %{rate}. Publish anyway?", Bulletins publiés. → "Report cards published.", Bulletins dépubliés. → "Report cards unpublished.", Bulletins déjà publiés. → "Report cards already published.", Motif du retrait → "Reason for withdrawal", Le motif est obligatoire. → "A reason is required.", Imprimer toute la classe (existing), Ouvrir le bulletin → "Open the report card", Trimestre %{n} → "Term %{n}", Année → "Year", Bulletins · lecture seule → "Report cards · read-only", Censorat · bulletins → "Vice-principal's office · report cards", Saisie des notes : %{rate} → "Mark entry: %{rate}", Publication impossible. → "Could not publish.". Keep existing msgstrs.

Run: `grep -c 'msgstr ""$' priv/gettext/en/LC_MESSAGES/default.po` before and after filling; the new strings must not add to the count.

- [ ] **Step 2: Full checks**

Run: `mix precommit`
Then: `mix compile --warnings-as-errors`
Then: `mix test`
Expected: all green, no warnings. Include files rewritten by the formatter in the commit.

- [ ] **Step 3: Roadmap status**

In `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`, I2 section, change `Status: spec approved 2026-10-01, not implemented.` to `Status: implemented <date> (branch \`i2-publish-report-cards\`, plan \`docs/superpowers/plans/2026-10-01-i2-publish-report-cards.md\`); no visual check done.`

- [ ] **Step 4: Commit**

```bash
git add -A priv/gettext docs lib test
git commit -m "chore: I2 translations and status"
```
