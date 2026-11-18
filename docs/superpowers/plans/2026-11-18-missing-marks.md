# Missing marks implementation plan

**Goal:** Give the censeur a student-level missing marks report and teachers a shortcut to finish a pending assessment.

**Architecture:** Extend `EntryProgress` with a batched missing-entry reader using the existing sequence roster and exemptions. `SequenceTrackingLive` loads a student report on demand; `CoursesLive` links to the first incomplete assessment of the editable sequence; `MarksLive` supports opening that assessment with only missing entries visible.

- [x] Compare expected students with the saved student IDs per assessment. Keep courses without an assessment separate and use existing handling for departures and exemptions.
- [x] Add the student report with zero-entry and incomplete filters, class and name filters, and expandable details identifying the missing assessment and teacher.
- [x] Add the resume card and missing-only view. Resolve combined assessment IDs to the shared column and preserve the existing save and keypad flows.
- [x] Verify outcomes with focused LiveView tests, translations, and repository checks.

136 focused and regression tests passed. The 34-test marks suite also passed after adding coverage for the missing-only keypad. Format, Gettext, asset build and whitespace checks passed. `mix precommit` stopped on the existing Plug 1.20.3 advisory, so the full suite did not run through that command.
