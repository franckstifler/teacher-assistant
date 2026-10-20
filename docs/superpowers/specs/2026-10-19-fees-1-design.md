# Fees 1 — fee types, tranches, payments with checkable receipts (design)

Status: implemented 2026-10-20 (branch `fees-1`, plan `docs/superpowers/plans/2026-10-20-fees-1.md`); no visual check done. Part 2 (« Fees 2 ») is outlined at the end and specced later.

## Why

Fees are the bursar's daily work and the school's money. The P2.10 fees page exists but is hidden (only
`/school/classes/:id/fees`, linked from nowhere), knows a single undivided amount per class, and gives the parent
nothing. Schools charge several fees with their own names (« Frais exigibles », « PTA », « Frais informatique »…),
parents pay in advances, and every payment must give the parent a receipt. A receipt carried home by a student can
be forged or altered (a student keeps part of the money): the user's explicit concern. Fees 1 makes the fee
module usable day to day and makes every receipt checkable against the school's records.

## User decisions (2026-10-19)

1. **Fee types are per school**, named by the school, with a **payment order**. « Frais exigibles » (or whatever
   the school puts first) is always paid first: a payment fills the first fee type before anything goes to the
   next.
2. **Partial payments (advances) are normal**: any amount, any day; the balance is always shown.
3. **Deadlines are school-wide tranches** covering all fees together (« 1re tranche avant le 15 octobre »), not
   one schedule per fee type.
4. **Every payment gives a receipt.** It is printable and, when a guardian has a phone number, can be sent to the
   parent with WhatsApp.
5. **Receipts are checkable**: a number and a QR code lead to a public page showing what the school recorded;
   every receipt also shows the total paid so far and the balance. Real SMS stays out (deferred in the docs).
6. **Last year's unpaid fees** carry over **only when the school decides**: « Reporter les reliquats de l'année
   précédente » lists the students who still owe and their amounts, the bursar can untick any, and confirming
   adds a « Reliquat année précédente » line paid first. A school that does not collect old debts never presses
   it; a single student's reliquat can later be forgiven with a reduction and a reason. Last year's records keep
   the real unpaid amounts. Payments are recorded in the open year only, so cash stays in one year.
7. **Fees 2** (warning letters, sending students home for fees, promises to pay, « Renvoyé pour frais » in roll
   call) is a separate later part.

## Goals

- The bursar sets the year's fee types, each class's amounts, and the tranches; records payments; prints or sends
  receipts; sees who is behind and the recovery figures.
- A parent (or anyone holding the receipt) can check it on their phone.
- The Proviseur and Censeur see the same numbers (fees axis: head, vice principal, bursar).

## Non-goals (Fees 1)

Warning letters, exclusion, promises to pay (Fees 2); SMS; online/mobile-money payment collection (the bursar
records a payment made elsewhere, with its reference); exam fees handled by the exam offices; accounting
(expenses, cash book); refunds (a cancelled receipt is the only correction).

## Anti-goals

- A receipt that can be edited after it is issued, or whose split changes when amounts change later.
- A check page that leaks anything beyond the receipt (no phone numbers, no other students, no browsing).
- Blocking anything (marks, report cards, roll call) on unpaid fees in Fees 1.

## Constraints

- Ash resources with attribute multitenancy, composite FKs like the rest; migrations only with
  `mix ash.codegen`; no bare `:atom` attributes (Ash enums); strings through gettext (French msgids, English
  translations, no fuzzy entries left).
- Writes on the fees axis (`SchoolRole.axis(:fees)`: head, vice principal, bursar); the `frais` module gates the
  screens as today.
- Amounts are integer FCFA (as today); dates are `Date`s; « today » is `Reference.today/0`.
- The QR check follows the report-card one (`BulletinVerification`, spec I5): HMAC token from
  `secret_key_base`, public controller route under `/verify/…`, `EQRCode` SVG.

## Data

1. **`FeeType`** (per school, per academic year): `academic_year_id`, `name` (non-empty, unique per year,
   case-insensitive), `position` (the payment order, 1 = paid first), `active?`. A new year starts with no
   types; « Copier les frais de l'année précédente » copies types, class amounts and tranches (dates shifted one
   year). A last-year class matches a this-year class by the same label, else by the same level and série; classes
   left without a match keep no amounts and are listed after the copy (« À compléter : … »). *(builder's call)* A school with no type yet is offered one click « Créer Frais exigibles et PTA ».
2. **`ClassFee`**: `class_group_id`, `fee_type_id`, `amount` (integer ≥ 0). No row (or 0) = that class does not
   pay that fee (e.g. computer fees only in some classes). Unique on (class, fee type).
3. **`FeeTranche` becomes school-wide**: `academic_year_id`, `label`, `due_date`, `position`, `percent` (1..100,
   cumulative: the share of the student's total due that must be paid by `due_date`; the last tranche is 100).
   Percent works for every class whatever its amounts. Existing class tranches (P2.10) are replaced: the module
   was hidden, so no school relies on them; the migration drops them (see Migration).
4. **`FeeAdjustment`** (exists, per enrollment) gains `fee_type_id`: a reduction or waiver now applies to one
   fee type (« exonéré de PTA », « enfant du personnel : 25 000 de réduction sur les frais exigibles »). One per
   (enrollment, fee type), a **fixed amount** (no percentage), ≤ that type's amount for the class. *(builder's
   call)*
5. **`Payment`** (exists) gains:
   - `number`: receipt number, unique per school, `R<year>-<6 digits>` (e.g. `R2026-000123`), year = the
     academic year's start year, sequential per school per academic year, assigned at creation, never reused;
   - `status`: Ash enum `:valid | :cancelled`, with `cancelled_at`, `cancelled_by_user_id`,
     `cancel_reason` (required when cancelling).
   - frozen figures, filled at creation: `paid_to_date` and `left_after` (the student's total paid this year and
     balance left, counting this payment), so the receipt, its reprints and the check page always show what the
     parent was given. *(builder's call, from the anti-goal)*
   A payment is **never updated or deleted** after creation (its amount, date and split are what the receipt
   says); a mistake is fixed by cancelling it and recording a new one. The `update` and `destroy` actions go.
6. **`PaymentAllocation`**: `payment_id`, `fee_type_id`, `amount` (> 0), plus the frozen `paid_to_date` and
   `left_after` for that type. Written once, at payment time, by the
   allocation rule; the receipt and every balance read it. Sum of a payment's allocations = its amount.
7. **Arrears.** `FeeType.kind`: Ash enum `:regular | :arrears`. The carry-over action creates (once per year) the
   type « Reliquat année précédente » of kind `:arrears` at position 0 (always paid first, cannot be reordered,
   renamed or given class amounts), and one **`StudentArrear`** per kept student: `enrollment_id` (this year's
   enrollment of the same student), `from_academic_year_id`, `amount` (> 0, the student's `left` at the end of
   that year, never more). A student with no enrollment this year cannot be carried (listed as « non réinscrit »).
   Running the action again only offers students not carried yet.
8. **Closed years.** `Payment`, `PaymentAllocation`, `ClassFee`, `FeeType`, `FeeTranche`, `FeeAdjustment` and
   `StudentArrear` get the `YearOpen` validation like the other year-bound resources: nothing is recorded or
   cancelled in a closed year.
9. Migrations with `mix ash.codegen`.

## Rules

10. **A student's due per fee type** = `ClassFee.amount` for their class (for the arrears type: their
   `StudentArrear` amounts) − their adjustment for that type (≥ 0).
   **Total due** = sum over active types. A fee type can be **deactivated only while no class amount > 0 and no
   payment uses it this year** (otherwise set its amounts to 0 first); so allocations never point to an inactive
   type. *(builder's call)* Every enrollment of the year counts (there is no withdrawn status yet). *(builder's
   call)*
11. **Allocation** (at payment time): walk the active fee types in `position` order; give each the smallest of
   (what is left of the payment, that type's due − what valid allocations already cover). Money left after the
   last type (an overpayment) goes to the **last** type and shows as « Trop-perçu » in the balance (negative
   balance); it is never refused, as a parent may pay ahead.
12. **Cancelling** a payment marks it cancelled; its allocations stop counting; later payments are **not**
    re-split (their receipts are already issued). Balances read valid allocations only.
13. **Balance** per student: per type (due, paid, left) and in total; **due to date** = total due × the percent of
    the latest tranche whose `due_date` ≤ today (0 before the first). **Status**: paid up (left ≤ 0), on track
    (paid ≥ due to date), behind (otherwise). `FeeBalance.compute` is reworked for this (stays pure).
14. **Recovery figures** (« Recouvrement »), for the school and per class: total expected for the year, expected to
    date, collected (valid payments), rate collected / expected (%), rate to date, number of students behind.
15. Changing a class amount or an adjustment after payments exist is allowed; it changes dues and balances, not
    past allocations or receipts.

## Receipts

16. **Content** (printable, A5 portrait, also fine on a phone): the school's official header (KLM header);
    « Reçu n° R2026-000123 »; date, method (cash / mobile money / bank transfer / other) and reference; student
    full name, matricule (when set), class; amount in figures **and in words** (French); the split by fee type;
    **total paid this year** and **balance left** after this payment, per type and total; the bursar's name;
    the QR code and the check URL with the number; « Reçu annulé » in large letters when cancelled.
17. **Check page** `/verify/receipt/:token` (public, no sign-in): school name, receipt number, date, amount,
    student name and class, the split, the frozen total paid and balance **as of that receipt**, and its status
    (valid / annulé). Nothing else. An unknown or forged token shows « Reçu introuvable ». The token is
    `BulletinVerification`-style: `{workspace_id, payment_id}` + HMAC tag, base64url.
18. **Typing the number** also works: the check page has a field « Numéro du reçu » + « Code » (the last 6
    characters of the token, printed under the QR) so someone without a camera can check by typing; both must
    match.
19. **WhatsApp**: on the payment's receipt view, one « Envoyer par WhatsApp » button per guardian with a phone
    (Cameroon numbers normalised to `237…` with the existing `Accounts.Phone`), opening
    `https://wa.me/<number>?text=<message>`; the message (French): school short name, student, amount, date,
    receipt number, balance left, check link. Nothing is sent by the server.

## Screens

20. **Bursar space** (`Spaces.space(:intendant)`) becomes: « Frais » (new school page), « Classes »,
    « Paramètres des frais ». The Proviseur and Censeur get « Frais » in their « Établissement » section. All
    gated by the `frais` module.
21. **« Frais »** (`/school/fees`, fees axis): recovery figures for the school (rule 14) with a per-class table
    (class, students, expected, collected, %, behind; sorted by class order, click → class page); a search box
    (name or matricule) that jumps to a student's fee card; « Derniers paiements » (last 20 receipts, with links).
22. **Class page** (`/school/classes/:id/fees`, existing route, reworked): the class's amounts per fee type (read
    here, edited in settings), then the roster: per student total due, paid, left, status (paid up / on track /
    behind, coloured), « Encaisser » button. A filter « En retard seulement ».
23. **Student fee card** (a drawer or panel on the class page, also reached from the search): per type due /
    paid / left, adjustments (add / remove, with reason), the payments list (number, date, amount, status) with
    « Reçu » (print view) and « Annuler » (asks the reason), and the payment form: amount, date (default today),
    method, reference (required for mobile money and bank transfer). Saving shows the receipt right away (print
    and WhatsApp buttons).
24. **Receipt print view** (`/school/fees/receipts/:id/print`, fees axis, controller like the report-card print).
25. **« Paramètres des frais »** (`/school/settings/fees`, fees axis): the active year's fee types (add, rename,
    reorder = payment order, deactivate), a grid classes × fee types of amounts (with « Même montant pour tout le
    niveau » per cell), the tranches (label, due date, cumulative %), « Copier l'année précédente », and
    « Reporter les reliquats de l'année précédente » (decision 6): a list of students still owing in the last
    closed year with their amount, each ticked by default, « non réinscrit » ones shown greyed; « Reporter »
    creates the arrears. Linked from the Settings hub too.
26. Strings FR (msgids) and EN.

## Migration of existing data

27. The fees module was hidden, so existing `fee_tranches` (per class) are dropped. Existing `payments` and
    `fee_adjustments`, if any, are kept: each school with payments gets one fee type « Frais exigibles »
    (position 1), every class gets a `ClassFee` equal to the sum of its old tranches, every old payment gets a
    receipt number (in `paid_on` then `inserted_at` order) and one allocation to that type, and every old
    adjustment points to that type. Done in the migration's data step (or a one-off task run by the migration);
    the plan decides which, with a test on a small fixture.

## Tests (what must be proven)

28. Allocation: priority order, partial, exact, overpayment to last type, adjustments, inactive types skipped,
    cancelled payments ignored, no re-split after a cancellation.
29. Balance, due to date with cumulative percents, status, recovery figures (school and class).
30. Receipt numbers: sequential per school and year, unique under concurrent payments (a DB unique index plus a
    counter row or `SELECT … FOR UPDATE`; the plan picks one and tests two parallel inserts).
31. Arrears: carry-over creates the type at position 0 and one `StudentArrear` per ticked student with the
    exact left amount; unticked and non-re-enrolled students get none; running it twice adds nothing twice; the
    arrears line is paid first; a reduction on it forgives it; nothing is written in a closed year.
32. Payments cannot be updated or deleted; cancel needs a reason and the fees axis.
33. Check page: valid, cancelled, forged token, wrong number/code pair, other school's payment (token from school A
    never shows school B data), and that it shows no phone number.
34. Policies: a teacher (non-fees member) cannot see or record; a form master keeps read access to their class
    (as today); the public check page needs no sign-in.
35. LiveViews: settings (types, grid, tranches, copy year), class page, student card (record → receipt shown,
    cancel), school « Frais » page, menus per role, module gating.

## Left to the builder

Layout details within the existing design system (Tableau theme, daisyUI), the exact receipt number counter
mechanism (rule 30), amount-in-words implementation (French, integers up to billions), the drawer vs panel choice
for the student card, and how many recent payments to show.

## Fees 2 (outline, specced later)

Warning letters per student after a tranche deadline (list of students behind, print one letter each); sending a
student home for fees (bursar or head, never automatic) and lifting it on payment or on a promise to pay
(« engagement », with a date); during an exclusion the roll call pre-fills « Renvoyé pour frais » for every
lesson, not counted as an unjustified absence nor in conduct; a passed promise date puts the student back in the
« behind » list.
