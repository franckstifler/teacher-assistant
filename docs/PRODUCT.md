# Teacher Assistant Product Definition

## Product Summary

Teacher Assistant is a Phoenix/Ash school operations and teacher productivity application built for Cameroon secondary education. It supports both schools and independent teachers:

- Schools use it to manage academic years, classes, subjects, marks, attendance, report cards, student classroom access, programme coverage, and staff workflows.
- Teachers use it to manage pedagogic activities, progression plans, APC lesson structures, teaching logs, attendance, and marks, even when they are not attached to a school.

The product must reflect real Cameroon school operations: academic years, terms, sequences, fiches de progression, APC lesson planning, report-card calculations, programme coverage rates, and role-based administration.

## Target Users

- Teacher: enters marks, tracks attendance, follows weekly progression, logs taught content, and prepares APC lesson structures.
- Independent teacher: uses a personal workspace for pedagogic planning, private learner tracking, attendance, and marks without official school administration.
- Admin/principal: configures school data, academic years, classes, students, subjects, staff, report settings, and role access.
- Vice principal: monitors programme coverage, teacher progression, and academic reporting.
- Accountant/admin: manages classroom access statuses for students.
- Discipline or school operations staff: may use attendance and classroom access views when enabled by school policy.

## Core Product Model

The app is organized around workspaces.

- Personal teacher workspace: automatically available to each teacher; private to the user; supports pedagogic work, private marks, and private attendance.
- School workspace: represents one school or organization; users enter by invitation or membership; all school-owned records are tenant scoped.
- A user can belong to many school workspaces and keep a personal workspace.
- The selected workspace determines tenant, role, navigation, permissions, and academic-year context.

No workflow should assume a selected school or an existing academic year. When setup is missing, the user gets a guided setup or empty state instead of a crash.

## Core Features

### Authentication and Workspace Selection

- Password login.
- Workspace selection after login when no workspace is selected.
- Personal workspace creation for users without school membership.
- Per-workspace role resolution instead of global role authorization.
- School invitation by email with role assignment and acceptance flow.

### Academic Setup

- Academic years with start/end dates.
- Terms and sequences.
- Classes/classrooms tied to an academic year.
- Levels, options, subjects, coefficients, and teacher assignments.
- Guided academic-year setup when required data is missing.

### Marks

- Teacher-filtered class and subject selection.
- Mark entry and update with 0-20 validation.
- Missing mark visibility.
- Deterministic data foundation for report cards.

### Attendance

- Teacher-accessible attendance entry for assigned classes.
- Present, absent, excused, and comment flows.
- Duplicate-safe create/update behavior.
- Attendance summaries for reports.

### Report Cards

- Deterministic calculations first: subject averages, coefficients, term averages, yearly averages, ranking, attendance counts, and appreciations.
- Printable/exportable previews can be added after calculation correctness is stable.
- AI remarks are optional editable suggestions, never authoritative calculations.

### Fiche de Progression and Programme Coverage

- Progression plans model planned weekly teaching content.
- Progression entries include term, sequence, date range, content, planned hours, and entry type.
- Entry types include lesson, integration, evaluation, correction, remediation, and holiday.
- Teaching logs record actual taught entries and hours.
- Programme coverage computes term and yearly taux de couverture du programme.
- Dashboards support teachers, admins, and vice principals.

### APC Lesson Structure

APC lesson structures should be editable teacher workspaces generated from a progression entry. Fields include:

- Competence.
- Prerequisites.
- Situation-problem.
- Teacher and learner activities.
- Resources.
- Evaluation.
- Remediation.
- Timing.

The app should not generate full lesson content by default in v1; it should generate or scaffold structure for teacher approval.

### Student Classroom Access

- Enrollment access statuses: allowed, pending, suspended, blocked.
- Manual status in v1, not fee-balance automation.
- Reason, set-by, and set-at audit fields.
- Visible flags in attendance and classroom views.

## Policy Model

- Admin/principal: manage school configuration, users, classes, subjects, report-card settings, academic years, and invitations.
- Accountant/admin/principal: manage student classroom access statuses.
- Teacher: use assigned classes and subjects; enter marks, attendance, teaching logs, and APC lesson structures.
- Vice principal/admin/principal: view coverage dashboards and academic reports.
- Personal teacher workspace: teacher-only private scope; no official school report cards or student fee/access administration.

## Roadmap

### Current Foundation

- Hybrid workspace model.
- Personal and school workspace support.
- Academic-year setup gate.
- Marks, attendance, report-card preview, grade intervals, progression workspace, programme coverage, student access, and invitation basics.

### Next Product Priorities

- Formalize personal learner groups for independent teachers.
- Add invitation acceptance UI from email/token links.
- Improve missing-setup empty states in every teacher workflow.
- Complete printable report-card export.
- Add reviewed PDF import for fiches de progression.
- Add APC structure templates by subject, level, and subsystem.
- Add richer coverage dashboards by teacher, subject, class, term, and year.

## Product Quality Bar

- No tenant fallback through arbitrary first records.
- No route should crash because academic year, class, subject, or assignment data is missing.
- School-owned data must remain tenant isolated.
- User permissions must derive from selected workspace role.
- Deterministic calculations must be correct before AI suggestions are introduced.
- All user-facing flows need stable DOM IDs for LiveView tests.
