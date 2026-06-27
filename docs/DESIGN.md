# Teacher Assistant Design System and UX Direction

## Design Summary

Teacher Assistant should feel like a professional school operations system: calm, dense, readable, and efficient. It is not a marketing dashboard once the user is inside the app. The interface should help users complete repeated administrative and teaching tasks quickly, with clear state, predictable navigation, and minimal visual noise.

The landing page can introduce and sell the project, but authenticated screens should prioritize work: tables, filters, forms, tabs, compact summaries, and strong empty states.

## Platform Constraints (set 2026-06-26)

- **Mobile-first.** Design every authenticated flow for a phone first; most Cameroon teachers work
  from smartphones. Dense desktop layouts are an enhancement of the mobile flow, not the baseline.
  Where this doc says "table," on mobile prefer stacked rows / cards that collapse gracefully.
- **Intermittent connectivity.** Keep interactions quick and forgiving: short forms, preserved
  state on validation error, no multi-step actions that lose work if a request drops. (True
  offline-first sync is a later phase, not v1.)
- **Bilingual FR + EN.** Every UI string and data label exists in both languages; locale is a user
  setting and switchable. Teacher-entered content stays in the teacher's chosen language. Use the
  FR↔EN terms in [`docs/domain/glossary-fr-en.md`](domain/glossary-fr-en.md).
- **Phased UI.** v1 is the independent-teacher experience only; school-workspace navigation and
  admin surfaces arrive in Phase 2 (see [`PRODUCT.md`](PRODUCT.md)). Don't surface school-only
  actions before that layer exists.

## Visual Principles

- Use a restrained operational style, not decorative card-heavy layouts.
- Keep typography compact and clear, especially in dashboards and forms.
- Use full-width sections and panels for workflows; avoid cards inside cards.
- Prefer tables for lists that users scan, compare, or act on repeatedly.
- Use compact KPI blocks for operational summaries.
- Make empty states specific and actionable.
- Keep button labels short and pair icons with clear commands where useful.
- Use subtle transitions and hover states; avoid distracting animation.

## Navigation Model

The app shell is role and workspace aware.

- Top bar: product name, current workspace, workspace switcher, current user, role, theme toggle, sign out.
- Sidebar: workflow groups based on selected workspace and role.
- Personal workspace navigation: teacher tools only.
- School workspace navigation: teacher tools, reports, access control, and configuration based on role.

Navigation should never show actions the user cannot take in the selected workspace.

## Screen Patterns

### List Screens

- Start with a compact title block: section label, heading, one-line purpose.
- Use filters above tables when the list can grow.
- Use a table with stable row IDs.
- Keep row actions right aligned.
- Use badges for statuses.
- Provide a useful empty row with the next action.

### Forms

- Use `<.form>` and `<.input>` from Phoenix components.
- Every form must have a stable DOM ID.
- Group related fields with grid layouts.
- Use short labels and avoid explanatory walls of text.
- Submit buttons should include an icon when the action is significant.
- Validation errors should appear near the field and preserve user input.

### Setup Gates

Setup screens should replace crashes and unclear redirects.

- Explain the missing prerequisite in one sentence.
- Provide one primary action.
- Keep setup forms short.
- Return the user to the workflow they were trying to use when feasible.

### Dashboards

- Use dashboards for monitoring, not decoration.
- Put KPIs above detailed tables only when they summarize the same data.
- Keep charts optional until the tabular data is reliable.
- Coverage dashboards should support filtering by academic year, term, class, subject, and teacher.

### Report Cards

- Treat report-card views as verification tools before export.
- Show deterministic values clearly: rank, average, coefficient, missing marks, absences, and appreciation.
- Do not hide missing marks.
- Printable/export views should come after calculation correctness and test coverage.

## Component Conventions

- Use Tailwind CSS and DaisyUI.
- Keep the Phoenix v1.8 layout wrapper: `<Layouts.app flash={@flash} current_scope={@current_scope}>`.
- Use `<.icon>` for icons.
- Do not use inline scripts in templates.
- Maintain Tailwind v4 import syntax in `assets/css/app.css`.
- Do not use `@apply` in raw CSS.
- Add stable DOM IDs for key forms, filters, buttons, tables, rows, report sections, and setup gates.

## Color and Density

- Use a calm neutral base with clear semantic accents.
- Avoid one-note palettes dominated by one hue.
- Avoid oversized hero-scale headings inside app panels.
- Keep cards/panels at 8px radius or less unless the existing system changes globally.
- Prioritize spacing that supports scanning rather than large decorative gaps.

## Interaction Details

- Use selects for bounded choices such as role, status, term, sequence, class, subject, and academic year.
- Use date inputs for dates.
- Use segmented controls or tabs for modes.
- Use badges for statuses like allowed, pending, suspended, blocked, active, draft, and pending invitation.
- Use loading states on long-running actions.
- Preserve form state after validation errors.
- Use LiveView tests against stable IDs, not raw HTML strings.

## Workspace-Specific UX

### Personal Teacher Workspace

The personal workspace should feel private and pedagogic.

- Show teacher tools only.
- Use copy such as "Private pedagogic tools, attendance, and marks."
- Do not show official school report cards, student access controls, or school configuration.
- Missing academic year should route to the guided setup gate.

### School Workspace

The school workspace should feel administrative and collaborative.

- Show role-specific navigation.
- Use school name prominently in the app shell.
- Keep tenant boundaries visible through the workspace switcher.
- School-only pages should redirect personal users back to workspace selection with a clear message.

## Content Guidelines

- Use Cameroon school vocabulary where appropriate: academic year, term, sequence, fiche de progression, APC, programme coverage, report card, classroom access.
- Prefer clear operational labels over generic SaaS wording.
- Keep help text short and tied to the task.
- Do not use in-app text to describe obvious UI mechanics.

## Accessibility and Testability

- Use semantic headings in order.
- Keep tables readable with header cells.
- Ensure buttons and links have clear accessible names.
- Use visible focus styles from DaisyUI/Tailwind.
- Do not rely on color alone for statuses.
- Every critical workflow should be testable with LiveView selectors.

## Design Quality Bar

- Authenticated screens should work at desktop and mobile widths without overlapping text.
- Important text must fit inside buttons and controls.
- Empty states must be helpful, not dead ends.
- No UI should imply access to workflows unavailable in the selected workspace.
- No feature should depend on hidden debug output or browser console behavior.
