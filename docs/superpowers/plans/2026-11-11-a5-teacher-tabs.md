# A5 — Teacher tabs: Bulletins folded into Mes cours, « Ma classe » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A teacher's phone bar reads Ma journée · Mes cours · EDT · Plus (Ma journée · Mes cours · Ma classe · EDT · Plus for a professeur principal); Mes cours carries the bulletin timeline that the removed Bulletins teacher page used to show; a course row links to its statistics.

**Architecture:** `Spaces` gets a `my_class` item built from the form-master classes already read in `facts/1`, an enseignant tab spec without top-up, and no `bulletins` item in the enseignant menu. The timeline helpers private to `BulletinsLive` (`steps/3`, `step_dot/1`, `seq_state/2`) move to a shared component module used by `CoursesLive`. `BulletinsLive`'s teacher mode is deleted: a teacher without `?class=` is sent to Mes cours; the class view with `?class=` stays as it is for form masters and teachers of a published class.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView 1.2, Gettext FR source + EN, daisyUI. No Ash resource change, no migration.

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A5.

## Global Constraints

- **Depends on A4 merged** (`/school/statistics/me` and the `statistics` menu item).
- The Proviseur, Censeur, Surveillant and Intendant bars and menus are unchanged (`spaces_test` "each role space gets its four primary tabs" keeps its other assertions).
- « Ma classe » exists only when the member is form master of at least one class of the current year; one class → `/school/classes/<id>`, several → `/school/classes?f=mine`. The `classes` item leaves the enseignant menu when `my_class` is there (one page, one tab).
- The Bulletins entry leaves the enseignant menu entirely (builder's call on the spec's open question: no DB read in `facts/1` for a « has a published class » rule; a published class is reached from the class page's « Bulletins » action, from the publication notification, and by URL). The route and the class view stay.
- Every new string through Gettext (FR source, EN filled, no fuzzy). Update the marketing tabs in `page_html.ex:275` to « Ma journée », « Mes cours », « EDT ».
- Branch `feat/audit-a5` in `.claude/worktrees/audit-a5`, `MIX_TEST_PARTITION=a5`; explicit paths in commits; `mix precommit` green before merge.

## Review Focus

1. A head who also teaches: proviseur bar in the proviseur space, the new enseignant bar after switching (`Spaces.keys_for/1` yields both) — Task 1 tests it.
2. A form master who teaches nothing: bar Ma classe · EDT · Plus (no top-up), menu with Ma classe and EDT only — Task 1 tests it.
3. A teacher whose school has the `notes` module off: Mes cours shows no timeline and no Stats link, nothing crashes — Task 2 tests it.
4. A teacher opening `/school/bulletins?class=<unknown id>`: today `class_params` falls back to the first visible class; keep that for admins, but a teacher with no visible class is still sent home — Task 3 tests the unknown id for a teacher (lands on a class they may see, or Mes cours when none).
5. The old `#back-to-teacher` link from the class view: must not patch into a removed view — Task 3 replaces it and tests the new target.

---

### Task 1: Tab bar, « Ma classe », no Bulletins for teachers

**Files:**
- Modify: `lib/teacher_assistant_web/spaces.ex` (`facts/1` :108, `space(:enseignant, …)` :255-278, `tab_bar/1` :296-316, `tab_spec/1` :358-365, `tab_label/1` :369, `path_under_item?/2` :335, new `my_class/1` next to `classes/0` :464)
- Modify: `lib/teacher_assistant_web/live/school/classes_live.ex` (`@filters` :17, `matches_filter?/2` :709, `filter_counts/1` :713, `filter_label/1` :716, pills :139-149)
- Modify: `lib/teacher_assistant_web/controllers/page_html.ex:275`
- Test: `test/teacher_assistant_web/spaces_test.exs`, `test/teacher_assistant_web/live/role_spaces_test.exs:82`, `test/teacher_assistant_web/live/school/classes_live_test.exs`

**Interfaces:**
- `Spaces.facts/1` adds `form_master_classes: [%{id, label}]` from the `Enrollment.list_form_master_classes/2` read already made at line 115 (`form_master?` stays, derived from it). The test helper `facts/2` in `spaces_test.exs:5-12` gains `form_master_classes: []` by default and takes `form_master_classes:` as an option.
- `my_class(classes)` → `item("my-class", gettext("Ma classe"), "hero-user-group", path)` with `path = ~p"/school/classes/#{id}"` for one class, `~p"/school/classes?f=mine"` for several.
- `space(:enseignant, facts)` items: `my_day` (teaches?), `courses()` (teaches?), `statistics` (teaches?, from A4), `my_class(facts.form_master_classes)` (form_master?), `timetable()`. No `classes()`, no `bulletins()`.
- `tab_spec(:enseignant)` → `["today", "courses", "my-class", "timetable-me"]`; `tab_bar/1` does not top up the enseignant bar (a missing chosen item leaves a shorter bar; the other spaces keep the top-up). `tab_label("my-class")` → « Ma classe ».
- `path_under_item?/2`: an item whose id is `nav-school-my-class` lights for any path starting with `/school/classes` (the query is not in `current_path`).
- `ClassesLive`: filter `:mine` (`row.cg.form_master_user_id == current_user.id`), label « Mes classes », pill shown only when its count is > 0; `?f=mine` accepted.
- `page_html.ex:275`: `tabs: [gettext("Ma journée"), gettext("Mes cours"), gettext("EDT")]`.

- [ ] **Step 1: Write the failing tests**

```elixir
# spaces_test.exs
test "a plain teacher's bar is Ma journée · Mes cours · EDT, nothing topped up"       # tab_labels(:enseignant, facts([:teacher], teaches?: true)) == ["Ma journée", "Mes cours", "EDT"]
test "a form master gets Ma classe as third tab, opening the class"                   # one class → path "/school/classes/<id>"; two classes → "/school/classes?f=mine"
test "a form master who does not teach: Ma classe · EDT"
test "the enseignant menu has no Bulletins and no Classes entry"                      # update the item_ids assertions at 192-211
test "a head who teaches keeps the proviseur bar and gets the enseignant bar"         # keys_for → [:proviseur, :enseignant]; tab_labels per key
# "no two tabs open the same page" and "missing chosen items are topped up from the menu" updated for the enseignant exception
# role_spaces_test.exs:82 → assert #tab-nav-school-timetable-me, refute #tab-nav-school-bulletins
# classes_live_test: "a form master filters to their classes with f=mine; the pill is absent for others"
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=a5 mix test test/teacher_assistant_web/spaces_test.exs test/teacher_assistant_web/live/role_spaces_test.exs test/teacher_assistant_web/live/school/classes_live_test.exs` — FAIL.
- [ ] **Step 3: Implement**; Gettext extract + EN (« Ma classe », « Mes classes »).
- [ ] **Step 4: Run** the three files + `test/teacher_assistant_web/controllers/page_controller_test.exs` + gettext tests — PASS.
- [ ] **Step 5: Commit** `feat(nav): teacher bar without Bulletins, « Ma classe » for form masters`.

---

### Task 2: The bulletin timeline on Mes cours, Stats link

**Files:**
- Create: `lib/teacher_assistant_web/components/bulletin_timeline.ex` (`TeacherAssistantWeb.BulletinTimeline`)
- Modify: `lib/teacher_assistant_web/live/school/bulletins_live.ex` (`steps/3` :101-161, `step_dot/1` :666, `seq_state/2` :671, `seq_tone/1` :679 move out; the teacher render keeps working until Task 3 deletes it)
- Modify: `lib/teacher_assistant_web/live/school/courses_live.ex` (`mount/3` :17-43, `handle_params/3` :45-48, render between the header :102-129 and the pills :143, course row :188-231)
- Modify: `lib/teacher_assistant/academics/teacher_courses.ex` moduledoc :4-6
- Test: `test/teacher_assistant_web/live/school/courses_live_test.exs`

**Interfaces:**
- `BulletinTimeline.steps(sequences, published?, today) :: [%{state: :done | :now | :later, title, sub}]` — the function moved verbatim from `BulletinsLive.steps/3` (same titles « Notes de la séquence %{n} », « Conseils de classe », « Publication des bulletins », same subs with `Dates.countdown/2`).
- `<BulletinTimeline.timeline id="bulletin-timeline" steps={steps} />` — on phones a `<details class="ta-section group">` whose `<summary>` shows the current step (the first `:now`, else the last `:done`, else the first) with its sub and a chevron (`group-open:rotate-180`, pattern of `my_day_live.ex:231-250`); the full `<ol>` (`li` with `data-state`, `step_dot/1` classes) is `hidden group-open:block sm:block` and the chevron `sm:hidden`. Ids: `#bulletin-timeline`, `#bulletin-timeline-current`, `#bulletin-steps`.
- `<BulletinTimeline.period_pills id="courses-period-tabs" periods={…} current={param} patch={fn param -> path end} />` — trimester and year pills only (séquence periods dropped, as `periods_for/2` does for non-publishers).
- `CoursesLive`: when `Scope.module?(scope, :notes)`, `periods = ReportCards.periods(scope, year)` without séquences; `?period=` param (default: the trimester containing `@seq`, else the year); `sequences = period séquences` (same filter as `BulletinsLive.period_sequences/3`, moved into `Organization.sequences_of_period/3` or kept local — builder's call); `published? = every class of the teacher's courses ∈ ReportCards.published_class_ids(scope, period)`; the pills and timeline render between the header and the filter pills. Module off → neither.
- Course row: a sibling of the main `<.link>` inside the `li`, `<.link id={"course-stats-#{course.id}"} navigate={~p"/school/statistics/me?period=seq:#{@seq.id}"} aria-label={gettext("Statistiques du cours")}>` with `hero-chart-bar` (text « Stats » from `sm`), only when `@seq` and the `notes` module is on.

- [ ] **Step 1: Write the failing tests**

```elixir
test "Mes cours shows the trimester pills and the timeline with the current step first", ctx
  # #courses-period-tabs with #period-trim-<id>[aria-current]; #bulletin-timeline-current =~ "Notes de la séquence 1"; #bulletin-steps li[data-state=now] exists
test "the timeline marks a published trimester done", ctx   # publish_trimester for every class of the teacher → li[data-state=done] "Publication des bulletins"
test "a course row links to its statistics", ctx            # #course-stats-<id> href =~ "/school/statistics/me?period=seq:"
test "without the notes module there is no timeline and no Stats link", ctx
```

- [ ] **Step 2: Run** `courses_live_test.exs` — FAIL.
- [ ] **Step 3: Implement** the component (move, don't copy: `BulletinsLive` calls `BulletinTimeline.steps/3` until Task 3), then `CoursesLive`; Gettext extract + EN.
- [ ] **Step 4: Run** `courses_live_test.exs` + `bulletins_live_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(courses): the bulletin timeline and period pills on Mes cours, Stats per course`.

---

### Task 3: Remove the Bulletins teacher view

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/bulletins_live.ex` (moduledoc :14-17; `handle_params/3` :55-61 third branch → `{:noreply, push_navigate(socket, to: ~p"/school/courses")}`; delete `teacher_view/2`, `period_sequences/3`, `seq_progress/3`, `render(%{mode: :teacher})` :684-805 and the helpers Task 2 did not move; `#back-to-teacher` :1105-1112 → `navigate={~p"/school/courses"}` labelled « Mes cours »)
- Modify: `lib/teacher_assistant/academics/teacher_courses.ex` (`progress/3` stays if still used by `CoursesLive`; else remove)
- Test: `test/teacher_assistant_web/live/school/bulletins_live_test.exs:371-410` (rewrite), `:101` (teacher of a published class still reads it)

**Interfaces:**
- `/school/bulletins` without `?class=` for a non-publisher → redirect to `/school/courses`. With `?class=<visible id>` → the class view as today (`:full` for the form master, `:published` for a teacher of the class). With an unknown id → the first visible class for a publisher; for a non-publisher, the first visible class too when they have one (today's behaviour), else `/school` (today's mount guard).

- [ ] **Step 1: Write the failing tests**

```elixir
test "a teacher without ?class= is sent to Mes cours"                       # live(conn, "/school/bulletins") → {:error, {:live_redirect, %{to: "/school/courses"}}}
test "a teacher of a published class still reads it with ?class=, with a way back to Mes cours"   # #back-to-teacher href "/school/courses", text "Mes cours"
test "a form master reads their class's draft with ?class="                 # access :full
# delete the assertions on #bulletins-teacher / #teacher-course- / #published- (moved to courses_live_test in Task 2)
```

- [ ] **Step 2: Run** `bulletins_live_test.exs` — FAIL (teacher view still rendered).
- [ ] **Step 3: Implement** the removal; `mix compile --warnings-as-errors` clean (unused helpers gone).
- [ ] **Step 4: Run** `bulletins_live_test.exs` + `courses_live_test.exs` + `test/teacher_assistant_web/live/school/notifications_live_test.exs` (publication link still opens the class view) — PASS.
- [ ] **Step 5: Commit** `refactor(bulletins): drop the teacher view; teachers land on Mes cours`.

---

### Task 4: Verify and merge

- [ ] Browser check on the demo school (worktree server on 4010, phone width): as prof@demo.test the bar (3 tabs + Plus), Mes cours with the timeline collapsed then opened, a trimester pill, a Stats link; as a form master the « Ma classe » tab opening the class; as the head switch to the enseignant space and back; `/school/bulletins` as a teacher lands on Mes cours; the publication notification link still opens the class view. Desktop width once for the rail.
- [ ] `MIX_TEST_PARTITION=a5 mix precommit` → exit 0 (refresh Gettext references if the check fails on line numbers); fast-forward merge into main; update memory `project-audit-2026-11-10` (A5 merged; the « no Bulletins entry for teachers » call).
