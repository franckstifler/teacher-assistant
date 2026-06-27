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

- v1 — Build a *fiche de progression* per subject × class and track **programme coverage**
  (planned vs taught). *(See the current
  [design spec](docs/superpowers/specs/2026-06-26-teacher-progression-coverage-v1-design.md).)*
- Next: assisted import of existing fiches → marks & report cards → CBA lesson planning.

**Phase 2 — School layer (later):** school workspaces, staff roles & councils, teacher
invitations, official report cards & statistics, enrollment, fees and fee-based access control.
