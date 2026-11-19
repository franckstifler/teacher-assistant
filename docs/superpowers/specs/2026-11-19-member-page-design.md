# Member page (replaces the member drawer) — design

Date: 2026-11-19. Supersedes the drawer part of `2026-11-17-teacher-member-profile-design.md`.

## Intent

A member (most often a teacher) opens as a page of their own, the way a student
does at `/school/students/:id`, not in a drawer over the Membres list. The user
asked for it: the drawer is inconsistent with the student page, it cannot be opened
in a new tab or shared, and the back button leaves the list instead of closing it.

## Goals

- `/school/members/:id` shows everything the drawer shows today: header, contact
  actions, Résumé, Emploi du temps, Paramètres (name, roles, employment status,
  weekly service, account state, password reset, deactivation).
- The tab and the chosen day are in the address (`?tab=timetable&day=tuesday`), so
  the back button, a reload and a shared link land on the same view.
- On the Membres list, a member's row is a real link: a tap opens the page, and
  ctrl/⌘/middle-click opens it in a new tab and leaves the list alone (the
  `ta-row-open` / `ta-row-link` pattern from 58ec585).

## Non-goals

- No new information on the page, no new permissions: who may open a member is
  unchanged (staff managers or service managers, `can_manage_staff?` /
  `can_set_service?`); others still see names as plain text on the list.
- « Ajouter un membre » stays a drawer on the list: it creates someone, it does not
  show someone.
- Teacher names elsewhere (assignments, timetable editor, séquence tracking) are not
  turned into links to this page in this change. That is a possible follow-up.
- No schema change.

## Approaches considered

1. **One full page, settings on the page** — chosen by the user. One place to see and
   manage a member; matches the student page.
2. Profile on a page, settings kept in a drawer on the list — less code moved, but a
   member is managed in two places, which is the inconsistency being removed.
3. A page for teachers only, the drawer for other members — two ways to open a
   member depending on their role; rejected for the same reason.

## Design

**Route.** `live "/school/members/:id", School.MemberLive, :show` in the same
`live_session` as `/school/members`. An unknown or deactivated member, or a viewer
without the right, goes back to `/school/members` (not-allowed flash for the latter,
« Membre introuvable » for the former).

**Page layout** (phone first, same width as the student page):

```
Membres › Awa Ndjock                         ← breadcrumb, « Membres » links back
(AN)  Awa Ndjock                             ← initials avatar, name (h1)
      +237 6 99 00 11 22 · Enseignant, Censeur
[Appeler] [WhatsApp] [SMS]                   ← existing contact_actions
Résumé | Emploi du temps | Paramètres        ← patch links, ?tab=…
…tab panel…
```

- Tabs are `<.link patch>` instead of `phx-click="member_tab"`; the existing
  allowlist stays (`overview`, `timetable` only when the timetable shows, `settings`
  only for those who may change something). An invalid `tab` falls back to Résumé.
- The day buttons in Emploi du temps patch `?tab=timetable&day=…`; no `day` means
  today when it is a school day, else the first day (as now).
- Paramètres: the same form, with « Enregistrer » at the bottom of the form instead
  of a drawer footer. A successful save stays on the page with « Membre mis à
  jour. »; errors show in place as today. Deactivating sends the head back to the
  list with « Membre désactivé. ». The reset-password confirmation and the
  temporary-password dialog move to the page unchanged.
- Page title: the member's display name.

**Code ownership.**

- New `School.MemberLive` owns one member: loading it, `TeacherProfile.load`, the
  save / reset / deactivate handlers now in `MembersLive`.
- The account-state logic (`account_status/5` and its helpers, `temporary_password_info`)
  is needed by both the list (Accès column) and the page; it moves out of
  `MembersLive` into one shared module rather than being copied.
- `member_drawer` becomes the page's body (header + tabs + panels) in
  `MembersComponents` / `MemberProfileComponents`; the drawer wrapper, `edit_member`,
  `member_tab`, `member_day`, `close_drawer`'s member fields and `@editing` leave
  `MembersLive`.
- List rows: the desktop `<tr>` gets `ta-row-open` and the name becomes a `.link
  navigate` with `ta-row-link` (the checkbox stays clickable above it); the phone
  `member_row` uses `list_row`'s existing `navigate`. Rows for viewers who cannot
  open members stay plain.

**Tests.** The drawer tests (`member_profile_live_test`,
`member_profile_today_live_test`, the drawer parts of `members_live_test`,
`staff_names_test`) move to the page: opening from the list, tabs and day in the
URL, reload on a tab, permissions (direct URL refused), save / reset / deactivate,
unknown id, list rows are links with no row click handler.

## Left to the builder

- The shared module's name and whether it lives under `TeacherAssistantWeb.School`
  or `Accounts`.
- Whether the page loads one membership directly or filters `Accounts.list_members/1`
  (one read is preferred if a policy-checked action exists).
- Exact copy for the « introuvable » flash.
