# Design Spec — Assisted Fiche Import (v1.1)

**Date:** 2026-06-27
**Status:** Approved design → ready for implementation planning
**Builds on:** v1 (Progression & Coverage) — see
[`2026-06-26-teacher-progression-coverage-v1-design.md`](2026-06-26-teacher-progression-coverage-v1-design.md)
**Domain source of truth:** [`docs/domain/`](../../domain/README.md) (esp.
[`03-teacher-documents.md`](../../domain/03-teacher-documents.md))

---

## 1. Background & goal

The *fiche de progression* is the pivot document Cameroonian teachers already have — usually shared
as a PDF in WhatsApp groups. v1 makes teachers **build** it by hand; v1.1 lets them **import** an
existing fiche PDF and turn it into a usable progression plan in minutes.

**Goal:** a teacher with a digital fiche PDF can upload it, see its content extracted into editable
draft rows, fix what the parser got wrong, and save it as a new draft `ProgressionPlan` — entirely
on their phone, with no AI dependency.

## 2. Settled decisions (from brainstorming)

| Decision | Choice |
|---|---|
| **Input format** | Digital PDFs with real, selectable text (not scans/photos). |
| **Extraction intelligence** | **Deterministic** parsing — no AI / no external API. |
| **Entry point** | Import **creates a new** progression plan (not append-to-existing). |
| **Auto-fill ambition** | Core + type + week: `module`, `lesson_title`, `planned_hours`, `entry_type`, `week_no`, sequence number. CBA fields stay manual. |
| **Extraction engine** | Server-side `pdftotext -layout` (poppler-utils) + a pure Elixir parser. |

## 3. Non-goals (v1.1)

- Scanned images / photo fiches / OCR — that is the later **AI/vision** increment.
- AI / LLM structuring of any kind.
- **Appending** imported rows into an existing plan (deferred; v1.1 only creates new plans).
- Multi-file / batch import.
- Parsing **CBA fields** (famille de situations, catégories d'action, compétence visée) — too
  irregular to parse reliably; they remain manual.
- **Storing** the uploaded PDF — it is parsed from the temp path and discarded.

## 4. User flow

1. **Enter** — from a "Import a fiche (PDF)" button on the dashboard (including the empty
   "no plan yet" state). Precondition: an active academic year + ≥1 teaching context. With no
   teaching context, the screen gates the teacher to setup.
2. **Pick + upload** — select the teaching context (subject×class for the active year), optionally
   edit the plan title, upload one PDF (`allow_upload`, `.pdf`, ~10 MB cap).
3. **Extract** — server runs `pdftotext -layout <tmpfile> -` → column-aligned plain text. PDF is
   never stored.
4. **Parse** — `FicheParser` turns text into draft rows (§6).
5. **Review** — draft rows render in an editable table; teacher fixes cells, adds/removes rows,
   assigns sequences (§7).
6. **Save** — `import_progression_plan/3` creates the draft plan + entries transactionally,
   owner-scoped, then navigates to the fiche builder.

## 5. Architecture & components

```
ImportLive (LiveView)
  ├─ upload form: teaching-context select + title + <.live_file_input :fiche>
  ├─ on submit → FicheExtractor.extract(tmp_path)  ── injected (configurable) ──┐
  │                                                                              │
  │   default impl: System.cmd("pdftotext", ["-layout", path, "-"])             │
  │   test impl:    returns fixture text (no poppler needed)                    │
  ├─ FicheParser.parse(text) → %{rows: [...], confidence: :high | :low}  (pure) │
  ├─ editable review table (rows held in assigns; add/edit/delete/reorder)      │
  └─ save → Academics.import_progression_plan(ws, attrs, rows)  (transactional)─┘
```

- **`TeacherAssistant.Academics.FicheExtractor`** — thin wrapper around `pdftotext`; the function
  is **injected** via `Application.get_env(:teacher_assistant, :fiche_extractor)` so tests stub it.
  Returns `{:ok, text}` | `{:error, reason}`. A missing `pdftotext` binary surfaces as
  `{:error, _}`, never a crash.
- **`TeacherAssistant.Academics.FicheParser`** — pure; the heuristic engine (§6).
- **`TeacherAssistantWeb.Teacher.ImportLive`** — the screen (§7).
- **`Academics.import_progression_plan/3`** — transactional persistence (§8).

## 6. The parser (`FicheParser`)

**Signature:** `parse(layout_text) :: {:ok, %{rows: [row], confidence: :high | :low}}`
where `row = %{module, lesson_title, planned_hours, entry_type, week_no, sequence_no, raw}`.

**Heuristics, in order:**
1. **Clean** — split into lines; drop blanks and recurring boilerplate (page numbers,
   "République du Cameroun…", per-page repeated headers).
2. **Find header row** — match bilingual column keywords: `module|chapitre`,
   `leçon|lesson|contenu|titre`, `durée|heures|hours|h`, `semaine|week`, `séquence|sequence`.
   The header's word positions define **column boundaries** (relies on `-layout` space alignment).
3. **Slice** each data line by those boundaries → cells → map to fields via the header.
4. **`entry_type`** from content keywords: évaluation→`:evaluation`, intégration→`:integration`,
   remédiation→`:remediation`, révision→`:revision`, correction→`:correction`,
   congé/holiday→`:holiday`, else `:lesson`.
5. **`planned_hours`** — first number in the duration cell (`"2h"`, `"2"`, `"1,5"`→`1.5`);
   default `1` when missing/garbage.
6. **`week_no` / `sequence_no`** — integers from those columns when present.
7. **Confidence** — `:high` if a header was found and a reasonable share of lines parsed into
   ≥2 fields; otherwise `:low`.

**Low confidence** (no header, or almost nothing parsed): return whatever rows were salvaged **plus
the raw lines**, so the review screen falls back to a manual grid with the extracted text shown for
reference. **The parser never throws** — worst case is `{:ok, %{rows: [], confidence: :low}}` with
raw text available.

**Honest limits by design:** `sequence_no` is captured as a *number* and mapped to the year's real
sequence in review (not blindly guessed); CBA fields are never parsed.

## 7. Review screen (`ImportLive`)

- **Editable table**, one row per draft entry: `module`, `lesson_title`, `hours`, `type` (select of
  the seven entry types), `week` (number), `sequence` (select of the year's six sequences). Cells
  editable; **delete row**, **add blank row**, reorder by position.
- **Summary banner** on success: *"Parsed N rows from your fiche — review and fix before saving."*
- **Low-confidence state:** warning banner + raw extracted text in a collapsible, over an
  empty/partial grid, so the teacher can still build manually.
- **Actions:** Save as draft plan / Discard. **Plan title** defaults from the teaching context
  (subject · class), editable.
- **Stable DOM ids** for tests (e.g. `#fiche-import`, `#import-upload-form`,
  `#import-context-select`, `#import-review`, `#import-rows`, `#import-save`).

## 8. Persistence (`import_progression_plan/3`)

`import_progression_plan(workspace, attrs, rows)`:
- In **one Ash transaction**: create the `ProgressionPlan` (status `:draft`) and all entries with
  `position` set by order. A mid-way failure rolls back → **no orphan plan** (correcting the known
  non-transactional behavior of `duplicate_progression_plan`).
- **Owner-scoped:** the teaching context and academic year are verified to belong to `workspace`
  before any write; otherwise `{:error, :not_found}`.
- Returns `{:ok, plan}` | `{:error, reason}`.

## 9. Error handling

| Situation | Behavior |
|---|---|
| Non-PDF / `pdftotext` failure / empty text | Flash *"Couldn't read that PDF. Try another file, or build the plan manually."* → manual grid. |
| `poppler` binary missing | Same graceful `{:error, _}` path; never a crash. |
| Parser low confidence | Manual fallback grid + raw text; teacher can still save. |
| Excessive rows | Capped (~300) with a notice. |
| Upload too large / wrong type | Rejected by `allow_upload` constraints with inline message. |

## 10. Testing

- **`FicheParser` (core):** fixture `-layout` text — a clean tabular FR sample, a clean EN sample,
  and a messy/no-header sample. Assert parsed rows, `entry_type` detection, hours/week parsing,
  header detection, and the low-confidence fallback.
- **`import_progression_plan/3`:** transactional success; rollback on a bad row (no plan persists);
  owner scoping (foreign context rejected).
- **`ImportLive`:** extractor **stubbed** to fixture text — upload → review renders rows → edit a
  cell → save creates plan + entries; ownership guard (cannot import into another teacher's
  context); low-confidence renders the manual fallback.

## 11. Success criteria (definition of done)

- A teacher can upload a text-based fiche PDF and get editable draft rows without writing anything
  by hand first.
- They can correct rows and save a new **draft `ProgressionPlan`** with entries, owner-scoped, in a
  single transaction.
- A messy/unparseable PDF never crashes — it degrades to a manual grid with the extracted text.
- Parser behavior is covered by fixture-based unit tests; the LiveView flow is covered without
  requiring poppler in the test environment.
- `mix precommit` green.

## 12. Deployment note

Adds a runtime system dependency: **`poppler-utils`** (`pdftotext`). Must be installed in the
server / Docker image. Its absence is handled gracefully at runtime (manual fallback), but the
feature is non-functional without it.
