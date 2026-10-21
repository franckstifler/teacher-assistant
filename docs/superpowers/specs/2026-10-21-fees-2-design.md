# Fees 2 — warnings, sending students home, return notes, « Renvoyé pour frais » (design)

Status: design, 2026-10-21. Builds on Fees 1 (`docs/superpowers/specs/2026-10-19-fees-1-design.md`, on main).

## Why

When parents fall behind, schools in Cameroon do two things: they send a **warning home with the student**, and
the bursar goes **class by class reading out who must leave** until a solution is found (a payment, or a promise
to pay by a date). Today the app knows who is behind (Fees 1 « En retard ») but gives the bursar nothing for
those rounds, nothing for the paper a returning student carries, and the teacher's roll call would count those
students as absent. The same forgery worry as receipts applies: a student can fake or alter a warning, or a
permission to come back.

## User decisions (2026-10-21)

1. **The bursar works class by class.** She stands in front of the class with a list and reads the names of the
   students who must leave and of those allowed to stay; the ones named leave on the spot. The class list mockup
   (« Contrôle des frais — 6e A ») was accepted as drawn: must-leave names with what they still owe, allowed-
   despite-late names with why, and a count of students up to date.
2. **A student comes back with a note from the bursar** (« Autorisation de retour en classe »). The note shows no
   amount, only the student, class, reason and how long it is valid. **Anyone can check it** (teacher, surveillant,
   bursar) — like a receipt, by QR code or number + code.
3. **Promises to pay are mostly spoken, sometimes with a date.** The bursar records the promise; its date is the
   note's validity.
4. **The bursar decides when warnings go out** (no automatic sending). The warning (« Avis de retard de paiement »)
   shows the overdue amount per fee, the total due today, a pay-by date and the bursar's name, and is **checkable**
   like a receipt. The mockup was accepted as drawn.
5. **Days sent home do not count as absences** (not on the record, not on the bulletin, not in conduct). The roll
   call shows « Renvoyé pour frais ».
6. **A send-out lasts for that day only.** If the student is still unpaid the next day, they are named again at
   the next round. (The user said this is a hard question with no settled answer; keep it simple and easy to
   change.)

Mockups: `.superpowers/brainstorm/*/content/fees2-class-list.html`, `fees2-note.html`, `fees2-warning.html`
(local, not committed). The note mockup still shows an amount; per decision 2 it must not.

## Goals

- The bursar prints or opens on her phone the list for one class, reads it, and records who actually left.
- Teachers' roll calls that day show those students as « Renvoyé pour frais », not absent.
- The bursar records a promise (with an optional date) or a permission, and prints a checkable return note.
- The bursar prints checkable warnings for chosen late students or a whole class.
- Head, vice principal and bursar can do all of it (Fees 1 `:fees` axis); teachers only see the roll-call mark.

## Non-goals

- Sending anyone home automatically, or blocking marks, report cards or anything else on unpaid fees.
- SMS. (A WhatsApp link to a guardian, as for receipts, is welcome but optional — builder's call.)
- Multi-day exclusions, a history of « how many times was X sent home » reports, letters for other reasons.
- Changing how Fees 1 computes « late » or the recovery figures.

## Anti-goals

- A teacher's roll call or the absence/conduct numbers counting fee send-outs as absences.
- A return note or warning that shows anything beyond what is printed on it on the public check page (no phone
  numbers, no other students, no browsing), or a note showing the amount owed.
- A note that silently stays valid after its date, or that can be edited after it is issued.

## Who must leave (the class list)

For one class and one day (default today):

- **Must leave**: every active student whose Fees 1 status is late on that day (owes more than what the tranches
  due by that day require) **and** has no valid return note on that day. Show what they still owe toward what is
  due today (the Fees 1 « reste » toward due-to-date, not the year total — builder: use whatever Fees 1 already
  computes for « late »; if it only has the year total, show that and say so).
- **Allowed despite late**: late students with a note valid that day, with the note's reason (« promesse jusqu'au
  31/10 », « exonération », « paiement reçu »).
- **Up to date**: just the count.
- No tranche due yet → everybody is up to date; the page says so.

The page is a screen that prints cleanly (A4 or A5 portrait, like the receipt print page). On the screen version
each must-leave name has a tick « Sorti » the bursar can set (and unset the same day) to record that the student
actually left; she can tick from her phone in the classroom or afterwards from the printed list. A « Tout cocher »
for the must-leave group is fine.

## Send-outs and the roll call

- A recorded send-out is (student enrollment, date, who recorded it, when). One per student per day at most.
  It can be undone the same day (a mistake, or the parent arrived with money) — builder: hard delete or a
  cancelled flag, either is fine since it has no paper trail.
- **Lifted by a note or payment the same day** (my call): issuing a return note valid that day, or recording a
  payment after which the student is no longer late, lifts that day's send-out exactly as an undo would — lessons
  whose roll call is not taken yet show the student normally; roll calls already taken are untouched.
- **Roll call.** For every lesson of that day whose roll call is taken **after** the send-out was recorded,
  the student shows as « Renvoyé pour frais », set already, and the teacher does not mark them. Lessons whose
  roll call was already taken before the send-out keep what the teacher recorded (my call: don't rewrite a
  teacher's record behind their back). If the send-out is undone, nothing already recorded changes; lessons not
  yet taken simply show the student normally again.
- Attendance stores this as its own status (my call: a new `AttendanceStatus` value, e.g. `:sent_home`, label
  « Renvoyé pour frais »). Every absence count, lateness count, conduct rule, school-life list, register and
  bulletin that today counts `:absent` must keep counting only `:absent` (they compare to `:absent` explicitly
  today; the builder must check each one, and the Attendance write path's `@valid_statuses`). The roll call
  screen shows the new status but a teacher cannot pick it by hand (only fee send-outs set it), and cannot change
  it to absent; they can change it to present if the student is actually in the room (my call — the student
  came back with a note or paid during the day).
- Builder's choice how the mark gets onto the roll call: pre-filled when the roll call screen loads, or written
  when the send-out is recorded for that day's lessons not yet taken. Either must give the same visible result.

## Return notes (« Autorisation de retour en classe »)

- Issued by the bursar (fees axis) from the student's fee card. Three reasons:
  - **Promesse de paiement** — with a date (required on the note: « valable jusqu'au »). Optional free note for
    what was promised (internal only, not printed — the note shows no amount).
  - **Paiement reçu** — offered after recording a payment while the student is still late or was sent home;
    valid until the next tranche due date (or the end of the school year if none), my call.
  - **Exonération / autorisation spéciale** — e.g. decided by the proviseur; valid until a date the bursar sets
    (default: end of the school year).
- Numbered per school per year like receipts but its own series (e.g. `A2026-000014`), never edited; it can be
  cancelled with a reason (like a receipt), after which it no longer counts and the check page says so.
- Printed: school, number, date issued, student, class, reason (without amount), valid until, the bursar's name,
  QR code and 6-character code (same scheme as receipts).
- A note counts for the class list from its issue date to its « valid until » date inclusive. After that date the
  student is simply late again (no automatic action).
- The student's fee card lists the notes (valid, expired, cancelled).

## Warnings (« Avis de retard de paiement »)

- From the class fees page: pick late students (default: all late students of the class) and a pay-by date
  (default: one week from today, my call), then print — one warning per page/half-page, in one print job.
- Also from the student's fee card for one student.
- Each warning is recorded and numbered (own series, e.g. `V2026-000031`) with the figures frozen at issue: per
  fee type the amount overdue toward what is due today, the total, the pay-by date, the issuer. Never edited;
  cancellable with a reason like the others.
- **Per-fee split of « overdue today »** (my call, following user decision 1 of Fees 1 that « Frais exigibles » is
  always paid first): the total due to date (Fees 1 `due_to_date`) is filled fee type by fee type **in payment
  order** (arrears line first when carried, then the regular types), each capped at that type's due after
  reductions; each row's overdue amount is that filled share minus what was paid on that type, never below zero.
  The rows add up to the total, and they match how a payment would be allocated. Types with nothing overdue are
  not printed.
- Printed text: « Aux parents de … — classe », the per-fee table, « Merci de régler cette somme avant le …
  Passé ce délai, l'élève pourra être renvoyé jusqu'au paiement. », the bursar's name, QR + code.
- The student's fee card lists warnings sent (number, date, amount, pay-by date).

## The check page

`/verify/receipt` (Fees 1) becomes the one place to check any fee paper: the number's prefix tells receipts,
notes and warnings apart; QR links go straight to the paper. It shows only what is printed on the paper, plus:

- For a note: « Valable aujourd'hui » or « Expirée depuis le … » or « Annulée ».
- For a warning: « Avis authentique » / « Annulé ».

Route names and whether to add `/verify/note` aliases are the builder's call; old receipt links must keep
working.

## Screens (summary)

- **Frais page** (`/school/fees`): each class row gets a way to open its « Contrôle des frais » list.
- **Class fees page**: a « Contrôle des frais » button (the list above) and an « Avis de retard » action.
- **Student fee card (drawer)**: « Autorisation de retour » (reason, date) → prints the note; after a payment, an
  offer to print a « Paiement reçu » note; lists of notes and warnings; « Avertir les parents » for one student.
- **Roll call**: the « Renvoyé pour frais » state (distinct colour, not error red).

## Constraints

Same as Fees 1: Ash resources with attribute multitenancy and composite FKs; migrations only with
`mix ash.codegen`; Ash enums (no bare atoms); gettext with French msgids, English translations, no fuzzy entries;
`frais` module gates the screens; fees axis for writes; `YearOpen` on year-bound writes; « today » is
`Reference.today/0`; tests on `MIX_TEST_PARTITION`; numbering under the same kind of lock as receipts.

## Tests (what must be proven)

- Class list: late without note → must leave; late with a valid note → allowed, with reason; note expired → must
  leave again; up-to-date students only counted; no tranche due → nobody listed.
- Send-out: recorded once per student per day, undo works, only fees axis can record it; a teacher cannot.
- Roll call after a send-out shows the student as sent home; a roll call taken before is untouched; the new status
  is not counted by any absence, conduct, register, school-life or bulletin figure (one test per counting place).
- Notes and warnings: numbering, frozen figures, cancel with reason, check page by QR and by number + code
  (case-insensitive like receipts), expired note shown as expired, nothing extra leaked.
- Tenancy isolation and closed-year refusal for the new resources, like the Fees 1 ones.

## Left to the builder

Resource names and shapes, the exact roll-call integration mechanism (within the rules above), print layout
details in the Tableau/receipt style, how many warnings per printed page, the colour of « Renvoyé pour frais »,
and whether the class list and the warnings print from controllers (like the receipt) or LiveViews.
