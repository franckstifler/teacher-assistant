# Exam photos export — design

Date: 2026-10-29 · Status: draft for approval

## Why

For the national exams (Probatoire and Baccalauréat, technical series), the exam
directorate requires each candidate's photo in a fixed format: the date at the top, the
photo, then the candidate's name and two codes under it, all in bold blue on white. The
school sends these pictures to a colleague who uploads them to the exam platform.

The user's school has about 100 candidates (all its 1ère and Terminale students) and
needs the pictures **next week**. Doing it by hand is too slow; the photos will already
be in the app (taken with the class séance or from the student page), so the app should
produce the exam pictures itself and hand the user a zip to share.

Reference picture (supplied by the user, kept in the conversation): about 633×1080 px,
white band with « 23/11/2025 » on top, the photo, white band with
« BIYONG NDJENG EMMANUEL P. » and, on a second, larger line, « PBF3  CR  8127 ».

## Decisions taken with the user

- **New files only.** The export reads the student's stored photo and draws a new
  picture. The stored photo, `photo_path` and `photo_taken_at` are never changed.
- **Layout copies the reference picture**: white top band with the date, the photo
  unchanged in the middle, white bottom band with the name in capitals on one line and
  « <exam code>  <CR code> » on a second, larger line; Arial-like bold sans serif,
  saturated blue text.
- **Date = the day that student's photo was taken** (photos are taken on different
  days), shown `dd/mm/yyyy`.
- **Long names (option B of the mockups):** same letter size every time; when the
  name does not fit on one line, words become initials, from the end, until it fits
  (« BIYONG NDJENG EMMANUEL PATRICE » → « BIYONG NDJENG EMMANUEL P. »). The app stores
  one `full_name` string and cannot tell surname from first names, so **the first two
  words are never shortened**. If the name still does not fit once every other word is
  an initial, the letters get smaller until it fits — nothing is ever cut off.
- **Exam code: one per class.** Every student of a class sits the same exam code. The
  codes the user listed: PBF3, PBF4-BA, PTAMEB, PTIH, PBCG, PTESF (Probatoire, 1ère);
  BAF3, BAF4-BA, BTAMEB, BTIH, BTESF (Bac, Terminale). The app suggests it from the
  class's level and series, and the user can change it.
- **« CR » code: typed by the user.** It is not per student; it is shared by a group of
  candidates (likely a school or exam-centre code) and may differ between groups, for a
  reason not known yet. So it is set per class, with a default to fill every class at
  once. The user named the whole of « CR 8127 » as this code, and the accepted mockup
  types it as one value, « CR 8127 »: the app prints what was typed, with no « CR »
  label of its own. The second line is « <exam code>  <CR code> » with wide spaces, as
  in the reference (« PBF3  CR  8127 »).
- **Codes are remembered** once filled in, so the user does not retype them.
- **The export page (mockup « export-page », accepted as is):** one line per exam class
  (1ère and Terminale) with its exam code, its CR code, « photos ready / students »
  and a warning count of students without a photo, and a « Zip » button. Opening a line
  shows that class's pictures as previews; a student without a photo shows as a
  « sans photo » tile with a link to take it. A « Code CR par défaut » field and a
  « Télécharger tout (zip) » button sit on top.
- **Picking students:** each preview has a tick box, all ticked by default, plus
  « Tous / Aucun » per class. Ticks are kept while moving between classes. Each class's
  « Zip » exports that class's ticked students; the top button becomes « Télécharger la
  sélection · N photos » and exports every ticked student of every class, one folder per
  class in the zip. Buttons show how many photos they will export.
- **The user zips and shares**; the app's job ends with the zip download.
- **Built in the app, this week** (not a one-off script).

## Deferred by the user

- **Which paid module this belongs to.** The user wants it sold as a paid feature
  « same as the school ID card » (today the ID card belongs to the « Photos et cartes »
  module, `:photos`). Whether it joins `:photos` or becomes its own module is open; the
  user asked to set it aside. **Interim (Claude's call):** the page goes under
  `:photos` in `TeacherAssistant.Modules`, next to the ID card the user compared it to;
  the user's school has `:photos` on (checked on the dev copy). Moving it to its own
  module later is one entry in `Modules` plus a new `Modules.Key` value.

## Goals

- From the app, in a few clicks, a zip of exam pictures for any set of exam candidates,
  matching the reference format.
- Works on a phone as well as a computer (the user works on a phone).

## Non-goals

- Uploading to the exam platform, or any link with it.
- Taking photos: the existing séance and student-page studio do that.
- Editing, retouching or replacing the stored photo.
- Exam codes per student, or any exam registration data beyond the two codes.
- Classes other than 1ère and Terminale (CAP and other exams are not in scope).

## Anti-goals (would make this a failure even if it works)

- Any change to a student's stored photo or its date.
- A picture whose name, date or codes are wrong or cut off — the platform may reject
  it, and the deadline is next week.
- An export that silently skips students: a ticked student without a photo must be
  visible before downloading, and never produce a blank or broken picture.

## Constraints

- **Server:** no image library is installed (no libvips/ImageMagick); adding one means
  new system packages on deploy. The browser already draws and encodes JPEGs in the
  photo studio hook (`assets/js/hooks/photo_studio.js`, canvas + `toBlob`).
- **Front end:** only the `app.js`/`app.css` bundles; no npm `package.json` — vendored
  JS lives in `assets/vendor/`. No inline `<script>`.
- **Photos** are stored as 600×800 JPEGs (3:4), served by `StudentPhotoController`
  (`/school/students/:id/photo`), same origin. `Student.photo_taken_at` holds the date
  of the current photo (set by `:set_photo`).
- **Series:** `ClassGroup.level` ("1ère", "Terminale") and `ClassGroup.serie`
  (e.g. "F3", "F4-BA", "AMEB", "IH", "ESF", "CG") already exist and match the codes.
- Project rules: Ash resources, migrations via `mix ash.codegen --dev` only, Ash enums
  not bare atoms, Gettext FR source with EN translations (no fuzzy entries left),
  `mix precommit` before committing.

## How (decided)

- **Pictures are drawn in the browser** (canvas → JPEG), like the photo studio, so
  nothing new is installed on the server and the zip downloads straight to the device.
- **Exam-code suggestion** from level + series, as observed on the user's classes
  (the user did not confirm the rule; it is only a suggestion the user can edit):

  | Level | Series | Code |
  |---|---|---|
  | 1ère | F3, F4-BA, CG | `PB` + series (PBF3, PBF4-BA, PBCG) |
  | 1ère | AMEB, IH, ESF | `PT` + series (PTAMEB, PTIH, PTESF) |
  | Terminale | F3, F4-BA | `BA` + series (BAF3, BAF4-BA) |
  | Terminale | AMEB, IH, ESF | `BT` + series (BTAMEB, BTIH, BTESF) |
  | other | — | empty, the user types it |

  The user's school also has a « Tle CG » class (no students this year); no Bac CG
  code was given, so its suggestion stays empty (Claude's call).

## Claude's calls (not discussed with the user — check these)

- **Who can open the page:** the same people who manage class photos today
  (`Enrollment.can_manage_register?/1`: school admin or conduct roles).
- **Where it lives:** a school-level page « Photos examen » (e.g.
  `/school/exam-photos`), linked from the school menu next to the other photo screens.
- **Picture size:** 600 px wide (the photo's own width, so no scaling of the face),
  bands sized to keep the reference's proportions (about 600×1024), JPEG quality 0.9,
  until the directorate gives an official size. Size and colours live in one place so
  they can be changed quickly.
- **File names:** `<exam code>_<NAME_IN_CAPITALS>.jpg`, accents removed, spaces →
  `_`, other unsafe characters dropped; a numeric suffix if two names collide. The
  pattern lives in one place so it can follow the platform's rule once known.
- **Zip name:** `photos-examen-<class label>.zip` per class,
  `photos-examen-<date>.zip` for a selection.
- **Zip format:** stored (no compression — JPEGs do not compress), written by a small
  hand-written zip writer in the app's JS, so no dependency is added.
- **Codes stored on the class** (two optional attributes on `ClassGroup`), so they
  follow the class within its year; the « Code CR par défaut » field fills the CR code
  of every exam class that has none and is not stored by itself.
- **A ticked student without a photo** is left out of the zip; the button count and a
  warning line say how many were left out.
- **A photo without a recorded date** prints no date (the band stays empty) and the
  preview shows it, rather than inventing a date.

## Left to the builder

- Exact font sizes, band heights and blue shade, as long as the result reads like the
  reference picture.
- How previews are rendered (the same canvas drawing as the export is preferred, so
  the preview is the picture).
- Whether codes are saved on blur or with a « save » button.
- Test approach for the drawing and the zip writer.
