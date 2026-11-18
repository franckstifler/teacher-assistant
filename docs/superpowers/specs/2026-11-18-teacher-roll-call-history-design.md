# Teacher roll-call history

Add **Historique des appels** to each teaching unit in **Mes cours**. Teachers can consult saved records for the selected course in the current school and academic year. Resolve the requested unit through the teacher's authorized teaching assignments on the server. Apply the attendance module gate and keep the history read-only.

## Sequence and attendance count

Use the selected sequence's configured start and end dates, inclusive. Default to the active sequence when there is one. Otherwise provide a sequence selector with the most recent sequence containing saved roll calls selected when available. A sequence with no records shows an empty state.

In **Par élève**, display a count such as **4/6 présents**, with the breakdown available beside it or on tap:

- The numerator includes present and late marks. Show late arrivals separately within that total.
- The denominator includes saved present, late and absent marks for that student in the selected course and sequence. A justified absence still counts as an absence and is identified separately.
- Unmarked students, dates without any saved roll call, and lessons before a student joined or after they left contribute nothing to the ratio. Show unmarked entries separately when a saved roll call exists for the student's class and the student was on its roster on that date. Show a dash with a no-records message when the denominator is zero.
- The existing sent-home status is displayed separately and excluded from the numerator and denominator.
- The unit is a recorded lesson period. Two periods saved together count as two periods, which matches the stored attendance data. For combined courses, a shared period is displayed once with class groups, and each student contributes at most one mark to their own count for that period.

Aggregate across the whole sequence. Show dates grouped by week in the lesson history so teachers can see how coverage varies as the sequence progresses. Use the date of the saved roll call even if the lesson was moved or the timetable changed later.

## Lesson and assessment views

In **Par séance**, list saved roll calls newest first and show the date, period, class groups, and counts. Open a roll call to view the recorded students and their statuses. Include app and paper records when the stored teaching context links them to this course. A paper entry without a course link is never attributed using today's timetable. Expand a student in **Par élève** to inspect the underlying dates and statuses.

For assessments with a recorded date, provide a link to the course's saved roll calls for that date. Show all matching periods when there are several and an empty state when there are none. Assessment attendance and marks retain their existing workflows and permissions.

## Verification

Test inclusive sequence boundaries, partially recorded roll calls, justified absences, late and sent-home marks, roster changes, all-zero data, app and paper records, combined courses, multiple periods saved together, timetable changes, other teacher and school isolation, and dates with zero or multiple assessment roll calls. Verify mobile presentation and French and English labels.
