# Member Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A member opens as its own page at `/school/members/:id` (tabs and day in the URL, settings on the page) instead of a drawer over the Membres list, and list rows become real links.

**Architecture:** A new `School.MemberLive` owns one member: loading, profile, tabs, settings, reset, deactivate. `MembersLive` keeps the list, filters, selection and the « Ajouter un membre » drawer. The account-state logic both pages need moves into one web-layer module; the role/status parsers move into `MembersComponents` next to `role_short/1`.

**Tech Stack:** Phoenix 1.8 LiveView, Ash (attribute multitenancy), gettext FR/EN, daisyUI + Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-11-19-member-page-design.md`

## Global Constraints

- Work on branch `review/latest-commits` in this worktree. Stage explicit paths only, never `git commit -a`. Never reset the dev DB.
- Every LiveView template starts with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`.
- Use `<.icon>` and `<.input>`; no inline `<script>`.
- New user-facing strings go through `gettext`, French source. After `MIX_ENV=test mix gettext.extract --merge`, fill every new English entry in `priv/gettext/en/LC_MESSAGES/default.po` and remove its `fuzzy` flag (fuzzy text is rendered).
- Who may open a member is unchanged: `Accounts.can_manage_staff?(scope) or Accounts.can_set_member_service?(scope)`.
- Copy: not-found flash « Membre introuvable. » (EN "Member not found."); save flash « Membre mis à jour. »; deactivate flash « Membre désactivé. » (both existing).
- Done = `mix precommit` green.

## Review Focus

1. Reloading `?tab=timetable` for a member with no timetable (non-teacher, or school without `:emploi_du_temps`) shows Résumé, no crash. → Task 2 test.
2. A plain teacher typing `/school/members/<id>` is refused and sent to `/school/members`. → Task 2 test.
3. An id that is not an active member of this school (another school's membership, a deactivated member, garbage) gives « Membre introuvable. » and the list, no crash. → Task 2 test.
4. `?day=garbage` or a day the member has no column for falls back to today/first day. → Task 2 test.
5. No member row on the list keeps a `phx-click`, so ctrl/⌘-click only opens a new tab. → Task 4 test.

---

### Task 1: Shared member helpers (pure refactor)

**Files:**
- Create: `lib/teacher_assistant_web/live/school/member_account.ex`
- Modify: `lib/teacher_assistant_web/live/school/members_live.ex` (remove `account_status/5`, `created_here_status/1`, `linked_status/0`, `self_managed_status/0`, `expiry_date/1`, `temporary_password_info/4`, the resettable/renamable/states block of `reload_members/1`, `parse_role/1`, `parse_roles/1`, `parse_membership_status/1`, `checked_roles/1`)
- Modify: `lib/teacher_assistant_web/live/school/members_components.ex`

**Interfaces:**
- Produces, in `TeacherAssistantWeb.School.MemberAccount`:
  - `access(scope, members, manager? :: boolean) :: %{resettable: MapSet.t(), renamable: MapSet.t(), states: %{membership_id => %{kind: atom, label: String.t(), note: String.t()}}}` — empty sets/map when `manager?` is false (same rules as today's `reload_members/1`).
  - `temporary_password_info(scope, user :: User.t(), password :: String.t(), kind :: :created | :reset) :: map` — same keys as today (`kind, name, login, value, expires_on, message`); takes the user instead of looking it up in `socket.assigns.members`.
- Produces, public in `TeacherAssistantWeb.School.MembersComponents`: `parse_role/1`, `parse_roles/1`, `parse_membership_status/1`, `checked_roles/1` (bodies moved unchanged).

- [ ] **Step 1:** Move the functions listed above; `MembersLive.reload_members/1` calls `MemberAccount.access(scope, members, socket.assigns.can_manage_staff?)` and assigns `resettable_member_ids`, `renamable_member_ids`, `account_states` from it. The `create_account` and `reset_password` handlers pass the user to `MemberAccount.temporary_password_info/4`.
- [ ] **Step 2:** Run `mix test test/teacher_assistant_web/live/school/members_live_test.exs test/teacher_assistant_web/live/school/member_profile_live_test.exs` — expected: all pass, no warnings.
- [ ] **Step 3:** Commit `refactor(members): share account state and role parsers`.

### Task 2: The member page — header, tabs and timetable in the URL

**Files:**
- Create: `lib/teacher_assistant_web/live/school/member_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (after `live "/school/members", …`, add `live "/school/members/:id", School.MemberLive, :show`)
- Modify: `lib/teacher_assistant_web/live/school/member_profile_components.ex` (`profile_tabs/1`, the day strip in `timetable/1`)
- Test: `test/teacher_assistant_web/live/school/member_profile_live_test.exs`, `test/teacher_assistant_web/live/school/member_profile_today_live_test.exs`

**Interfaces:**
- Consumes: Task 1's `MemberAccount.access/3`.
- Produces: `MemberLive` assigns `member` (the `SchoolMembership` with `user`), `profile`, `tab` (`"overview" | "timetable" | "settings"`), `day`, `today`, `can_manage_staff?`, `can_set_service?`, `account` (Task 1's map for `[member]`), `show_timetable?`. URL params `tab` and `day` (day as `Atom.to_string/1` of a `profile.days` entry).
- Produces: `profile_tabs/1` takes `attr :member_id` and renders each tab as `<.link patch={~p"/school/members/#{@member_id}?tab=#{value}"}>` keeping `id="member-tab-…"`, `role="tab"`, `aria-selected`, `aria-controls`, `tabindex` and the `MemberProfileTabs` hook. Change the sticky offset to the page (`top-0`, no `-mx-5`/`-top-5`). The day buttons stay `<button phx-click="member_day">` (`aria-pressed` needs a button); the handler `push_patch`es `?tab=timetable&day=<day>`.

- [ ] **Step 1: Rewrite the test helper and tab tests (failing).** In `member_profile_live_test.exs`, `open(conn, member, query \\ "")` becomes `{:ok, view, _} = live(conn, ~p"/school/members/#{member.id}" <> query); view`. Replace `#member-drawer` in selectors with `#member-page`. Tab clicks assert the patch: `view |> element("#member-tab-timetable") |> render_click(); assert_patch(view, ~p"/school/members/#{c.member.id}?tab=timetable")`. Day click: `assert_patch(view, ~p"/school/members/#{c.member.id}?tab=timetable&day=tuesday")`. Replace « changing member resets the tab » with two `live/2` calls on two ids each showing their own assignments. New tests:
  - `"a reload keeps the tab and the day"`: `open(c.conn, c.member, "?tab=timetable&day=tuesday")` → `#member-tab-timetable[aria-selected=true]`, `#member-day-tuesday[aria-pressed=true]`.
  - `"an unknown tab or day falls back"`: `"?tab=nope&day=garbage"` → `#member-tab-overview[aria-selected=true]`; `"?tab=timetable&day=sunday"` → today's/first day pressed (Review Focus 4).
  - `"timetable tab is ignored for a member who does not teach"`: non-teaching member with `"?tab=timetable"` → overview selected, no `#member-panel-timetable` (Review Focus 1).
  - `"ordinary teacher is refused"`: `assert {:error, {:live_redirect, %{to: "/school/members"}}} = live(teacher_conn, ~p"/school/members/#{c.member.id}")` (Review Focus 2; `:redirect` is also acceptable if `Authz.put_not_allowed` + `push_navigate` yields it — assert the `to`).
  - `"an unknown or deactivated member is not found"`: random UUID, a membership from a second school, and a deactivated member each redirect to `/school/members` with flash `"Membre introuvable."` (Review Focus 3).
  - `"the page is titled and crumbed with the member's name"`: `page_title(view) =~ "Awa Profile"`, `#member-breadcrumb a[href='/school/members']`.
  - In `member_profile_today_live_test.exs`, open the page URL instead of the drawer.
- [ ] **Step 2:** Run `mix test test/teacher_assistant_web/live/school/member_profile_live_test.exs test/teacher_assistant_web/live/school/member_profile_today_live_test.exs` — expected: FAIL (no route).
- [ ] **Step 3: Implement `MemberLive`.**
  - `mount/3`: no workspace → `push_navigate(~p"/school")`; neither right → `Authz.put_not_allowed` + `push_navigate(~p"/school/members")`; member = `Accounts.list_members(scope)` find by `to_string(id)` (the same policy-checked read the list uses; `nil` → flash « Membre introuvable. » + `push_navigate(~p"/school/members")`). Load `TeacherProfile.load(scope, member, allowed?: true)`, `today = SchoolCalendar.weekday(Reference.today())`, `page_title` = `User.display_name(member.user)`, `account = MemberAccount.access(scope, [member], can_manage_staff?)`.
  - `handle_params/3`: `tab` from the allowlist (`"timetable"` only when `show_timetable?`), else `"overview"`; `day` = the param if in `profile.days`, else today if in days, else `List.first(days)`.
  - `handle_event("member_day", …)` → `push_patch`; `handle_event("retry_member_profile", …)` reloads the profile.
  - Render: `<section id="member-page" class="mx-auto max-w-[760px] space-y-5">`, `.breadcrumb id="member-breadcrumb"` (« Membres » → `/school/members`, then the name), header (initials avatar `size-14`, `h1` name in the student page's `font-display` style, contact line, role labels), `contact_actions`, `profile_tabs`, `academic_panels`. Move `show_member_timetable?/3` here.
- [ ] **Step 4:** Run the two test files — expected: PASS.
- [ ] **Step 5:** Commit `feat(members): member page with tabs and day in the URL`.

### Task 3: Settings on the page

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/member_live.ex`
- Modify: `lib/teacher_assistant_web/live/school/members_components.ex` (extract `member_settings/1` from `member_drawer/1`)
- Test: `test/teacher_assistant_web/live/school/members_live_test.exs` (the drawer tests), `test/teacher_assistant_web/live/school/member_profile_live_test.exs`

**Interfaces:**
- Consumes: Task 1 (`MemberAccount`, parsers), Task 2 assigns.
- Produces: `member_settings/1` with the drawer's settings attrs (`member, form, error, state, resettable?, renamable?, can_manage_staff?, can_set_service?, roles, tab`), rendering `#member-panel-settings` (always mounted, `hidden` unless tab is settings) with the « Enregistrer » submit button at the end of `#member-form` (keep `phx-disable-with`). `MemberLive` events: `save_member`, `ask_reset_password`, `cancel_reset_password`, `reset_password`, `close_temporary_password`, `deactivate_member` — same payloads and DOM ids as today.

- [ ] **Step 1: Move the drawer tests (failing).** In `members_live_test.exs`, `open_member(view, id)` becomes `open_member(conn, id)` → `{:ok, view, _} = live(conn, ~p"/school/members/#{id}?tab=settings"); view`. Callers that asserted the list after an action now open `live(conn, ~p"/school/members")` again to check rows. Replace `#member-drawer` with `#member-page`. Changed expectations:
  - after a successful save: still on the page, flash « Membre mis à jour. », the saved values in the form;
  - after deactivate: `assert_redirect(view, ~p"/school/members")` and the flash « Membre désactivé. »;
  - errors (`entre 1 et 40`, `Indiquez le nom et le prénom.`, `dernier chef`) show in `#member-page`;
  - drop the « Fermer » test.
  In `member_profile_live_test.exs`, « settings remain mounted » asserts `#member-form button[type=submit]` exists while the settings panel is `hidden` on another tab.
- [ ] **Step 2:** Run `mix test test/teacher_assistant_web/live/school/members_live_test.exs test/teacher_assistant_web/live/school/member_profile_live_test.exs` — expected: the moved tests FAIL.
- [ ] **Step 3: Implement.** Move the handlers above, `save_service/3`, `save_name/3`, `save_roles/3`, `save_status/3`, `member_form/1`, `member_error/4` and the `confirm_reset_dialog` / `temporary_password_dialog` rendering into `MemberLive`. After a save or a reset, reload the member (and `account`) by id; if it is gone, flash « Membre introuvable. » and `push_navigate` to the list. `deactivate_member` success → `put_flash` + `push_navigate(~p"/school/members")`.
- [ ] **Step 4:** Run the two test files — expected: PASS.
- [ ] **Step 5:** Commit `feat(members): member settings, reset and deactivation on the page`.

### Task 4: List rows become links; the drawer goes

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/members_live.ex`
- Modify: `lib/teacher_assistant_web/live/school/members_components.ex` (`member_row/1`, delete `member_drawer/1`)
- Test: `test/teacher_assistant_web/live/school/members_live_test.exs`, `test/teacher_assistant_web/live/school/staff_names_test.exs` (check it still passes)

**Interfaces:**
- Consumes: Task 2's route.
- Produces: desktop `<tr id="member-tr-…">` gets `ta-row-open` when `@can_manage_staff? or @can_set_service?`; the name is `<.link id="member-open-#{m.id}" navigate={~p"/school/members/#{m.id}"} class="ta-row-link font-semibold hover:text-primary">` (the checkbox stays above it through the existing `.ta-row-open :is(input…)` rule). `member_row/1` drops `selected` and `phx-click`, passes `navigate={@editable? && ~p"/school/members/#{@member.id}"}` to `list_row` (keep `id="member-row-…"`).

- [ ] **Step 1: Write the failing test** in `members_live_test.exs`, `"a member row opens the member page through a link, never a click handler"`: head's list has `#member-open-#{m.id}[href='/school/members/#{m.id}']`, `a#member-row-#{m.id}[href='/school/members/#{m.id}']`, `tr#member-tr-#{m.id}.ta-row-open`; `refute has_element?(view, "[phx-click='edit_member']")`; and for a plain teacher, no `#member-open-…` link and no `a[id^='member-row-']` (Review Focus 5).
- [ ] **Step 2:** Run it — expected: FAIL.
- [ ] **Step 3: Implement.** Make the row changes; delete from `MembersLive` the `edit_member`, `member_tab`, `member_day`, `retry_member_profile`, `save_member`, `ask_reset_password`, `cancel_reset_password`, `reset_password`, `deactivate_member` handlers, `load_member_profile/1`, `show_member_timetable?/3`, the member fields of `close_drawer/1` and `mount/3` (`member_profile, member_tab, member_day, member_today, editing, member_form, member_error, reset_candidate`), the `<.member_drawer>` and `<.confirm_reset_dialog>` render, and the now-unused aliases. Keep `temporary_password` for « Ajouter un membre ». Delete `member_drawer/1`. Update the `@moduledoc` (« the member page » instead of « the member drawer »).
- [ ] **Step 4:** Run `mix test test/teacher_assistant_web/live/school/` — expected: PASS, and `mix compile --warnings-as-errors` clean.
- [ ] **Step 5:** Commit `feat(members): list rows link to the member page; drop the drawer`.

### Task 5: Copy, precommit, browser check

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/*/LC_MESSAGES/default.po`

- [ ] **Step 1:** `MIX_ENV=test mix gettext.extract --merge`; fill "Membre introuvable." → "Member not found." and any other new entry in the English `.po`, no `fuzzy` left on them.
- [ ] **Step 2:** `mix precommit` — expected: exit 0, all tests pass.
- [ ] **Step 3: Browser check** on the dev server (`PORT=4010 ELIXIR_ERL_OPTIONS="-live_debugger 'disabled?' true" mix phx.server`, run in the background, demo school seed): from Membres open a teacher, switch tabs and days (URL changes, back button returns through them), reload on Emploi du temps, save a service change, reset a password on a school-created account, cmd-click check by synthetic event (`defaultPrevented` false); repeat at 375 px wide (sticky tabs, header wrap, no horizontal scroll).
- [ ] **Step 4:** Commit the gettext files and any fixes: `chore(members): member page copy`.
