# Bilan des absences — design

Date: 2026-11-23. Small change: one page and its print, on existing calculations.

## Why

The surveillant général sees absence totals only for the séquence of the day picked in a
class's « Cahier d'appel », and never for a trimester or the year (only the trimester
bulletin carries them). The user wants one view for three jobs: check the figures before
the bulletins print, spot students to warn or whose parents to call, and bring a sheet to
the class council.

## Decisions

- **Approach (user's choice, 2026-11-23):** one « Bilan des absences » page in the
  surveillant's « Vie scolaire » menu, right after « Absences », at `/school/absence-totals`.
  Rejected: a new class tab (school-wide spotting would need a second screen) and adding
  totals to the « Discipline » tab (one class only, and a sanctions page grows longer).
- **Pickers:** a period (séquence, trimester, « Année ») defaulting to the current séquence,
  and « Toutes les classes » or one class. Both live in the URL (`?period=seq:…&class=…&seuil=…`),
  so a link or a reload keeps them.
- **Figures:** exactly what the bulletin prints — `Attendance.bulletin_conduct/3` per class.
  A class counted from roll calls shows unjustified hours, justified hours and lates; a class
  whose hours are typed shows its typed unjustified hours only, tagged « saisi », and
  « non saisi » for a student with no figure yet. No new counting rule.
- **One class:** every student in roll order (as on the bulletin), the class's source named
  once above the table, students at or over the alert threshold marked.
- **All classes:** only students at or over the threshold, grouped by class in class order,
  most unjustified hours first, with « Aucun élève au-dessus du seuil » when none.
- **Threshold (user's choice, 2026-11-23):** typed on the page, in hours of unjustified
  absence. Pre-filled with 20 h per séquence: 20 h for a séquence, 20 h × its séquences for
  a trimester or the year (60 h for a three-séquence trimester). The surveillant may type
  another figure; it lives in the URL (`?seuil=`), so a link, a reload and the print keep
  it. It is a figure for this page only: the school's « seuil d'alerte » (Règles de vie
  scolaire, 10 h by default) keeps flagging students on the « Absences » page as today.
- **Print:** « Imprimer » opens an A4 print of what the screen shows (period, class choice,
  the threshold used), in the style of the other prints.
- **Links:** the class « Discipline » tab gets a « Bilan des absences » link with its class
  and period already picked.
- **Access:** conduct managers (head, censeur, surveillant: `Discipline.can_manage_conduct?`);
  the page and its print belong to the Discipline module, like « Heures d'absence ».

## Left to the builder

Layout and wording details; whether the print is a controller like the other prints (likely).

## Not changed

Counting rules, the typed-hours screen, the « Cahier d'appel » totals, the bulletin.
