# Teacher profile from Members

## Approved direction

Clicking a teacher in Members opens an expanded drawer with Overview, Timetable and Settings tabs. Overview is selected initially. This makes teaching information the main purpose of the drawer while retaining existing member administration.

## Scope and interaction

Keep the members list, search, filters, selection and add-member workflow unchanged. Keep the existing permission gate for opening member details (staff management or service management). Opening another member resets the active tab and removes the previous member's data. Closing the drawer clears its profile state.

Show the member name and contact details in the drawer header. Display the selected academic year near teaching information. Use the existing translated French interface conventions and Gettext for new strings.

Overview shows:

- Roles and employment status.
- Assigned subjects and their classes, with weekly assigned hours. Combined courses show their constituent classes together and count once toward workload.
- Total assigned weekly hours versus expected service, including an excess-hours indicator where expected service is known. Label these as assigned hours, not actual hours taught or scheduled hours.
- Form-master responsibilities for classes in the selected school and academic year, including classes for which the teacher has no subject assignment.
- Links to class overview pages and, when the viewer has the required permission, the existing assignment editor.

Timetable shows the teacher's recurring weekly schedule, including lesson times, subject, classes and room where available. Use a week grid on wider screens and a day selector with lesson cards on phones. Respect the school's configured lesson days and periods. Group simultaneous entries belonging to one combined course; preserve distinct overlapping lessons so real conflicts remain visible. An explicit empty state distinguishes no timetable from a failed load. This is the recurring timetable, not a dated attendance or substitution report.

Settings contains the existing name, role, employment-status and weekly-service form, account state, password-reset and deactivation actions. Preserve existing authorization and confirmations. Only show the Save action for Settings. Switching tabs must preserve unsaved settings values by keeping the form mounted and hiding its panel; closing or changing member retains the existing discard behavior. Non-teaching members retain access to settings and identity details, with teaching tabs shown when the member has the teacher role or teaching/form-master data.

## Architecture and data flow

MembersLive remains responsible for selection, tab state and existing member mutations. Extract profile rendering into a focused component module rather than growing MembersComponents with a full timetable implementation. Keep the existing settings form reusable through MembersComponents.

A focused profile reader assembles the selected member's teaching data. Reuse Curriculum.list_units_for_user/3, Timetabling.teacher_timetable/2 and Timetabling.teacher_service/2 where appropriate. Fetch form-master classes, periods and calendar through existing scope-aware domain reads. Do not impersonate the selected teacher or substitute that teacher for the viewing actor. All reads use the current viewer's scope and selected academic year.

Load profile data only for the selected member, not every row in Members. The event handler resolves the member from the authorized members list; arbitrary client-supplied user identifiers cannot select another school's teacher. Handle expected authorization and data-loading failures without crashing the LiveView. Keep account settings usable if academic data cannot load, and provide a retry action for the academic content. A missing academic year produces an explicit year-selection message and no academic reads.

Tab selection accepts a fixed allowlist. Use accessible tab and panel associations, selected states and keyboard navigation. Preserve drawer focus, close behavior and responsive layout. Keep shared drawer defaults unchanged for unrelated screens.

## Boundaries

No schema changes are expected. No new assignment editor, timetable editor, individual print endpoint, attendance analytics or teacher performance scoring is included. Existing class and assignment pages remain the editing destinations. No expansion of who may view or change member records is included.

## Verification

Add focused LiveView and reader tests for:

- Opening a teacher on Overview and switching between tabs.
- Correct subject/class assignments and independent form-master responsibilities.
- Weekly service totals and combined-course deduplication.
- Timetable times, rooms, combined lessons and genuine overlapping lessons.
- School and academic-year isolation, rejected unknown member IDs and unauthorized viewers.
- No year, no assignments, no timetable and recoverable loading failures.
- Switching teachers and reopening the drawer without stale data.
- Preserved settings values across tab changes and existing save/reset/deactivation behavior.
- Non-teaching members retaining existing administration.

Run the relevant member/profile/timetable tests and the repository-required mix precommit check. Inspect desktop and mobile layouts in a running app when a usable local session is available; report any verification that cannot be performed.

## Review

The design has been checked for incomplete requirements, scope conflicts and ambiguous workload semantics. The next step is the implementation plan after written-spec review, as required by the brainstorming workflow.

## Approved additions (2026-11-17)

The user approved three quick wins: expected versus assigned versus scheduled weekly service, contact call/copy shortcuts, and an individual teacher timetable print. This supersedes the earlier exclusion of an individual print endpoint. Scheduled hours follow the existing editor's school-period convention, with one combined lesson counted once. Show unplaced periods per assignment so overscheduling another subject cannot cancel a gap. Printing uses the existing teacher print layout and school module gate. The broader attention dashboard remains deferred.
