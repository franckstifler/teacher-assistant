# TeacherAssistant

This project is a Web App that aims to assist Schools and Teachers in their different activities.

It's structured based on the Cameroon educational system.

## Project documents

- [Domain knowledge base](docs/domain/README.md) — how the Cameroon education system actually
  works (subsystems, CBA/APC, teacher documents, grading & report cards, school roles & fees).
  **Source of truth for domain facts.**
- [Product definition](docs/PRODUCT.md)
- [Design system and UX direction](docs/DESIGN.md)

It is **mobile-first**, **bilingual (FR/EN)**, and marketed around the **Competency-Based
Approach (CBA / APC)**. It is built **teacher-first**: a teacher gets full value alone, and
schools layer official administration on top later. See [Product definition](docs/PRODUCT.md)
for the phased roadmap.

**Phase 1 — Independent teacher (in progress):**

- ✅ **v1 — Progression & Coverage (shipped).** Build a *fiche de progression* per subject × class,
  log what's actually taught (*cahier de textes*), and track **programme coverage** (*taux de
  couverture* — planned vs taught), with a guided year-setup wizard and a teacher dashboard.
  *(See the [design spec](docs/superpowers/specs/2026-06-26-teacher-progression-coverage-v1-design.md).)*
- ✅ **v1.1 — Assisted fiche import (shipped).** Upload an existing text-based fiche PDF and turn it
  into an editable draft progression plan, **deterministically (no AI)**. Requires `pdftotext`
  (see [System dependencies](#system-dependencies)). *(See the
  [design spec](docs/superpowers/specs/2026-06-27-fiche-import-v1_1-design.md).)*
- ✅ **v1.2 — Marks & mark register (shipped).** Per-subject mark register for the independent
  teacher: a shared class **roster**, free-form **assessments** per séquence, **/20 marks**, and
  deterministic **séquence statistics** (moyenne séquentielle, class average, *taux de réussite*,
  rank, garçons/filles split, mentions) — **deterministically (no AI)**. The official multi-subject
  *bulletin de notes* is deferred to the school layer (Phase 2). *(See the
  [design spec](docs/superpowers/specs/2026-07-01-teacher-marks-register-v1_2-design.md).)*
- Next: **v1.3** CBA lesson-plan (*fiche de préparation*) editor.

The app also ships a distinct visual identity — the **"Tableau" chalkboard theme** (dark default +
light *craie*), Fraunces + IBM Plex Mono, branded sign-in/registration, and a marketing landing
page. See the [Design system](docs/DESIGN.md).

**Phase 2 — School layer (later):** school workspaces, staff roles & councils, teacher
invitations, official report cards & statistics, enrollment, fees and fee-based access control.

## System dependencies

The **fiche import** feature (v1.1+) requires `pdftotext` (from `poppler-utils`) to extract text from PDF files. Without it installed, the import feature gracefully falls back to manual entry but PDF parsing will not be available.

**Installation:**
- **macOS:** `brew install poppler`
- **Debian/Ubuntu:** `apt-get install poppler-utils`
- **Other:** See [poppler documentation](https://poppler.freedesktop.org/)
