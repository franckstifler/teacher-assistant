# Exam Photos Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A « Photos examen » school page that draws each 1ère/Terminale candidate's exam picture (date, photo, name, exam code + CR code) in the browser and downloads the ticked ones as a zip, without touching the stored photo.

**Architecture:** Everything that can be decided without measuring text lives in Elixir and is unit-tested: the exam-code suggestion, the name variants (full → shortened), the codes line and the file names. The LiveView owns the codes (two new `ClassGroup` attributes), the ticks and the counts, and on export pushes one event with the ready-made items. A JS hook draws each picture on a canvas (picking the first name variant that fits, shrinking the font only as a last resort) and writes a stored (uncompressed) zip by hand.

**Tech Stack:** Elixir, Ash 3 (`ClassGroup` in the `TeacherAssistant.Enrollment` domain), Phoenix LiveView 1.2, plain ES modules bundled by esbuild (no npm), canvas + `toBlob`.

**Spec:** `docs/superpowers/specs/2026-10-29-exam-photos-export-design.md`

## Global Constraints

- The stored photo, `Student.photo_path` and `Student.photo_taken_at` are only **read**; no task writes them.
- Exam classes = classes of the current academic year whose `level` is `"1ère"` or `"Terminale"`.
- Exam-code suggestion: 1ère + F3/F4-BA/CG → `"PB" <> serie`; 1ère + AMEB/IH/ESF → `"PT" <> serie`; Terminale + F3/F4-BA → `"BA" <> serie`; Terminale + AMEB/IH/ESF → `"BT" <> serie`; anything else → `nil`.
- Picture: 600 px wide; top band 64 px (date `dd/mm/yyyy`, empty when the photo has no date); photo drawn 600×800 unscaled; bottom band 160 px (name line, then codes line); total 600×1024; white background; text bold sans serif (`Arial, Helvetica, sans-serif`) in `#1414C8`; JPEG quality 0.9. All of these in one constants block in `assets/js/exam_photos/draw.js`.
- Names: capitals; when too wide, words become initials **from the end**, **never the first two words**; if still too wide, smaller font until it fits — never cut.
- Codes line: exam code then the typed CR code, tokens joined by two spaces (`"PBF3  CR  8127"`).
- File name: `<exam code>_<FULL_NAME>.jpg`, accents removed, spaces → `_`, characters other than `A-Z 0-9 _ -` dropped; `_2`, `_3`… on collisions within a class; a missing exam code gives `SANS-CODE`.
- Zip: one folder per class (folder = class label made file-safe the same way); stored entries; names `photos-examen-<class label>.zip` for one class, `photos-examen-<yyyy-mm-dd>.zip` for a selection.
- Access: `Enrollment.can_manage_register?/1` (admin or conduct axis); module `:photos`.
- Gettext: French msgids, English translations filled, no `fuzzy` left after `mix gettext.extract --merge`.
- Migrations only through `mix ash.codegen --dev` (then `mix ash.migrate`); never reset the dev DB.
- Work in a worktree on branch `feat/exam-photos`; run tests with `MIX_TEST_PARTITION` set (parallel sessions share the test DB); stage explicit paths, never `git commit -a`.

## Review Focus

- A ticked student **without a photo**: never drawn, never in the zip; the page says how many were left out before download → Task 3 test `ticked students without a photo are counted and left out`.
- A class with **no exam code** yet (non-standard series, Tle CG): export still works, file named `SANS-CODE_…`, codes line shows only the CR code → Task 1 test `file_names/2 without an exam code` + Task 3 test `a class without a suggestion exports with an empty code`.
- **Accented and odd names** (« Hervé N'DIAYE-ÉKOLLO », double spaces): name line upcased with accents kept, file name ASCII-only → Task 1 tests on `name_variants/1` and `file_names/2`.
- **Two students with the same name** in one class: distinct files, nothing overwritten in the zip → Task 1 test `file_names/2 deduplicates`.
- **Codes typed with stray spaces** (« cr  8127 ») or cleared to empty: trimmed, empty stored as `nil`, the default CR never overwrites a class that has one → Task 2 test + Task 3 test `the default CR code fills only empty classes`.

---

### Task 1: `TeacherAssistant.ExamPhotos` — pure rules

**Files:**
- Create: `lib/teacher_assistant/exam_photos.ex`
- Test: `test/teacher_assistant/exam_photos_test.exs`

**Interfaces:**
- Produces:
  - `ExamPhotos.exam_levels() :: [String.t()]` → `["1ère", "Terminale"]`
  - `ExamPhotos.suggested_exam_code(level :: String.t(), serie :: String.t() | nil) :: String.t() | nil`
  - `ExamPhotos.name_variants(full_name :: String.t()) :: [String.t(), ...]` — capitals, most complete first, last = shortest allowed
  - `ExamPhotos.codes_line(exam_code :: String.t() | nil, center_code :: String.t() | nil) :: String.t()`
  - `ExamPhotos.file_names(exam_code :: String.t() | nil, students :: [%{id: String.t(), full_name: String.t()}]) :: %{String.t() => String.t()}` (student id → file name)
  - `ExamPhotos.safe_segment(text :: String.t()) :: String.t()` — the ASCII rule shared by file and folder names
  - `ExamPhotos.photo_date(DateTime.t() | nil) :: String.t() | nil` → `"23/11/2025"` in the school's time zone (`Africa/Douala`, UTC+1, no DST — add the hour, no tz database needed)

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.ExamPhotosTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.ExamPhotos

  test "suggested_exam_code/2 follows the series table" do
    assert ExamPhotos.suggested_exam_code("1ère", "F3") == "PBF3"
    assert ExamPhotos.suggested_exam_code("1ère", "F4-BA") == "PBF4-BA"
    assert ExamPhotos.suggested_exam_code("1ère", "CG") == "PBCG"
    assert ExamPhotos.suggested_exam_code("1ère", "AMEB") == "PTAMEB"
    assert ExamPhotos.suggested_exam_code("1ère", "IH") == "PTIH"
    assert ExamPhotos.suggested_exam_code("1ère", "ESF") == "PTESF"
    assert ExamPhotos.suggested_exam_code("Terminale", "F3") == "BAF3"
    assert ExamPhotos.suggested_exam_code("Terminale", "F4-BA") == "BAF4-BA"
    assert ExamPhotos.suggested_exam_code("Terminale", "AMEB") == "BTAMEB"
    assert ExamPhotos.suggested_exam_code("Terminale", "IH") == "BTIH"
    assert ExamPhotos.suggested_exam_code("Terminale", "ESF") == "BTESF"
    assert ExamPhotos.suggested_exam_code("Terminale", "CG") == nil
    assert ExamPhotos.suggested_exam_code("2nde", "F3") == nil
    assert ExamPhotos.suggested_exam_code("1ère", nil) == nil
  end

  test "name_variants/1 shortens from the end, never the first two words" do
    assert ExamPhotos.name_variants("Biyong Ndjeng Emmanuel Patrice") == [
             "BIYONG NDJENG EMMANUEL PATRICE",
             "BIYONG NDJENG EMMANUEL P.",
             "BIYONG NDJENG E. P."
           ]

    assert ExamPhotos.name_variants("  Ateba   Ben ") == ["ATEBA BEN"]
    assert ExamPhotos.name_variants("Hervé N'Diaye-Ékollo Zoé") ==
             ["HERVÉ N'DIAYE-ÉKOLLO ZOÉ", "HERVÉ N'DIAYE-ÉKOLLO Z."]
  end

  test "codes_line/2 joins every token with two spaces" do
    assert ExamPhotos.codes_line("PBF3", " cr  8127 ") == "PBF3  CR  8127"
    assert ExamPhotos.codes_line(nil, "CR 8127") == "CR  8127"
    assert ExamPhotos.codes_line("PBF3", nil) == "PBF3"
    assert ExamPhotos.codes_line(nil, nil) == ""
  end

  test "file_names/2 is ASCII, capitalised and deduplicates" do
    students = [
      %{id: "a", full_name: "Hervé N'Diaye-Ékollo"},
      %{id: "b", full_name: "Ngono Jean"},
      %{id: "c", full_name: "Ngono  Jean"}
    ]

    assert ExamPhotos.file_names("PBF4-BA", students) == %{
             "a" => "PBF4-BA_HERVE_NDIAYE-EKOLLO.jpg",
             "b" => "PBF4-BA_NGONO_JEAN.jpg",
             "c" => "PBF4-BA_NGONO_JEAN_2.jpg"
           }
  end

  test "file_names/2 without an exam code" do
    assert ExamPhotos.file_names(nil, [%{id: "a", full_name: "Ngono Jean"}]) ==
             %{"a" => "SANS-CODE_NGONO_JEAN.jpg"}
  end

  test "photo_date/1 is the Douala day" do
    assert ExamPhotos.photo_date(~U[2025-11-23 22:59:00Z]) == "23/11/2025"
    assert ExamPhotos.photo_date(~U[2025-11-23 23:30:00Z]) == "24/11/2025"
    assert ExamPhotos.photo_date(nil) == nil
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_TEST_PARTITION=exam mix test test/teacher_assistant/exam_photos_test.exs`
Expected: FAIL — `TeacherAssistant.ExamPhotos` is undefined.

- [ ] **Step 3: Implement `lib/teacher_assistant/exam_photos.ex`**

Pure module, no DB. Name variants: split on whitespace, upcase each word (`String.upcase/1` keeps accents); variant *k* turns the last *k* words (only words at index ≥ 2) into `first grapheme <> "."`. Accent removal for `safe_segment/1`: `:unicode.characters_to_nfd_binary/1`, drop combining marks (`~r/\p{Mn}/u`), upcase, whitespace runs → `_`, then drop anything outside `[A-Z0-9_-]`. Dedupe in input order.

- [ ] **Step 4: Run to verify it passes**

Run: `MIX_TEST_PARTITION=exam mix test test/teacher_assistant/exam_photos_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/exam_photos.ex test/teacher_assistant/exam_photos_test.exs
git commit -m "feat(exam-photos): exam code, name, codes line and file name rules"
```

---

### Task 2: Exam codes on the class

**Files:**
- Modify: `lib/teacher_assistant/academics/class_group.ex` (attributes after `:paper_roll_call`, action next to `:set_paper_roll_call`, policy next to its policy)
- Modify: `lib/teacher_assistant/enrollment.ex:20-22` (code interface)
- Create: migration + snapshot via `mix ash.codegen --dev exam_codes_on_class` then `mix ash.migrate`
- Test: `test/teacher_assistant/academics/class_group_exam_codes_test.exs`

**Interfaces:**
- Produces:
  - `ClassGroup` attributes `:exam_code` and `:exam_center_code`, both `:string`, `allow_nil?: true`, `public?: true`.
  - Update action `:set_exam_codes` accepting both, trimming them and storing `""` as `nil` (an inline `change` or `Ash.Type` constraint `trim?: true, allow_empty?: false`), `require_atomic? false` like `:set_paper_roll_call`.
  - `Enrollment.set_exam_codes(class_group, %{exam_code: _, exam_center_code: _}, scope: scope) :: {:ok, ClassGroup.t()} | {:error, term}` (`define :set_exam_codes, action: :set_exam_codes`).
  - Policy: admin or conduct axis (same as `:set_paper_roll_call`).

- [ ] **Step 1: Write the failing tests**

```elixir
test "admins and conduct managers set the codes, trimmed, empty as nil", %{scope: head, cg: cg, sg: sg} do
  assert {:ok, cg} =
           Enrollment.set_exam_codes(cg, %{exam_code: " PBF3 ", exam_center_code: "CR 8127"}, scope: head)
  assert {cg.exam_code, cg.exam_center_code} == {"PBF3", "CR 8127"}

  assert {:ok, cg} = Enrollment.set_exam_codes(cg, %{exam_code: "", exam_center_code: "CR 9"}, scope: sg)
  assert {cg.exam_code, cg.exam_center_code} == {nil, "CR 9"}
end

test "a teacher cannot set them", %{scope: head, cg: cg} do
  teacher = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})
  assert {:error, %Ash.Error.Forbidden{}} =
           Enrollment.set_exam_codes(cg, %{exam_code: "PBF3"}, scope: teacher)
end
```

Setup as in `class_photos_live_test.exs`: `setup_complete_school_fixture()`, a `"1ère F3"` class (`level: "1ère", serie: "F3"`), `sg` with `roles: [:discipline_master]`. Check the teacher role atom against `TeacherAssistant.Accounts.SchoolRole` before writing it.

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_TEST_PARTITION=exam mix test test/teacher_assistant/academics/class_group_exam_codes_test.exs`
Expected: FAIL — `set_exam_codes/3` undefined.

- [ ] **Step 3: Add the attributes, action, policy and code interface; run `mix ash.codegen --dev exam_codes_on_class` and `mix ash.migrate`**

- [ ] **Step 4: Run to verify it passes**

Run: `MIX_TEST_PARTITION=exam mix test test/teacher_assistant/academics/class_group_exam_codes_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/class_group.ex lib/teacher_assistant/enrollment.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant/academics/class_group_exam_codes_test.exs
git commit -m "feat(exam-photos): exam and CR codes on the class"
```

---

### Task 3: The « Photos examen » page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/exam_photos_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex:147` (route next to `ClassPhotosLive`)
- Modify: `lib/teacher_assistant/modules.ex:59` (`photos: [W.School.ClassPhotosLive, W.School.ExamPhotosLive]`)
- Modify: `lib/teacher_assistant_web/spaces.ex` (an `exam_photos()` item after `students()` in the proviseur, censeur and surveillant spaces)
- Test: `test/teacher_assistant_web/live/school/exam_photos_live_test.exs`

**Interfaces:**
- Consumes: Task 1 functions; `Enrollment.set_exam_codes/3`; `Enrollment.list_class_groups/3`, `Enrollment.list_roster/2`, `Enrollment.can_manage_register?/1`; `StudentPhotoComponents.student_photo_url/1`.
- Produces (for Task 4):
  - Route `live "/school/exam-photos", School.ExamPhotosLive, :index`; menu item id `"exam-photos"`, label `gettext("Photos examen")`, icon `"hero-camera"`.
  - Container `<div id="exam-photos" phx-hook="ExamPhotos">`.
  - Each preview: `<canvas id={"exam-card-#{student.id}"} phx-hook="ExamCard" phx-update="ignore" data-card={Jason.encode!(card)} width="600" height="1024">`, where `card = %{photo_url:, date:, names:, codes:}` (`date` from `photo_date/1`, `names` from `name_variants/1`, `codes` from `codes_line/2`). A student without a photo renders a « Sans photo » tile linking to `~p"/school/classes/#{cg.id}/photos"` instead.
  - On export: `push_event(socket, "exam-photos:build", %{zip_name: String.t(), items: [%{folder:, file:, photo_url:, date:, names:, codes:}]})` — only ticked students **with** a photo.

Page behaviour (spec « export page » mockup): DOM ids `#exam-default-center` (form, phx-submit `"fill_center"`), `#exam-class-<id>` rows with a codes form (phx-change `"save_codes"`, debounce 600, fields `exam_code`, `exam_center_code`, hidden `class_id`), `#exam-count-<id>` (« 18 / 19 » + « · 1 sans photo »), `#exam-open-<id>` (phx-click `"open"`), tick boxes `#exam-tick-<student id>` (phx-click `"toggle"`), `#exam-all-<id>` / `#exam-none-<id>` (`"tick_all"` / `"tick_none"`), `#exam-zip-<id>` (phx-click `"export"` with `phx-value-class`), `#exam-zip-selection` (phx-click `"export"`, label « Télécharger la sélection · N photos »), `#exam-left-out` warning (« N élève(s) coché(s) sans photo ne seront pas exportés »). State: `ticked` is a `MapSet` of student ids, initialised to every exam-class student; it survives `open`. Codes shown = stored value, else (exam code only) `suggested_exam_code/2`; the suggestion is what gets exported until the user edits it. `"fill_center"` sets `exam_center_code` on every exam class whose code is `nil` and leaves the others. Mount guard as in `ClassPhotosLive.mount/3` (`Authz.put_not_allowed` + navigate to `/school`); no current academic year → empty state text.

- [ ] **Step 1: Write the failing tests**

Setup: `setup_complete_school_fixture()`; classes `"1ère F3"` (`level: "1ère", serie: "F3"`), `"Tle CG"` (`level: "Terminale", serie: "CG"`), `"2nde F3"` (`level: "2nde", serie: "F3"`); students Awa and Ben in 1ère F3 (Awa gets a photo with `StudentPhotos.store(scope, awa, "test/support/fixtures/files/1x1.jpg")`), Zoé in Tle CG with a photo; `sg` with `roles: [:discipline_master]`; `conn_for/2` as in `class_photos_live_test.exs`.

```elixir
test "lists exam classes only, with the suggested code", %{sg: sg, ws: ws, f3: f3, cg_tle: tle, seconde: seconde} do
  {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  assert has_element?(view, "#exam-class-#{f3.id} input[name=exam_code][value=PBF3]")
  assert has_element?(view, "#exam-class-#{tle.id}")
  refute has_element?(view, "#exam-class-#{seconde.id}")
  assert view |> element("#exam-count-#{f3.id}") |> render() =~ "1 / 2"
end

test "a teacher is sent away", %{scope: head, ws: ws} do
  teacher = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})
  assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn_for(teacher, ws), ~p"/school/exam-photos")
end

test "saving codes stores them on the class", %{sg: sg, ws: ws, f3: f3} do
  {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  view |> form("#exam-class-#{f3.id} form", %{class_id: f3.id, exam_code: "PBF3", exam_center_code: "CR 8127"}) |> render_change()
  assert {:ok, %{exam_code: "PBF3", exam_center_code: "CR 8127"}} = Enrollment.fetch_owned_class_group(sg, f3.id)
end

test "the default CR code fills only empty classes", %{sg: sg, ws: ws, f3: f3, cg_tle: tle} do
  {:ok, _} = Enrollment.set_exam_codes(f3, %{exam_center_code: "CR 1"}, scope: sg)
  {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  view |> form("#exam-default-center", %{center: "CR 8127"}) |> render_submit()
  assert {:ok, %{exam_center_code: "CR 1"}} = Enrollment.fetch_owned_class_group(sg, f3.id)
  assert {:ok, %{exam_center_code: "CR 8127"}} = Enrollment.fetch_owned_class_group(sg, tle.id)
end

test "ticked students without a photo are counted and left out", %{sg: sg, ws: ws, f3: f3, awa: awa} do
  {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  assert view |> element("#exam-left-out") |> render() =~ "1"
  view |> element("#exam-zip-#{f3.id}") |> render_click()
  assert_push_event(view, "exam-photos:build", %{zip_name: "photos-examen-1ERE_F3.zip", items: [item]})
  assert item.file == "PBF3_AWA_NGONO.jpg"
  assert item.folder == "1ERE_F3"
  assert item.names == ["AWA NGONO"]
end

test "ticks carry across classes into the selection export", %{sg: sg, ws: ws, f3: f3, awa: awa, zoe: zoe} do
  {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  view |> element("#exam-none-#{f3.id}") |> render_click()
  view |> element("#exam-tick-#{awa.id}") |> render_click()
  assert view |> element("#exam-zip-selection") |> render() =~ "2"
  view |> element("#exam-zip-selection") |> render_click()
  assert_push_event(view, "exam-photos:build", %{items: items})
  assert items |> Enum.map(& &1.photo_url) |> length() == 2
end

test "a class without a suggestion exports with an empty code", %{sg: sg, ws: ws, cg_tle: tle} do
  {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  view |> element("#exam-zip-#{tle.id}") |> render_click()
  assert_push_event(view, "exam-photos:build", %{items: [%{file: "SANS-CODE_ZOE.jpg", codes: ""}]})
end

test "the SG's menu links to the page", %{sg: sg, ws: ws} do
  {:ok, _view, html} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  assert html =~ ~s(href="/school/exam-photos")
end
```

Adjust names to the fixtures (Awa's full name is `"Awa Ngono"`; Zoé is `"Zoé"` so her file is `SANS-CODE_ZOE.jpg`). The module-off case is already covered for every `@views` entry by `test/teacher_assistant_web/router_modules_test.exs`.

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_TEST_PARTITION=exam mix test test/teacher_assistant_web/live/school/exam_photos_live_test.exs`
Expected: FAIL — no route `/school/exam-photos`.

- [ ] **Step 3: Implement route, `Modules` entry, menu item and `ExamPhotosLive`**

`<Layouts.app flash={@flash} current_scope={@current_scope}>` like the other school pages; daisyUI table on desktop, stacked rows on phones (one row per class; the open class's previews in a 2-column grid on phones, 4–6 on desktop). Previews are the `ExamCard` canvases (Task 4 draws them); until JS runs they show as blank 600×1024 boxes scaled by CSS (`w-full h-auto`).

- [ ] **Step 4: Run to verify it passes**

Run: `MIX_TEST_PARTITION=exam mix test test/teacher_assistant_web/live/school/exam_photos_live_test.exs test/teacher_assistant_web/router_modules_test.exs test/teacher_assistant/modules_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/exam_photos_live.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant/modules.ex lib/teacher_assistant_web/spaces.ex test/teacher_assistant_web/live/school/exam_photos_live_test.exs
git commit -m "feat(exam-photos): Photos examen page with codes, ticks and export event"
```

---

### Task 4: Drawing, zip and download in the browser

**Files:**
- Create: `assets/js/exam_photos/draw.js`, `assets/js/exam_photos/zip.js`, `assets/js/hooks/exam_photos.js`
- Modify: `assets/js/app.js:27-29,52` (import and register `ExamPhotos`, `ExamCard`)

**Interfaces:**
- Consumes: the `data-card` JSON and the `exam-photos:build` payload from Task 3.
- Produces:
  - `draw.js`: `export async function drawExamCard(canvas, {photo_url, date, names, codes})` — draws onto a 600×1024 canvas per the Global Constraints. Name: first entry of `names` whose `measureText` width ≤ 552 at 30 px; if none, the last entry with the font reduced 1 px at a time (floor 12 px). Codes line at 46 px, centred. Photo fetched with `fetch(photo_url, {credentials: "same-origin"})` → `createImageBitmap`.
  - `zip.js`: `export function storedZip(files /* [{name: string, data: Uint8Array}] */) /* → Blob "application/zip" */` — local headers + central directory + end record, method 0 (stored), CRC-32 (table-driven), UTF-8 name flag (bit 11), DOS date of now.
  - `hooks/exam_photos.js`: `export const ExamCard` (`mounted`/`updated` → `drawExamCard(this.el, JSON.parse(this.el.dataset.card))`) and `export const ExamPhotos` (`handleEvent("exam-photos:build", …)` → for each item draw on an off-screen canvas, `toBlob("image/jpeg", 0.9)`, collect `{name: folder + "/" + file, data}`, `storedZip`, download via a temporary `<a download>` + `URL.createObjectURL`, revoke after). While building, the button area shows « Préparation… n/N » (a `data-role="progress"` element inside `#exam-photos`, text set by the hook); a failed photo fetch skips that student and the hook ends with `this.pushEvent("export_failed", {count})`, which the LiveView turns into an error flash (Step 2).

- [ ] **Step 1: Write the zip writer, then check it with a throwaway Node script (not committed)**

Run (from the worktree root):
```bash
node --input-type=module -e "
import {storedZip} from './assets/js/exam_photos/zip.js';
import {writeFileSync} from 'node:fs';
const enc = new TextEncoder();
const blob = storedZip([{name: '1ERE_F3/PBF3_AWA.jpg', data: enc.encode('hello')}, {name: 'TLE_IH/BTIH_ZOE.jpg', data: enc.encode('world!')}]);
writeFileSync(process.env.TMPDIR + '/t.zip', Buffer.from(await blob.arrayBuffer()));
" && unzip -t "$TMPDIR/t.zip"
```
Expected: `No errors detected in compressed data of …/t.zip.` with both entries listed.

- [ ] **Step 2: Write the failing LiveView test for a failed export, in `exam_photos_live_test.exs`**

```elixir
test "a failed export tells the user how many photos were skipped", %{sg: sg, ws: ws} do
  {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
  assert render_hook(view, "export_failed", %{"count" => 2}) =~ "2"
end
```

Run: `MIX_TEST_PARTITION=exam mix test test/teacher_assistant_web/live/school/exam_photos_live_test.exs`
Expected: FAIL (no `handle_event("export_failed", …)`); add it (error flash « %{count} photo(s) n'ont pas pu être préparées ») and rerun → PASS.

- [ ] **Step 3: Write `draw.js` and the hooks; register them in `app.js`; `mix assets.build`**

Expected: build succeeds with no esbuild warnings.

- [ ] **Step 4: Browser check on the dev server (phone viewport 375×812, then desktop)**

On the demo school (see `reference-demo-school-seed`: sign in as the censeur or SG), give 2–3 students of a 1ère/Tle class a photo with the class séance (stub `getUserMedia` with a canvas `captureStream()` as in the photo-studio check) and set one name long enough to need shortening. Open `/school/exam-photos`:
- previews show the date, photo, name and codes like the reference; the long name is shortened from the end with the first two words whole;
- « Zip » downloads a file; check its contents in the page with `unzip -l` after saving, or by reading the blob in `javascript_tool` (entry names `FOLDER/CODE_NAME.jpg`, each a valid JPEG 600×1024);
- the student without a photo is counted and absent from the zip.
Afterwards remove the test photos you added (photo sheet → « Supprimer la photo ») so the demo data is as before.

- [ ] **Step 5: Commit**

```bash
git add assets/js/exam_photos/draw.js assets/js/exam_photos/zip.js assets/js/hooks/exam_photos.js assets/js/app.js lib/teacher_assistant_web/live/school/exam_photos_live.ex test/teacher_assistant_web/live/school/exam_photos_live_test.exs
git commit -m "feat(exam-photos): draw exam pictures and zip them in the browser"
```

---

### Task 5: Translations and the full suite

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/{fr,en}/LC_MESSAGES/default.po`

- [ ] **Step 1: `mix gettext.extract --merge`; fill every new English `msgstr` (« Photos examen » → "Exam photos", « Sans photo » already exists, etc.); remove every `fuzzy` flag the merge added and give those entries their correct translation**

Run: `grep -c fuzzy priv/gettext/*/LC_MESSAGES/default.po`
Expected: `0` for both files.

- [ ] **Step 2: Full check**

Run: `MIX_TEST_PARTITION=exam mix precommit`
Expected: formatter, credo/compile and every test pass (note: precommit does not fail on warnings — read the compile output for new warnings and fix them).

- [ ] **Step 3: Commit**

```bash
git add priv/gettext/default.pot priv/gettext/fr/LC_MESSAGES/default.po priv/gettext/en/LC_MESSAGES/default.po
git commit -m "chore(exam-photos): translations"
```
