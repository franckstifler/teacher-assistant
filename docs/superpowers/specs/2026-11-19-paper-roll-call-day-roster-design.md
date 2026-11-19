# Paper roll call: each lesson against that day's class — design

Date: 2026-11-19. Amends the paper roll call (spec 2026-10-28).

## Why

A weekly sheet typed in after its week was saved against the class list of the day it
was typed (`PaperWeek.read` used today's roster). A student who left mid-week got no
mark for the days they still attended; a student added mid-week got « présent » for
days before they joined. The teacher roll-call history (2026-11-19) relies on every
saved roll call marking exactly the class of that day, so these gaps became invisible.

## Decisions

- **The week's students** are everyone in the class at some point of the week: on the
  class list (`left_on` empty or after Monday) and added to Scolaka on or before
  Saturday. Each row carries `joined_on` (the day the enrollment was created, when it
  falls after Monday) and `left_on` (when it falls in the week).
- **In class on a day** = added on or before that day, and not yet left (`left_on`
  after that day), the same rule as the class list on a date.
- **Departure** (settled): the student stays on that week's sheet; their days before
  `left_on` are typed and saved as usual; cells from `left_on` on are greyed
  « Parti(e) le … » and save nothing.
- **Arrival** (the user's choice, 2026-11-19): cells before the day they were added are
  greyed « pas encore inscrit(e) » and save nothing, as an app roll call those days
  would have done. Accepted risk: a student attending before being entered in Scolaka
  loses those days.
- **The class's first entry** (the user's choice after the browser check, 2026-11-19):
  students entered on the class's first day in Scolaka (its setup or import, often
  weeks into the year) count from the year's start, so a school that joins mid-year
  keeps full sheets for its earlier weeks. Only students entered after that day are
  treated as arriving mid-year.
- **Saving** a ticked column writes marks only for students in class on that lesson's
  day; a crafted cycle on a greyed cell is ignored.
- **Printed sheet**: rows as above; greyed cells for days a student is not in class.

## Approaches

1. Week roster with per-day presence (chosen): one student list, a day rule.
2. One roster per day: rows would change from day to day, which a printed grid cannot show.

## Not changed

Transfers between classes keep their known limit (an enrollment's class change has no
date). The history's moduledoc gap note is removed.
