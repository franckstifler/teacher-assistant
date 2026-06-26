# Domain Knowledge Base — Cameroon Education System

This folder is the **source of truth for how the Cameroonian education system actually works**.
It exists so that product, data-model, and UI decisions are grounded in real Cameroonian
school practice — not generic SaaS assumptions.

It was assembled from deep web research (Aug 2025–Jun 2026 sources) cross-checked against
primary legal texts and real artifacts (ministerial decisions, exam-board pages, actual
report cards, and official syllabus PDFs). Every non-obvious claim carries a source link.

> **These are reference docs, not the product spec.** The product design lives in
> `docs/PRODUCT.md` / `docs/DESIGN.md` and the specs under `docs/superpowers/specs/`.
> When product docs and these domain docs disagree about *how Cameroon works*, the domain
> docs win — fix the product doc.

## Contents

1. [`01-education-system.md`](01-education-system.md) — the two subsystems, levels, classes
   & séries, national exams, academic calendar, school types, ministries.
2. [`02-cba-pedagogy.md`](02-cba-pedagogy.md) — the Competency-Based Approach (APC/CBA):
   model, vocabulary, lesson structure, assessment philosophy.
3. [`03-teacher-documents.md`](03-teacher-documents.md) — the documents teachers actually
   use: official syllabus, **fiche de progression / scheme of work**, lesson plan, cahier de
   textes, grade book, attendance sheet — with concrete column layouts.
4. [`04-grading-and-report-cards.md`](04-grading-and-report-cards.md) — sequences/terms,
   the /20 scale, coefficients, average formulas, the bulletin, mentions, statistics.
5. [`05-school-roles-and-fees.md`](05-school-roles-and-fees.md) — administrative roles &
   councils, teacher↔school relationship, school fees, fee-based access control, enrollment.
6. [`glossary-fr-en.md`](glossary-fr-en.md) — bilingual (FR↔EN) controlled vocabulary.

## Confidence legend (used throughout)

- ✅ **Confirmed** — grounded in a primary source (ministerial text, exam board, real artifact)
  or corroborated by multiple independent sources.
- 🟡 **Variable** — real and widely practised, but the exact form varies by school / subject /
  author. Model it as **configurable**, not constant.
- ⚠️ **Uncertain / flagged** — single source, secondary citation, or sources disagree. Verify
  against a current official document before hard-coding.

## Cross-cutting rules for anyone building on this

- **The system is bilingual by law**, not by translation. Francophone (French model) and
  Anglophone (British model) are two tracks of *one* national system. Carry both FR and EN
  labels for every domain concept; see the glossary.
- **Almost every number is a per-school / per-year setting**, not a national constant: fee
  amounts, coefficients (by série), devoirs per sequence, distinction thresholds, conduct
  scale, promotion rules. Hard-code only the items marked ✅ in
  [`04-grading-and-report-cards.md`](04-grading-and-report-cards.md).
- **The calendar is re-issued every August by ministerial decision** — model the year (term &
  sequence boundaries, holidays) as configurable per-year data.
