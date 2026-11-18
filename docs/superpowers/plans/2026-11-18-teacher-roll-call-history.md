# Teacher Roll-call History Implementation Plan

**Goal:** Show saved course attendance by lesson and by student for a sequence, with dated assessment shortcuts.

**Architecture:** `TeacherAssistant.Academics.RollCallHistory` resolves the teacher's course from scoped assignments and builds the view from saved attendance entries, historical enrollment dates, and assessments. `School.RollCallHistoryLive` owns the filters and presentation. `School.CoursesLive` supplies the entry point.

**Tech stack:** Phoenix LiveView, Ash, PostgreSQL, Gettext, and Tailwind.

- [x] Add the scoped reader, aggregate by date and period, and count present, late, and absent marks per enrollment. Test partially saved sessions and tenant/teacher isolation.
- [x] Add `/school/courses/:id/roll-calls` with the attendance module gate, lesson and student filters, and assessment-date links. Expose it on each course row and verify the full navigation with LiveView tests.
- [x] Translate labels, check formatting and Gettext, and run focused attendance and course tests plus the repository's precommit checks.

73 focused and regression tests passed. Formatting, Gettext freshness, asset builds, and `git diff --check` passed. `mix precommit` stopped at an existing Plug 1.20.3 advisory before its full test step. Mobile browser verification is pending.
