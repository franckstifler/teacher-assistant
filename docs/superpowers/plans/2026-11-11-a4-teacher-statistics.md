# A4 — Teacher statistics (séquence, trimester, year, printable) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A teacher reads and prints, for any séquence, trimester or the year, the figures their pedagogical forms ask for — effectif, garçons/filles, notés, moyenne, taux de réussite (overall and by sex), extrêmes, mentions — per course and across all their courses, with trimester and year figures identical to the bulletin.

**Architecture:** A new `TeacherAssistant.Academics.TeacherStatistics` context computes one course's statistics for a period (séquence: the existing marks path; trimester/year: the per-subject averages of the class's compiled bulletin, taken from the published snapshot when one exists, computed live otherwise) and the table of all a teacher's courses. `Marks.from_averages/3` is extracted from `Marks.summarize/4` so séquence and period figures share one statistics routine. The Résultats page gains period chips, a new `Teacher.StatisticsLive` page lists every course, and a `StatisticsPrintController` prints it on A4 with the official header, following `MarkSheetPrintController`.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView 1.2, Ash 3.37 (reads only; no new resource, no migration), Gettext FR source + EN, print CSS as in `mark_sheet_print_html`.

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A4.

## Global Constraints

- A trimester or year figure on the statistics page equals the subject average printed on that class's bulletin for the same student: same `GradingRules`, same `Assessment.class_results_for_period/3`, and the published snapshot wins when one exists (`ReportCards.current_publication(scope, cg, period, snapshot: true)`).
- A teacher sees their own courses only; the Proviseur and Censeur (`ReportCards.can_publish?/1`) may open any teacher's page and print with `?teacher=<user id>`.
- Exempted students are excluded as on Résultats today (`Curriculum.exempt_student_ids/2`).
- No CSV, no median / standard deviation, no coverage rate, no HOD table (spec §A4 point 4).
- Every new string through Gettext (FR + EN), no fuzzy left; `mix gettext.extract --merge` then fill EN.
- Tests on `MIX_TEST_PARTITION=a4`; branch `feat/audit-a4` in `.claude/worktrees/audit-a4`; explicit paths in commits; `mix precommit` green before merge.

## Review Focus

1. A combined course (two classes, two contexts): the course row's figures cover the union, each class sub-row its own class — Task 1 tests a combined course's trimester row and sub-rows.
2. A period with no mark at all in a course (séquence not started, or no assessment): figures read « — » and the course still appears — Task 2/3 test an empty course row.
3. A student with marks who was exempted later: excluded from headcount and figures on every period — Task 1 tests exemption on a trimester.
4. A trimester where one séquence is published and later marks changed: the page shows the snapshot's figure, labelled published, not the live one — Task 1 tests a mark changed after publication.
5. A teacher pasting another teacher's `?teacher=` id: refused (empty page with « accès refusé » flash, no data) — Task 3 tests it, and Task 4 for the print (302 to `/school`).

---

### Task 1: `TeacherStatistics` context and `Marks.from_averages/3`

**Files:**
- Modify: `lib/teacher_assistant/academics/marks.ex:22-60` (extract `from_averages/3`; `summarize/4` calls it)
- Create: `lib/teacher_assistant/academics/teacher_statistics.ex`
- Modify: `lib/teacher_assistant/assessment.ex` (public `teacher_statistics/3`, `course_statistics/3` delegates, next to `sequence_entry_grid`)
- Test: `test/teacher_assistant/academics/teacher_statistics_test.exs` (new), `test/teacher_assistant/academics/marks_test.exs` (if it exists; else in the new file)

**Interfaces:**
- `Marks.from_averages(students, averages, rules)` — `students` as `summarize/4` takes them (`%{id, sex, name}`), `averages :: %{student_id => Decimal | nil}` already rounded by the school's rule; returns exactly `summarize/4`'s map (`per_student` with `average`/`mention`/`rank`, `class_average`, `pass_rate`, `highest`, `lowest`, `graded_count`, `by_sex`). `summarize/4` = per-student `subject_average` → `round_average` → `from_averages`.
- `TeacherStatistics.course(scope, %TeachingContext{} = ctx, period) :: %{summary: map | nil, students: [%{id, sex, full_name, class_label}], source: :live | :published | :mixed, members: [%{class_group, ctx, students, summary, source}]}` — `ctx` may be a member of a combined course (every member class is covered, as `MarksSummaryLive.members/3` does today). `summary` nil when the period has no assessment/mark for the course. `period` is `{:sequence, seq} | {:trimester, term} | {:annual, year}`.
  - séquence: assessments + marks of each member context (`Assessment.list_assessments/3`, `list_marks_for_context_sequence/3`) → `Marks.summarize/4` over the union (today's Résultats computation, moved here).
  - trimester / year: per member class, `results = published snapshot's results || Assessment.class_results_for_period(scope, cg, period)`; the per-student average of this context is `results.per_student[sid].subjects |> Enum.find(&(&1.context_id == member_ctx.id)) |> average`; union → `Marks.from_averages/3`; `source` `:published` when every member class is published, `:live` when none, `:mixed` otherwise.
- `TeacherStatistics.table(scope, %User{} = teacher, period) :: [row]` with `row = %{course: TeacherCourses row, class_label: String | nil, headcount, boys, girls, graded, average, pass_rate, pass_m, pass_f, lowest, highest, mentions: [{label, count}], source}` — one row per course (`TeacherCourses.list/2` restricted to `teacher`: add an optional `user:` to `TeacherCourses.list/3` or filter `Curriculum.list_units_for_scope` by the teacher; builder's call), followed by one sub-row per member class when the course is combined (`class_label` set). Mentions from `per_student` as `mentions_line/1` counts them, best first.
- `Assessment.course_statistics/3` and `Assessment.teacher_statistics/3` delegate to the module (the web layer calls contexts, never `Academics.*` directly — keep that rule).

- [ ] **Step 1: Write the failing tests**

```elixir
# teacher_statistics_test.exs — fixture: school, year with calendar (terms/sequences), cg "6e A" with 3 students (2 f, 1 m),
# head teaches Maths (tc) and another teacher teaches Anglais; S1 and S2 of trimester 1 each get one assessment with marks
test "a séquence course summary equals the Résultats computation", ctx
  # Assessment.course_statistics(scope, tc, {:sequence, s1}).summary == Marks.summarize(students, assessments, marks, rules)

test "a trimester figure equals the bulletin's subject average for every student", ctx
  # results = Assessment.class_results_for_period(scope, cg, {:trimester, term})
  # for each student: course.summary.per_student[sid].average == the Maths row's average in results.per_student[sid].subjects
  # and course.source == :live

test "a published trimester is read from the snapshot even after a later mark change", ctx
  # publish_trimester(scope, cg, term); then upsert a new mark for student 1 in S2
  # course.summary.per_student[s1].average == snapshot figure (unchanged); course.source == :published

test "an exempted student is out of the headcount and the figures", ctx
  # make Maths optional (Curriculum.update_coefficient_grid), set_exemptions(scope, tc, [s3]); headcount 2 on séquence and trimester

test "a combined course: one union row and one sub-row per class", ctx
  # second class cg_b with 2 students, head teaches Maths there too, combine_course; table(scope, head_user, {:trimester, term})
  # → [%{class_label: nil, headcount: 5}, %{class_label: "6e A", headcount: 3}, %{class_label: "6e B", headcount: 2}]

test "from_averages ranks, mentions and sex-splits like summarize", _
  # 3 students, averages 15/9/nil → rank 1,2,nil; pass_rate 0.5; by_sex.f.graded_count …
```

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=a4 mix test test/teacher_assistant/academics/teacher_statistics_test.exs`
Expected: FAIL — `Assessment.course_statistics/3` undefined, `Marks.from_averages/3` undefined.

- [ ] **Step 3: Implement** `Marks.from_averages/3` (move the ranking/aggregate half of `summarize/4` into it), the module and the two delegates. For the published read use `ReportCards.current_publication(scope, cg, period, snapshot: true)`; `Assessment` must not call `ReportCards` if that creates a cycle (`ReportCards` already calls `Assessment`): put the published lookup in `TeacherStatistics` and have **`ReportCards`** expose `course_statistics/3` and `teacher_statistics/3` instead of `Assessment` if the compiler complains. Record the choice in the ledger.

- [ ] **Step 4: Run the tests** — PASS, plus `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs` and `test/teacher_assistant/report_cards_test.exs` still green (`from_averages` extraction must not change `summarize/4`).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/marks.ex lib/teacher_assistant/academics/teacher_statistics.ex lib/teacher_assistant/assessment.ex test/teacher_assistant/academics/teacher_statistics_test.exs
git commit -m "feat(statistics): a course's figures for a séquence, a trimester or the year"
```

---

### Task 2: Period chips on Résultats

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex` (params, `assign_summary/1`, chips, header)
- Test: `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`

**Interfaces:**
- URL: `?seq=<id>` as today, or `?period=trim:<term id>` / `?period=annee` (`Organization.resolve_period/3`); `?seq` wins when both are present; no param → current séquence as today.
- Assigns: `period` (`{:sequence, seq} | {:trimester, term} | {:annual, year}`), `summary` from `Assessment.course_statistics/3`, `source`.
- Chips: after the séquence chips, in the same `#summary-seq-chips` nav: `#summary-period-trim-<id>` « Trim. n » for each term and `#summary-period-annee` « Année ». Header eyebrow: « Résultats · Trimestre 1 » / « Résultats · Année »; under it, when `source != :published` on a trimester/year, a `#summary-provisional` line « Chiffres provisoires (bulletin non publié) », and « Chiffres du bulletin publié » when published.
- The « Toutes mes statistiques » link `#summary-all` to `/school/statistics/me?period=<param>` at the bottom of the page.

- [ ] **Step 1: Write the failing tests**

```elixir
test "trimester and year chips show the period's figures and their status", ctx
  # click #summary-period-trim-<term>: #summary-class-average shows the bulletin's class average for Maths
  # (compute via Assessment.course_statistics), #summary-provisional reads "provisoires"; publish_trimester → reads "publié"
test "the year chip computes on the started séquences only", ctx  # summary not nil, header « Année »
test "the way to the full table carries the period", ctx  # #summary-all href =~ "period=trim:"
```

- [ ] **Step 2: Run** — FAIL (no chips).
- [ ] **Step 3: Implement**; the séquence path keeps using `course_statistics/3` too (one code path).
- [ ] **Step 4: Run** the file — PASS.
- [ ] **Step 5: Commit** `feat(results): trimester and year figures on a course's Résultats`.

---

### Task 3: « Mes statistiques » page

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/statistics_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`live "/school/statistics/me", Teacher.StatisticsLive, :index` in the `:school_workspace` session, next to `/school/courses`)
- Modify: `lib/teacher_assistant_web/spaces.ex` (item `statistics` « Mes statistiques », `hero-chart-bar`, under Enseignement when `facts.teaches?`, after `courses()`; tab bar unchanged)
- Test: `test/teacher_assistant_web/live/teacher/statistics_live_test.exs`, `test/teacher_assistant_web/spaces_test.exs`

**Interfaces:**
- Params: `period` (default: current séquence, `TeacherCourses.current_sequence/1`), `teacher` (user id; honoured only when `ReportCards.can_publish?(scope)`, otherwise ignored with `Authz.put_not_allowed/1` and the page shows the signed-in teacher's own data — if they have none, the empty state).
- Mount: `rows = Assessment.teacher_statistics(scope, teacher, period)`; `periods` as the bulletins page builds them (séquences, trimesters, year); `teacher_name` from the member list when `?teacher=` is used.
- Render (`Layouts.app`, phone first): `<.page_header>` « Mes statistiques » (« Statistiques · <name> » for an admin), period pills `#stats-periods` (`patch`), a `#stats-source` line (published / provisoires / mixed), the table `#stats-table`: columns Cours · Effectif · G · F · Notés · Moyenne · Réussite · Réussite G · Réussite F · Min · Max; mentions folded in a `<details>` per row on phones (`#stats-mentions-<row id>`), shown as a last column from `sm`; sub-rows of a combined course indented with their class label. « Imprimer » `#stats-print` → `/school/statistics/me/print?period=…&teacher=…`. Empty state when `rows == []`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "lists every course of the teacher for the current séquence", ctx   # two courses → two rows, figures match course_statistics
test "the period selector patches to a trimester and shows its status line", ctx
test "a combined course is one row plus a sub-row per class", ctx
test "a plain teacher cannot read another teacher's statistics", ctx   # ?teacher=<other> → flash "Accès refusé" / own rows only
test "the head opens a teacher's page by id and sees their name", ctx
test "the menu lists Mes statistiques for a teacher, not for the bursar", ctx  # spaces_test
```

- [ ] **Step 2: Run** — FAIL (route missing).
- [ ] **Step 3: Implement** page, route, menu item; Gettext extract + EN.
- [ ] **Step 4: Run** the two files + `test/teacher_assistant_web/gettext_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(statistics): « Mes statistiques », every course of a teacher for a period`.

---

### Task 4: The print

**Files:**
- Create: `lib/teacher_assistant_web/controllers/statistics_print_controller.ex`, `statistics_print_html.ex`, `statistics_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (`get "/school/statistics/me/print", StatisticsPrintController, :show` beside the mark-sheet prints)
- Test: `test/teacher_assistant_web/controllers/statistics_print_controller_test.exs`

**Interfaces:**
- `GET /school/statistics/me/print?period=<param>&teacher=<id>`; `plug TeacherAssistantWeb.Plug.SchoolAccess`; same authorization as Task 3 (another teacher's id without `can_publish?` → `redirect(to: ~p"/school")`); no period → current séquence.
- Page: `PrintComponents.setup paper={:a4_portrait}` (check the atom in `print_components.ex:26`; landscape if the table does not fit 11 columns at 8.5pt — builder's call, state it in the ledger), `official_header` with the school's resolved template header (`ReportCards.template(scope, cg).header` of the teacher's first class, `logo?: true`), title « Statistiques — <teacher name> — <period label> », the same columns as Task 3 plus a Mentions column, sub-rows for combined courses, a footer « Imprimé le <date> · <source line> » and a signature line « L'enseignant(e) ». One table; rows `break-inside: avoid`. The `.print-actions` bar with the period `<select>` as the relevé has.

- [ ] **Step 1: Write the failing tests**

```elixir
test "prints every course row with the period's figures", ctx   # 200, html =~ course title, =~ formatted class average
test "an admin prints a teacher's page by id; a teacher cannot print another's", ctx  # 200 / 302 to /school
test "without a period, the current séquence is printed", ctx
```

- [ ] **Step 2: Run** — FAIL (no route).
- [ ] **Step 3: Implement**; Gettext extract + EN.
- [ ] **Step 4: Run** the file + gettext test — PASS.
- [ ] **Step 5: Commit** `feat(print): the teacher's statistics on A4`.

---

### Task 5: Verify and merge

- [ ] Browser check on the demo school (worktree server on 4010, as A2/A3): as prof@demo.test open a course's Résultats, tap « Trim. 1 » and « Année », then « Mes statistiques », switch periods, open the print; as proviseur open `/school/statistics/me?teacher=<prof id>` and its print. Phone width for the LiveViews, desktop for the print. Screenshots of the table and the print.
- [ ] `MIX_TEST_PARTITION=a4 mix precommit` → exit 0 (refresh Gettext references if the check fails on line numbers); fast-forward merge into main; update memory `project-audit-2026-11-10`.
