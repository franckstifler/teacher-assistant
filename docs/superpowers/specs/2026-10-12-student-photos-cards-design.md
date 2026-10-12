# Student photos & school ID cards — design

Status: approved in chat 2026-10-12, awaiting spec review.

## 1. Goal

Let the school attach a face photo to every student, fast enough to do a whole
class (≈60 students) in a few minutes from a phone, and reuse it on the report
card (bulletin) and on a printable school ID card.

Delivered in two parts, one spec: **Part A — photos** (capture, upload, display,
bulletin), then **Part B — ID cards** (print page).

### User decisions

| Topic | Decision |
|---|---|
| Who takes photos | School-life staff: **admin axis** (Proviseur, Censeur) and **conduct axis** (SG, surveillant). Not form masters, not teachers. |
| Bulk flow | **Both**: a class photo grid (fix / complete) and a chained full-screen « séance ». |
| Existing files | **One at a time on the grid** (tap or drag-and-drop on a thumbnail). No bulk-by-matricule, no bulk-by-order. |
| Published bulletin | **Photo frozen at publication** (path stored in the snapshot, old files kept). |
| Capture tech | In-page camera (`getUserMedia`) for the séance; native file input (camera / gallery / file picker) on the grid; fallback to the file input when the camera is refused. |
| ID card content | School header (logo, name, year) · photo · **name** · class · matricule, sex, birth date & place · primary guardian name + phone · head's signature + stamp. |

## 2. Data

`TeacherAssistant.Academics.Student` gains:

- `photo_path` — `:string`, nullable, public. Relative to `uploads_dir`.
- `photo_taken_at` — `:utc_datetime`, nullable, public.

New actions (not the generic `:update`):

- `:set_photo` — accepts `photo_path`; sets `photo_taken_at` to now.
- `:remove_photo` — sets both to `nil`.

Policy for both: `forbid_unless` active member; `authorize_if` `SchoolRole`
`:admin` or `:conduct`. (The form-master clause of `:update` does **not** apply.)
Read stays as today (any member), so every member sees avatars.

Domain functions: `set_student_photo/3`, `remove_student_photo/2`,
`can_manage_student_photos?/1` (`Ash.can?({Student, :set_photo}, scope)`-style,
matching the other `can_*?` helpers).

Migration via `mix ash.codegen --dev`, then named codegen per house rule.

## 3. Storage — `TeacherAssistant.StudentPhotos`

One module owns the file side effects:

- `store(scope, student, tmp_path)`:
  1. reject files > 1 MB;
  2. check JPEG magic bytes (`FF D8 FF`) — the client always sends JPEG, the
     declared extension is not trusted;
  3. copy to `uploads_dir/student_photos/<workspace_id>/<uuidv7>.jpg`;
  4. call `:set_photo`; on error delete the copied file and return the error.
- `resolve(relative_path)` — absolute path under `uploads_dir` or `:error`.

The path guard currently private in `SchoolLogoController.safe_logo_path/1` moves
to a shared helper (e.g. `TeacherAssistant.Uploads.resolve/1`) used by both the
logo controller and `StudentPhotos`.

Files are **never overwritten or deleted** on replace/remove: published
snapshots may reference them. Size is negligible (≈30–60 KB per photo). No
garbage collection in this increment.

## 4. Serving

`StudentPhotoController` (in the authenticated `/school` browser scope, like
`/school/logo`):

- `GET /school/students/:id/photo` — current photo. Loads the student through
  the caller's scope (other school → 404), `send_file` with
  `Cache-Control: private, max-age=86400`. The URL carries `?v=<photo_taken_at
  unix>` from the avatar so a replaced photo is not served stale.
- `GET /school/bulletins/:publication_id/photo/:student_id` — frozen photo:
  loads the publication through scope, reads the student's `photo_path` from its
  snapshot, resolves and sends it. 404 when absent.

## 5. Display

`<.initials_avatar name=…>` stays; new `<.student_avatar student=… class=…>` in
`core_components.ex` renders the photo when `photo_path` is set, initials
otherwise. Used in: class Élèves tab (`class_live.ex`), `/school/students`
(`students_live.ex`), student page header (`student_live.ex`), roll call
(`roll_call.ex`) where the row shows an avatar.

## 6. Bulletin

- `BulletinElement` gains `:photo` (label « Photo de l'élève »). It is in
  `defaults/0`, so schools that never saved a list get it; schools with a saved
  list keep exactly that list (existing rule).
- Publishing writes snapshot **v4**: each student entry adds `photo_path`
  (current value at publication, may be `nil`). `snapshot_version` → 4.
- Print (`bulletin_print_html/show.html.heex`) and the in-app bulletin view:
  when `:photo` is enabled — published: `<img>` from the frozen-photo route
  if the snapshot has a path; draft: current photo route. Snapshots v1–v3 have
  no key → no photo. Placement: top-right of the student identity block,
  ≈25 × 32 mm. No photo → nothing drawn (no empty frame on bulletins).

## 7. Photos page — `/school/classes/:id/photos`

`School.ClassPhotosLive`, inside `class_shell` (header/breadcrumb), but **not a
new tab**: reached by a « Photos » button on the Élèves tab, shown only when
`can_manage_student_photos?/1`. Mount refuses others (same pattern as other
gated pages). Students = the class's current enrollments.

### 7.1 Grid (default, mobile-first)

- Header: « 41/58 photos », toggle « Sans photo uniquement », primary button
  **« Lancer la séance »**, secondary « Cartes scolaires » (→ §9).
- 3:4 thumbnails (2 columns on phone, more on wider screens), name below;
  missing → initials + « Sans photo » badge.
- Tap → bottom sheet: *Prendre / choisir une photo* · *Supprimer* (when set) ·
  *Annuler*. « Prendre / choisir » = `<input type="file" accept="image/*">`
  (phone offers camera or gallery) → crop screen (§7.3) → upload.
- Desktop: dropping an image file on a thumbnail opens the crop screen for that
  student.
- Delete asks for confirmation in-page (no browser `confirm`).

### 7.2 Séance (full-screen mode of the same LiveView)

- Top bar: « 12/58 · NGONO Marie », buttons *Passer*, *Quitter*.
- Live camera viewfinder with a 3:4 frame and a face oval; back camera by
  default (staff photographs the student), switch button for the front camera.
- Big shutter → still preview → **Reprendre** / **Valider ✓**. Valider queues
  the upload and immediately shows the next student.
- Order: students without a photo first, alphabetical (class list order);
  « Refaire toute la classe » option includes everyone.
- Upload indicator « 3 en cours d'envoi »; failed uploads stay in memory with
  *Réessayer*; pending uploads are retried after a LiveView reconnect.
- Screen Wake Lock while the séance is open, when supported.
- Camera refused / unavailable → message and fall back to the file input flow
  for the current student.
- End of list → summary « 17 photos prises, 2 passées » → back to grid.

### 7.3 Crop screen (file / gallery / drop)

3:4 frame over the image; drag to move, slider / pinch to zoom; *Valider* /
*Annuler*. Initial position: centred, cover-fit.

### 7.4 Client processing & upload

- Two hooks in `assets/js` (imported in `app.js`): `PhotoCapture` (séance) and
  `PhotoCrop` (crop screen). Both output a **JPEG 600 × 800, quality 0.85** via
  canvas (`toBlob`); the browser decodes HEIC/PNG/etc., the server only ever
  receives JPEG.
- Upload through `allow_upload(:photo, accept: ~w(.jpg .jpeg), max_entries: 5,
  max_file_size: 1_000_000, auto_upload: true, progress: &handle_progress/3)`;
  the hook calls `this.upload("photo", [file])` with the file named
  `<student_id>.jpg`.
- `handle_progress` on `done?`: parse the student id from `client_name`, check
  it is one of this class's enrolled students (else drop the entry, error
  flash), `consume_uploaded_entry` → `StudentPhotos.store/3`; update the grid
  item and counters; push an ack event so the hook drops the blob from its
  retry queue.

## 8. Student page

On `/school/students/:id`, for `can_manage_student_photos?/1`: the avatar is
tappable and opens the same sheet (take/choose → crop → upload, delete). The
sheet + crop screen are a function component + the `PhotoCrop` hook shared with
§7 (no duplicated markup). Also a « Carte scolaire » link (→ §9, single student,
current class).

## 9. ID cards — Part B

`CardPrintController`, HTML print page like `BulletinPrintController`:

- `GET /school/classes/:id/cards/print` — every student of the class.
- `GET /school/classes/:id/cards/print?student=<id>` — one student (must be
  enrolled in that class).
- Access: admin or conduct axis (`can_manage_student_photos?/1`); others 404/forbidden
  as the bulletin print does.

Layout: ISO ID-1 card **85.6 × 54 mm**, A4 portrait, 2 × 5 = 10 cards per page,
crop marks, margins safe for common printers, `print-color-adjust: exact`.

Card content:

- Band: school logo, school name, academic year (e.g. 2026-2027).
- Left: photo ≈22 × 29 mm; no photo → empty framed box labelled « Photo ».
- Right: **full name** (bold), class, matricule, sex, birth date & place.
- Footer: « Contact : <name> – <phone> » of the `primary_contact` guardian,
  else the first linked guardian, else omitted.
- Head's signature and stamp images when uploaded (`/school/logo?kind=…`).
- Labels follow `SchoolProfile.bulletin_language` (FR / EN / bilingual).

Screen-only toolbar above the sheet: « Imprimer » button and a warning
« 3 élèves sans photo » linking to the photos grid.

## 10. Translations

All new strings through Gettext; after `mix gettext.extract --merge`, fill and
unflag every new fuzzy entry (guard test exists).

## 11. Testing

- `StudentPhotos`: valid JPEG stored + `photo_path` set; fake JPEG and > 1 MB
  rejected; path escaping `uploads_dir` refused; copied file removed when the
  action fails.
- Policies: SG/surveillant/Proviseur can `:set_photo`/`:remove_photo`; teacher
  and form master cannot; another school's member gets 404 on both photo routes.
- `ClassPhotosLive`: `file_input` + `render_upload` stores and updates counter;
  file named after a student outside the class is rejected; delete; « Sans
  photo » filter; page refused to a teacher; « Photos » button hidden for them.
- Bulletin: v4 snapshot carries `photo_path`; after replacing the photo the
  published bulletin still points at the old file; v3 snapshot renders without
  photo; unchecking `:photo` hides it; draft shows current photo.
- Cards: class and single-student print; primary guardian chosen; empty photo
  box; non-enrolled `student` param refused; teacher refused.
- JS hooks: no automated tests; manual check in Chrome at phone width on the
  demo school (séance, crop, retry after reconnect, camera refusal fallback).

## 12. Out of scope

Bulk import by matricule or by order; photo garbage collection; face detection /
auto-centring; card back side, barcode or QR on cards; photos for staff; parent
or student self-upload; offline capture beyond the in-memory retry queue.
