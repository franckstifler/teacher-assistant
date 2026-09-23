# Web-layer audit — TeacherAssistant (Phoenix 1.8 / LiveView 1.2 / Ash)

Read-only audit against `.claude/skills/phoenix-framework/**`, `AGENTS.md`, and `.claude/skills/ash-framework/references/ash_phoenix/*`. Every file under `lib/teacher_assistant_web`, `assets/css/app.css`, `assets/js/**`, the print/landing/auth templates, a sample of `test/teacher_assistant_web/**`, and `priv/gettext` were read in full. Nothing was edited (`git status` clean after the run).

## 1. Summary

- **Structure is sound**: every one of the 27 LiveViews opens with `<Layouts.app flash={@flash} current_scope={@current_scope}>`, scope is resolved once in `on_mount` per `ash_authentication_live_session`, `push_navigate`/`push_patch` are used correctly (no `live_redirect`/`live_patch`, no `phx-update="append"`, no `Heroicons.`, no `~E`, no inline `<script>` in LiveView templates, no LiveComponents), `<.icon>` everywhere, `app.css` uses the exact Tailwind v4/daisyUI import syntax, `mix compile --force` produces **0 warnings**.
- **Biggest architectural gap**: the web layer never passes an `actor` to Ash (0 hits). Authorization is 60 manual `Permissions.*` checks inside `handle_event` clauses plus `fetch_owned_*` helpers, while the resources' policies are `authorize_if always()` (32 occurrences). This is the "authorization hardening (C)" spec already on the roadmap; the audit confirms every write path relies on the LiveView remembering to check.
- **Forms drift from the rules**: ~29 raw `<form>` tags and ~56 raw `<input>/<select>` instead of `<.form>`/`<.input>`; 10 forms are built inline in templates (`for={AshPhoenix.Form.for_update(...) |> to_form()}`, `for={%{}}`, one `<.form :let={f}>`); 7 "scaffold" AshPhoenix forms whose submit bypasses `AshPhoenix.Form.submit` and hand-parses params with `String.to_existing_atom` (15 sites) — unknown values crash the LiveView instead of surfacing a field error.
- **Data loading**: `Layouts.app` runs two DB queries on every render of every LiveView (units + workspaces); six param-driven LiveViews load their data twice on first mount (mount + handle_params); several N+1 loops (`list_roster` per class to count, `coverage_for_plan` per plan, `get_lesson_plan_for_entry` per entry on every event); **no LiveView streams at all** (acceptable for bounded class lists, but rosters/balances/members/sanctions re-render fully on every event).
- **Duplication**: 8 controllers copy the same `load_user`/`scope_for` preamble; `presence/blank_to/parse_decimal/fmt/pick/default_period/authorized?/day_label` are each redefined in 2–8 files; the period selector, print link, invite form and timetable grid are copy-pasted.
- **i18n**: `mix gettext.extract --check-up-to-date` **fails** (`default.pot` stale); EN catalog has **211/652 untranslated** msgids; msgids mix English and French source strings; auth pages, landing page, `AuthController` flashes and `Layouts` auth copy are hard-coded French/English outside gettext; `<html lang="en">` while default locale is `fr`.
- **Tests**: 291 tests, good use of form ids + `render_submit/render_change` (145×), no `Process.sleep`; but 261 raw `html =~ "text"` assertions vs 218 `element/has_element?` (rule: never assert on raw HTML), and the login helper writes `:user_id` straight into the session, which is why every controller carries a `conn.assigns[:current_user] || load_user(session)` fallback.

Commands run: `mix phx.routes` → 67 lines; `mix compile --force 2>&1 | grep -c warning` → **0**; `mix gettext.extract --check-up-to-date` → **exit 1** (`priv/gettext/default.pot` out of date); `mix gettext.merge priv/gettext --check` → `--check` is not a merge flag, it merged (0 new / 0 removed / 651 unchanged for both locales; files byte-identical, git clean).

## 2. Route map (`mix phx.routes`, 67 lines, grouped)

### Public browser scope (`scope "/", TeacherAssistantWeb`, pipeline `:browser`)
| Verb | Path | Module | Action |
|---|---|---|---|
| GET | / | PageController | :home |
| GET | /schools/start | PageController | :start_school |
| GET | /workspaces/select/:id | WorkspaceController | :select |
| POST | /workspaces | WorkspaceController | :create — **no caller in lib/ or test/ (dead route)** |
| GET | /teacher/select-context/:id | TeacherContextController | :select |
| GET | /teacher/entries/:entry_id/fiche/print | FichePrintController | :show |
| GET | /school/classes/:id/students/:enrollment_id/bulletin/print | BulletinPrintController | :show |
| GET | /school/classes/:id/bulletin/print | BulletinPrintController | :class |
| GET | /school/classes/:id/timetable/print | TimetablePrintController | :class |
| GET | /school/timetable/me/print | TimetablePrintController | :me |
| GET | /school/logo | SchoolLogoController | :show |
| GET | /locale/:locale | LocaleController | :set |
| GET | /schools/invitations/:token | SchoolInvitationController | :show |
| POST | /schools/invitations/:token/accept | SchoolInvitationController | :accept |

### AshAuthentication (same scope; `auth_routes`, `sign_in_route`, `reset_route`, `magic_sign_in_route`, `sign_out_route`)
| Verb | Path | Module | Action |
|---|---|---|---|
| GET | /auth/user/magic_link | Accounts.User.magic_link | :accept |
| POST | /auth/user/magic_link/request | Accounts.User.magic_link | :request |
| POST | /auth/user/magic_link | Accounts.User.magic_link | :sign_in |
| GET | /auth/user/password/sign_in_with_token | Accounts.User.password | :sign_in_with_token |
| POST | /auth/user/password/register | Accounts.User.password | :register |
| POST | /auth/user/password/sign_in | Accounts.User.password | :sign_in |
| POST | /auth/user/password/reset_request | Accounts.User.password | :reset_request |
| POST | /auth/user/password/reset | Accounts.User.password | :reset |
| GET | /sign-out | AshAuthentication.Phoenix.SignOutLive | :sign_out |
| DELETE | /sign-out | AuthController | :sign_out |
| GET | /sign-in | AshAuthentication.Phoenix.SignInLive | :sign_in (layout `Layouts.auth`, on_mount `:live_no_user`) |
| GET | /reset | AshAuthentication.Phoenix.SignInLive | :reset |
| GET | /register | AshAuthentication.Phoenix.SignInLive | :register |
| GET | /password-reset/:token | AshAuthentication.Phoenix.ResetLive | :reset |
| GET | /magic_link/:token | AshAuthentication.Phoenix.MagicSignInLive | :sign_in |

### `ash_authentication_live_session :teacher_workspace` (on_mount `:live_user_required`, `:require_teaching_scope`)
| Verb | Path | Module | Action |
|---|---|---|---|
| GET | /teacher | Teacher.DashboardLive | :index |
| GET | /teacher/setup | Teacher.SetupLive | :index |
| GET | /teacher/import | Teacher.ImportLive | :new |
| GET | /teacher/log | Teacher.LogLive | :index |
| GET | /teacher/plans/:id | Teacher.FicheLive | :show |
| GET | /teacher/plans/:id/coverage | Teacher.CoverageLive | :show |
| GET | /teacher/contexts/:id/roster | Teacher.RosterLive | :index |
| GET | /teacher/contexts/:id/marks | Teacher.MarksLive | :index |
| GET | /teacher/contexts/:id/marks/summary | Teacher.MarksSummaryLive | :index |
| GET | /teacher/entries/:entry_id/fiche | Teacher.LessonPlanLive | :edit |

### `ash_authentication_live_session :school_workspace` (on_mount `:live_user_required`, `:require_school_setup`)
| Verb | Path | Module | Action |
|---|---|---|---|
| GET | /school | School.DashboardLive | :index |
| GET | /school/classes | School.ClassesLive | :index |
| GET | /school/classes/:id | School.ClassLive | :show |
| GET | /school/classes/:id/results | School.ResultsLive | :index |
| GET | /school/classes/:id/timetable | School.TimetableLive | :show |
| GET | /school/classes/:id/attendance/:period_id | School.AttendanceLive | :show |
| GET | /school/classes/:id/register | School.RegisterLive | :show |
| GET | /school/classes/:id/discipline | School.DisciplineLive | :show |
| GET | /school/classes/:id/fees | School.FeesLive | :show |
| GET | /school/timetable/me | School.MyTimetableLive | :index |
| GET | /school/classes/:id/students/:enrollment_id/bulletin | School.BulletinLive | :show |
| GET | /school/classes/:id/import | School.EnrollImportLive | :new |
| GET | /school/members | School.MembersLive | :index |
| GET | /school/settings | School.SettingsLive | :index |
| GET | /school/periods | School.PeriodsLive | :index |
| GET | /school/setup | Onboarding.SetupWizardLive | :index |

### `ash_authentication_live_session :onboarding` (on_mount `:live_user_required`)
| GET | /schools/new | Onboarding.CreateSchoolLive | nil |

### `ash_authentication_live_session :operator` (on_mount `:live_user_required`, `:require_operator`)
| GET | /admin/schools | Admin.SchoolsLive | nil |

### Dev only (`if Application.compile_env(:teacher_assistant, :dev_routes)`)
| GET | /dev/dashboard/css-:md5 | Phoenix.LiveDashboard.Assets | :css |
| GET | /dev/dashboard/js-:md5 | Phoenix.LiveDashboard.Assets | :js |
| GET | /dev/dashboard | Phoenix.LiveDashboard.PageLive | :home |
| GET | /dev/dashboard/:page | Phoenix.LiveDashboard.PageLive | :page |
| GET | /dev/dashboard/:node/:page | Phoenix.LiveDashboard.PageLive | :page |
| * | /dev/mailbox | Plug.Swoosh.MailboxPreview | [] |

### Sockets
| WS | /live/websocket | Phoenix.LiveView.Socket | |
| GET/POST | /live/longpoll | Phoenix.LiveView.Socket | |

## 3. Findings

Severity: **High** = correctness/security/perf impact now; **Medium** = rule violation with real cost; **Low** = rule/consistency nit.

### 3.1 Routing / auth / scope

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-01 | High | ash_phoenix/best_practices "let the resource guide"; AGENTS.md `current_scope` | `grep actor:` → 0 hits in `lib/teacher_assistant_web`; manual checks e.g. `live/onboarding/setup_wizard_live.ex:250,282,305,343`, `live/school/fees_live.ex:74,110,139,169,206,230,251`, `live/school/settings_live.ex:345,376,405,427,447,460,489,525,549`, `live/school/class_live.ex:410,446,466,488,523,543,557,568,594,642`, `live/school/members_live.ex:172,195,212,239,268`, `live/school/periods_live.ex:123,134,162`, `live/teacher/marks_live.ex:174`, `live/school/attendance_live.ex:159,167` | No Ash call in the web layer carries an actor; every write is guarded only by an `if Permissions.x?(scope)` / `with true <- socket.assigns.admin?` in the LiveView (60 sites). Resources declare policies (31 files) but 32 are `authorize_if always()`. Any handler that forgets the check (e.g. `admin/schools_live.ex:75-103` relies solely on `on_mount :require_operator`; `class_live.ex:410` gates on `manage?` which is hard-coded `true` at `:28`) is an open door. | Pass `actor: scope.current_user` (or `scope: scope`) on every domain call / code-interface call, move the `Permissions` rules into Ash policies, keep the LiveView checks for *display* only. This is the roadmap's "authorization hardening (C)". |
| WEB-02 | Medium | phoenix.md router/plug conventions; DRY | `controllers/bulletin_print_controller.ex:35-44,96-103`, `fiche_print_controller.ex:8-11,37-44`, `school_logo_controller.ex:8-11,38-45`, `teacher_context_controller.ex:7,29-36`, `timetable_print_controller.ex:12-15,39-43,61-68`, `workspace_controller.ex:8,28,40-47`, `school_invitation_controller.ex:63-77`; `live_user_auth.ex:88-121` | Eight copies of `user = conn.assigns[:current_user] \|\| load_user(get_session(conn, :user_id))` + `Workspaces.scope_for(...)`. The `:browser` pipeline (`router.ex:14`) runs `load_from_session` but nothing builds `current_scope` for controllers, so each controller rebuilds it. | Add a `TeacherAssistantWeb.Plug.Scope` to `:browser` that assigns `:current_scope` once (reusing `LiveUserAuth.resolve_scope/3`); controllers read `conn.assigns.current_scope`; delete the 8 `load_user/1` copies. |
| WEB-03 | Medium | `<.link navigate>` only for LiveView targets (liveview.md) / UX | `components/layouts.ex:336,343` (`navigate={~p"/locale/fr"}`), `controllers/locale_controller.ex:10` | Locale switch is a `navigate` to a dead controller route (LiveView falls back to a full reload) and the controller always redirects to `/teacher`, so a school user switching language is thrown out of the school workspace and off the page they were on. | Use `href=` (or `<.link href method="post">`), and redirect to the `referer`/a `return_to` param. |
| WEB-04 | Low | consistency | `live_user_auth.ex:100-101` (`assign(:current_scope)` **and** `assign(:scope)`), reassigned again in `live/school/dashboard_live.ex:14`, `periods_live.ex:21`, `members_live.ex:13`, `settings_live.ex:21`; `settings_live.ex:348-353` must update both | Two names for the same struct; handlers read `socket.assigns.scope` in some files and `current_scope` in others. | Keep only `current_scope`. |
| WEB-05 | Low | dead code | `router.ex:38` `POST /workspaces`, `controllers/workspace_controller.ex:27-38` | No template or test posts to `/workspaces` (`grep ~p"/workspaces"` → 0). | Remove route + action (school creation is `CreateSchoolLive`). |
| WEB-06 | Low | inconsistency | `controllers/timetable_print_controller.ex:14-18` vs `bulletin_print_controller.ex:41-42` | Bulletin print checks `Permissions.operating_allowed?` (verification gate); timetable print does not; `TimetablePrintController.me/2` (`:38-43`) has no membership check at all beyond `:school` workspace type. | Align the gate in the shared scope plug (WEB-02). |
| WEB-07 | Low | `on_mount` hygiene | `live_user_auth.ex:26-30` attaches a `handle_params` hook on every mount to compute `current_path`; `layouts.ex:77` defaults it to `"/teacher"` | Works, but `current_path` could come from `assign_new` + `URI.parse(uri)` in the hook only when it changes; the `"/teacher"` default highlights the teacher dashboard link on school pages before first `handle_params`. | Default to `nil`, not `"/teacher"`. |

### 3.2 Templates / HEEx

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-08 | High | liveview.md "Always use a form assigned via `to_form/2` in the LiveView … **Never** use `<.form let={f}>`" | `live/teacher/fiche_live.ex:590-598` (`<.form :let={f} for={entry_form_for(m)}>`), `:481` (`for={AshPhoenix.Form.for_update(m, :update, as: "credit") \|> to_form()}`), `:497`; `live/teacher/lesson_plan_live.ex:237` + `step_form(s)` re-evaluated 6× per row (`:237,244,247,253,258,263`); `live/school/periods_live.ex:48`; `live/school/settings_live.ex:236`; `live/teacher/marks_live.ex:509,617` (`for={to_form(%{}, as: :scores)}`); `live/teacher/import_live.ex:58,127`, `live/school/enroll_import_live.ex:48`, `settings_live.ex:132` (`for={%{}}`) | Forms are constructed inside `render`, so an `AshPhoenix.Form` (changeset + action metadata) is rebuilt on every diff, validation errors can never be shown (the form is thrown away), and change tracking on the whole row is defeated. | Build once in the LiveView: per-row forms in an assign map `%{step.id => to_form(...)}` rebuilt only when rows change; `to_form(%{}, as: :scores)` in `mount`/`handle_params`; drop `:let`. |
| WEB-09 | Medium | html.md/AGENTS.md "Always use `<.form>` … **always** use `<.input>`" | Raw `<form>`: `live/admin/schools_live.ex:53`, `live/school/timetable_live.ex:182`, `members_live.ex:42,65`, `fees_live.ex:364,426,494,533`, `class_live.ex:138,174,244,276,305,324,358`, `discipline_live.ex:193,265,313`, `results_live.ex:100`, `bulletin_live.ex:122`, `register_live.ex:146,184`, `live/teacher/fiche_live.ex:449`, `marks_live.ex:466,476,560,570`, `marks_summary_live.ex:107`. Raw `<input>/<select>` (56): e.g. `class_live.ex:144,176-199,206-215,246-255,278-286,312,330,360-375`, `fees_live.ex:370-390,428-441,500-527,539-551`, `discipline_live.ex:267-293,320-328`, `register_live.ex:149-154,190-195`, `import_live.ex:66-82,192-233` | These forms have no `to_form` backing and no `<.input>` error slot, so bad input degrades to a generic flash (`fees_live.ex:87-88`) or a silent `{:noreply, socket}` (`fees_live.ex:90-92,131-133`, `class_live.ex:472-474,517-519`, `discipline_live.ex:91-93,130-132`, `register_live.ex:97-99`). Also loses the default focus/error styling. | `to_form(%{}, as: :tranche)` etc. assigned in mount; `<.form for={@tranche_form} id=...>` + `<.input field={@tranche_form[:amount]} type="number">`; return parse errors as `errors:` on the form instead of dropping them. The small `phx-change` select wrappers (period/seq selectors) can stay raw but should be one shared component (WEB-30). |
| WEB-10 | Medium | Phoenix.Component: declare `attr`s; don't spread all assigns | `live/onboarding/setup_wizard_live.ex:65,67,69,71` (`<.year_panel {assigns} />`, `<.classes_panel {assigns} />`, …), panels at `:466,499,530,604` declare no `attr` | Passing the whole assigns map (incl. `@flash`, `@current_scope`, `@socket`…) into a function component defeats change tracking for the entire panel and hides which assigns each panel needs. | Declare `attr`s and pass only them (`<.year_panel year_form={@year_form} />`). |
| WEB-11 | Low | html.md "unique DOM IDs on key elements (forms, buttons)" | Submit/primary buttons without id: `setup_wizard_live.ex:522,588,592,638,668`; `classes_live.ex:134`; `members_live.ex:129`; `settings_live.ex:70,128,146,213,266,322`; `periods_live.ex:83`; `fees_live.ex:392,443,528,553`; `class_live.ex:201,317,376`; `discipline_live.ex:295,329`; `register_live.ex:156`; `import_live.ex:234` (row delete); `fiche_live.ex:462,494,606,621`; `roster_live.ex:267`. List rows without id: `enroll_import_live.ex:64`, `class_live.ex:217`, `school/dashboard_live.ex:121`, `marks_summary_live.ex:136` | Tests must fall back to text matching for these (see WEB-37). | Add ids (`id="fees-add-submit"`, `id={"import-row-delete-#{@i}"}`…). |
| WEB-12 | Low | AGENTS.md "Never write inline `<script>`"; JS/CSS "import vendor deps into app.css"; "cannot reference an external … link href in the layouts" | `components/layouts/root.html.heex:12-17` (Google Fonts `<link>`), `components/layouts/auth.html.heex:16-145` (`<style>` block) + ~40 inline `style="…"` (`:150-229`), `controllers/page_html/home.html.heex:7-17` (`<style>`) + inline `style=` on nearly every element of 680 lines | Landing and auth pages bypass Tailwind/daisyUI and app.css entirely (hard-coded hex palette, fonts, focus rings) and depend on a third-party font CDN (offline classrooms, GDPR). The `.ta-landing`/`.ta-auth-paper` scoping idea is fine; the delivery isn't. | Move the rules into `app.css` under `.ta-landing`/`.ta-auth-paper`; self-host Fraunces/Libre Franklin/Plex Mono in `priv/static/fonts` (already in `static_paths`); replace inline `style=` with utilities. |
| WEB-13 | Low | HEEx: keep logic out of templates | `components/layouts/auth.html.heex:14-15` (`<% assigns = assign(assigns, …) %>`); inline `<% x = … %>` bindings `live/school/my_timetable_live.ex:72`, `timetable_live.ex:180`, `register_live.ex:179`, `fees_live.ex:464`, `discipline_live.ex:312` | Assign mutation inside a layout template; per-cell bindings in `:for` loops recompute on every diff. | Compute `auth_copy`/`auth_points` in `Layouts.auth/1` (a wrapper function) and pre-join rows (`%{row, balance}`) in the LiveView. |
| WEB-14 | Low | i18n / correctness | `components/layouts/root.html.heex:2` `lang="en"`; print templates `bulletin_print_html/show.html.heex:2`, `fiche_print_html/show.html.heex:2`, `timetable_print_html/show.html.heex:2` `lang="fr"` | Default locale is `fr` (`plug/locale.ex:9`) but the app root declares English; print pages hard-code French even for EN users. | `<html lang={@conn.assigns[:locale] \|\| "fr"}>` (root layout has `@conn`); use `Gettext.get_locale/1` in print templates. |
| WEB-15 | Low | data quality in UI | `live/school/discipline_live.ex:239` renders `sanction.issued_by_user_id` (a UUID) in the "Émis par" column | Shows a raw id to head teachers. | Preload the issuer and show email/name. |

### 3.3 Forms (AshPhoenix)

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-16 | High | ash_phoenix/form_integration: submit through `AshPhoenix.Form.submit`; positional args/`prepare_source` for server-controlled values; elixir.md "don't `String.to_atom` on user input" (`to_existing_atom` still raises) | Scaffold forms whose submit bypasses the form: `live/teacher/log_live.ex:45-68,74-82`; `setup_live.ex:33-64,66-77`; `roster_live.ex:47-61,68-99`; `fiche_live.ex:189-203,335-339`; `marks_live.ex:197-201`; `setup_wizard_live.ex:434-442`; `members_live.ex:284-292`. Crash sites on unexpected input: `log_live.ex:55` (`String.to_existing_atom(p["status"])`), `:54` (`Decimal.new/1`), `roster_live.ex:89`, `setup_live.ex:29,49`, `import_live.ex:374`, `setup_wizard_live.ex:396,405`, `members_live.ex:308,317`, `create_school_live.ex:61,85`, `lesson_plan_live.ex:65` | The AshPhoenix form only renders fields; on submit the LiveView reparses `params` by hand and calls a domain function, so resource validations/errors never reach the template, and any value outside the `<select>` options (trivial to send) raises `ArgumentError` → LiveView crash + reconnect. `fiche_live.ex:301-330` and `discipline_live.ex:18,135-142`, `fees_live.ex:11,267-274`, `attendance_live.ex:13,146-148` already show the safe whitelist pattern — it just isn't applied consistently. | Give the orchestration to the resource (custom `create` action with `change`/`after_action`, or an `Ash.Resource.Change`) so `AshPhoenix.Form.submit` can be used end-to-end; where a domain function must stay, whitelist enums via `Ash.Type.Enum` `match/1` or a `@map` and return `{:error, field}` into the form with `AshPhoenix.Form.add_error/2` (as `log_live.ex:33-39` already does for `hours`). |
| WEB-17 | Medium | ash_phoenix/error_handling: handle `{:error, …}`; never crash the LiveView | `{:ok, _} =` / `:ok =` inside handlers: `live/admin/schools_live.ex:81,94`; `live/teacher/lesson_plan_live.ex:10,46,65,74`; `import_live.ex:266`; `live/school/periods_live.ex:124`; `timetable_live.ex:104,107`; `class_live.ex:480,574,580,646`; `members_live.ex:201`; `controllers/fiche_print_controller.ex:14`. Partial `case`: `members_live.ex:183-186` and `setup_wizard_live.ex:358-361` only match `{:error, :already_member}` | Any other error (policy, DB, validation) becomes a `MatchError`/`CaseClauseError` and kills the LiveView process instead of a flash. | `case … do {:ok, _} -> …; {:error, _} -> put_flash(…)` (pattern already used in most of `fiche_live.ex`). |
| WEB-18 | Low | ash_phoenix/form_integration (validate on change) | `live/school/fees_live.ex:426-444`, `class_live.ex:174-202,358-378`, `discipline_live.ex:265-296`, `register_live.ex:184-212` | Submit-only raw forms — no `phx-change="validate"`, no inline errors, no `phx-debounce`. | Falls out of WEB-09. |

### 3.4 LiveView state & data loading

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-19 | High | Function components must be pure/cheap; load data in `mount`/`on_mount` | `components/layouts.ex:41-53` (`Curriculum.list_units_for_scope/1`, `Organization.list_workspaces_for/1`) and `:67-75` (`Permissions.head?/admin?`) inside `Layouts.app/1` | `<Layouts.app>` wraps every LiveView render, so **two DB queries run on every diff of every page** — every keystroke in a `phx-change` form (`fiche-header-form` autosave, marks `preview`, wizard `validate_*`) re-queries units and workspaces. | Load `units`/`workspaces`/role flags once in `LiveUserAuth.on_mount/4` (they depend only on the scope) and read them from assigns in the layout (`assigns[:units]`), or memoise in the `Scope` struct. |
| WEB-20 | Medium | liveview.md: mount for static data, `handle_params` for URL-driven data (don't load twice) | `live/teacher/marks_live.ex:25-56,63-90` (mount) **and** `:375-409` (handle_params) both load assessments/marks/sibling scores; `marks_summary_live.ex:29` + `:42` (`assign_summary` twice); `live/school/results_live.ex:27` + `:35` (`class_results_for_period` + `list_roster` twice); `discipline_live.ex:40` + `:56`; `register_live.ex:22` + `:78` (`class_register` + per-student `student_conduct` loop twice); `bulletin_live.ex:32-35` + `:68-88` | Every param-driven page does its heaviest queries twice on first render. | Keep only scope/class resolution in `mount`; do all period/seq/date-dependent loading in `handle_params`. |
| WEB-21 | Medium | ecto.md preload/aggregate; avoid N+1 | `live/school/dashboard_live.ex:146-156` (`list_roster` and `list_assignments_for_class` per class only to count); `classes_live.ex:200-202` (`list_roster` per class for `effectif`); `live/teacher/dashboard_live.ex:16-18,44-55` (`coverage_for_plan` + `get_course` + `contexts_of_course!` per plan); `fiche_live.ex:168-172` (`get_lesson_plan_for_entry` per entry, re-run by `assign_modules` after **every** event `:34,47,58,74,86,97-98,120,130,141,153`); `log_live.ex:11` (`list_progression_entries!` per plan); `register_live.ex:56-66` (`student_conduct` per student, ×2 per WEB-20); `class_live.ex:401-405` (`combinable_siblings` per assignment); `members_live.ex:319-329` (`list_pending_invitations`/`list_members` refetched to find one row) | Query count scales with classes × students on dashboards and with entries on every fiche edit. | Ash aggregates/counts (`count_of_students` on ClassGroup, `has_lesson_plan` calc on ProgressionEntry), a single `class_conduct(cg, period)` map (already exists: `Attendance.class_conduct/2` used by the print controller), and `Ash.get` by id instead of list+find. |
| WEB-22 | Medium | liveview.md "**Always** use LiveView streams for collections" | `grep "stream("` → **0** LiveViews. Plain-list assigns re-rendered whole on each event: class roster `live/school/class_live.ex:391` (+ `load_roster/1` after every action `:418,454,471,481,504,527,546,561,608,651`), balances/roster `fees_live.ex:24,463,491`, members/invitations `members_live.ex:298-299`, sanctions `discipline_live.ex:167`, import rows (≤300) `live/teacher/import_live.ex:271,143-163`, students `marks_live.ex:33,71`, `roster_live.ex:35` | Judgement: Cameroon class sizes (≤ ~120) keep memory bounded, so this is not a runtime-termination risk; the cost is full-table re-render + diff on every click and the `load_roster` refetch pattern. Small lists (sequences, periods, tranches, KPIs) are fine as assigns. | Use streams for the class roster, fee balances, members, sanctions log and import rows (`stream_insert`/`stream_delete` after each mutation instead of `load_roster`); keep counts in separate assigns. `CoreComponents.table/1` already supports `LiveStream` rows but is unused. |
| WEB-23 | Low | liveview.md "phx-hook that manages its own DOM must set `phx-update="ignore"`" | `live/teacher/fiche_live.ex:431` `<div id="fiche-modules" phx-hook="ModuleLayout">` with no `phx-update`; `assets/js/hooks/module_layout.js:35-43` re-creates Sortables in `updated()` to survive morphdom | SortableJS moves DOM nodes; the server then re-renders the same tree from `apply-layout`. It works because the hook rebinds on `updated()`, but a patch arriving mid-drag will reorder under the user's cursor, and the rule is explicit. | Render modules/entries with `phx-update="stream"` (ids already exist: `module-#{id}`, `entry-#{id}`) and `stream` reset after `apply-layout`, or isolate the sortable container under `phx-update="ignore"` and drive membership via `push_event`. |
| WEB-24 | Low | permissions must be evaluated at action time | `live/school/class_live.ex:27-38` (`admin?`, `manage?: true`, link flags) and `:410,446,466,478` gate on `manage?` which is always `true`; `members_live.ex:14`, `settings_live.ex:22-23`, `fees_live.ex:22` snapshot roles at mount (though handlers there re-check `scope`) | Role changes during a session aren't seen; `manage?` is a dead flag that reads like a guard. | Derive from `scope` in handlers (as `settings_live.ex:345` does) or drop the dead flag; long-term WEB-01. |
| WEB-25 | Low | stale defaults | `live/teacher/setup_live.ex:8-13` (`"2025-2026"`, `"2025-09-08"`, `"2026-07-31"`), `import_live.ex:80` placeholder | Hard-coded academic year defaults; today is 2026-09-23. | Compute from `Date.utc_today()` (Sept–July window). |
| WEB-26 | Low | nit | `live/teacher/marks_live.ex:170` `Map.new(scores, fn {k, v} -> {k, v} end)` | Identity map. | `assign(socket, :scores, scores)`. |

### 3.5 Components / duplication

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-27 | Medium | DRY; AGENTS.md "app-wide helpers in `html_helpers`" | Redefined private helpers: `presence/1` (5 files: `setup_wizard_live.ex:430`, `register_live.ex:116`, `discipline_live.ex:154`, `fees_live.ex:304`, `class_live.ex:666`); `blank_to/2` (5: `log_live.ex:70`, `roster_live.ex:138`, `fiche_live.ex:225`, `import_live.ex:395`, `enroll_import_live.ex:167`); `parse_decimal/1` (3: `setup_live.ex:103`, `fiche_live.ex:229`, `import_live.ex:381`); `parse_int/1` (2); `fmt/1` Decimal→2dp (5: `marks_summary_live.ex:81`, `results_live.ex:87`, `bulletin_live.ex:107`, `discipline_live.ex:181`, `controllers/bulletin_print_html.ex:9`); `parse_date/1` (2: `register_live.ex:33`, `attendance_live.ex:68`); `pick/2` (2); `default_period/1` (2); `authorized?/2` (4); `day_label/1` (3); `load_user/1` (8 controllers, WEB-02) | Same 3–8 line helpers copy-pasted with slightly different edge behaviour (`import_live.ex:381-386` `Decimal.parse` accepts trailing garbage, `fiche_live.ex:232-237` doesn't). | `TeacherAssistantWeb.Params` (presence/blank_to/parse_decimal/parse_int/parse_date), `TeacherAssistantWeb.Format` (fmt, fmt_hours, pct) imported via `html_helpers`. |
| WEB-28 | Medium | DRY components | Period selector `<form phx-change="select_period"><.input type="select" options=[Séquences/Trimestres/Année]>` copy-pasted in `live/school/results_live.ex:100-114`, `bulletin_live.ex:122-141`, `discipline_live.ex:193-207` (+ handlers `:37-59`, `:60-66`, `:58-63,158-176`); invite form + `parse_roles`/`parse_membership_status` duplicated `members_live.ex:107-131,302-317` vs `setup_wizard_live.ex:616-640,390-405` (comment at `:388` admits it); timetable grid table duplicated `my_timetable_live.ex:56-87` vs `timetable_live.ex:164-208` vs `controllers/timetable_print_html/show.html.heex`; print button `<a target="_blank" class="btn btn-primary btn-sm gap-2"><.icon name="hero-printer">` in `my_timetable_live.ex:37-45`, `timetable_live.ex:152-160`, `results_live.ex:214-222`, `bulletin_live.ex:142-153`, `lesson_plan_live.ex:112-120`; `fiche_live.ex:262-295` `quota_stat` near-duplicates `CoreComponents.stat/1` (`core_components.ex:541-559`); seq selector duplicated between `marks_live.ex:466-489` and `:560-583` (two render clauses) | Six copies of behaviour that will drift (e.g. `discipline_live.ex:163` keeps the previous period on invalid param, `results_live.ex:46` doesn't). | `<.period_select sequences terms value>` + a `PeriodParams` helper; `<.print_link href>`; `<.timetable_grid periods days grid>`; `<.invite_form>`; extend `stat/1` with `target`/`ratio`. |
| WEB-29 | Low | dead code | `components/layouts.ex:463-493` `theme_toggle/1` unused (docstring `:458-461` claims root layout applies theme before load — it doesn't; `app.js:39-41` does it after the deferred bundle → light-theme users get a dark flash); `mix.exs:68` `:cinder` + `app.css:5` `@source "../../deps/cinder"` with zero usages in `lib`; `CoreComponents.table/1`, `list/1`, `header/1` unused | Unused dep pulled into every build and scanned by Tailwind. | Remove `theme_toggle` or wire it (and add the inline theme-init the docstring promises — the one generator-sanctioned `<script>` in `root.html.heex`); drop `:cinder` unless the syllabus-library work will use it. |
| WEB-30 | Low | component size | `components/layouts.ex:37-374` `Layouts.app/1` is ~300 lines: workspace switcher, class switcher, three navs, user card, locale switch | Hard to test in isolation (`workspace_switcher_test.exs` greps raw HTML); `role_label/1` (`:403-407`) prints `String.replace(role, "_", " ")` — untranslated internal atom names ("form master"). | Split into `<.workspace_switcher>`, `<.class_switcher>`, `<.rail_nav>`; translate roles via `SchoolRole.label/1`. |

### 3.6 Assets / CSS / JS

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-31 | — | AGENTS.md Tailwind v4 import syntax; daisyUI; no `@apply` | `assets/css/app.css:4-19` | **Compliant**: `@import "tailwindcss" source(none)`, `@source` for css/js/lib, `@plugin "../vendor/heroicons"`, `@plugin "../vendor/daisyui" { themes: dark --default, light }`, LiveView loading variants, no `@apply` anywhere (grep 0). The theme is expressed via daisyUI color tokens (`:60-117`) so `btn-primary`/`badge-*` follow it. Only nit: `@source "../../deps/cinder"` (`:5`) for an unused dep. | Keep. |
| WEB-32 | — | AGENTS.md hooks in `assets/js`, registered in `LiveSocket` | `assets/js/app.js:25-27,47-51`, `assets/js/hooks/module_layout.js` | **Compliant**: colocated hooks + external `ModuleLayout` passed to `LiveSocket`; vendored `sortable.js`, `topbar.js`, `daisyui.js`. The grep hit `app.js:91 else if` is JavaScript, not Elixir — false positive. | — |
| WEB-33 | Low | see WEB-12 | landing/auth CSS | Landing (`home.html.heex`) and auth (`auth.html.heex`) carry their own `<style>` + inline styles outside `app.css`. | Move to `app.css`. |

### 3.7 i18n

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-34 | Medium | gettext catalog must be extracted/merged; bilingual FR/EN is a product requirement | `mix gettext.extract --check-up-to-date` → **fails** (`priv/gettext/default.pot` out of date); `priv/gettext/en/LC_MESSAGES/default.po` has **211 of 652** `msgstr ""` (untranslated); FR has 0 untranslated but only because ~half the msgids are already French | EN users see a third of the UI in French; new strings since the last extract aren't in the catalog at all. | `mix gettext.extract --merge`, translate EN, add `mix gettext.extract --check-up-to-date` to `precommit`. |
| WEB-35 | Medium | one source language for msgids | Mixed English/French msgids in the same files, e.g. `live/onboarding/setup_wizard_live.ex:55-56` ("Get started"/"Set up your school") vs `:107-138` ("Identité", "Récapitulatif", "Bon à savoir"); `live/school/classes_live.ex:47-51` (`"No active academic year"` next to `"L'année scolaire n'a pas encore été créée."`); `"Delete"` (`:93`) vs `"Supprimer"` (`periods_live.ex:94`); `"Save"` (`log_live.ex:122`) vs `"Enregistrer"` (`settings_live.ex:70`) | Translators get two half-catalogs; FR fallback for an untranslated EN msgid shows English to French users. | Standardise msgids on French (FR-first product, memory note), translate to EN. |
| WEB-36 | Low | everything user-facing through gettext | `auth_overrides.ex:105-192` (compile-time `set :button_text, "Se connecter"` etc.), `components/layouts.ex:509-513,527-572` (auth copy), `components/layouts/auth.html.heex:170-173,193`, `controllers/page_html/home.html.heex` (whole page), `controllers/auth_controller.ex:10-12,33-39,52` (English flashes: "You are now signed in", "Incorrect email or password"), `live/school/attendance_live.ex:211-213` (`status_short` "P/A/R" hard-coded while `register_live.ex:120-123` wraps the same letters in gettext), `layouts.ex:403-407` (role label) | Auth/landing/flash copy cannot switch language; AshAuthentication overrides are compile-time so they need a different mechanism. | gettext in Layouts/controllers; for AshAuthentication use `gettext_backend`-style overrides or render the auth forms via your own components. |

### 3.8 Tests

| ID | Sev | Rule | Location | What's wrong | Recommended fix |
|---|---|---|---|---|---|
| WEB-37 | Medium | liveview.md tests: "**Never** test against raw HTML, **always** use `element/2`, `has_element/2`"; "favor presence of key elements over text" | 261 `=~ "…"` assertions vs 218 `element/has_element?`. Examples: `test/teacher_assistant_web/components/workspace_switcher_test.exs:10-11` (`html =~ "id=\"workspace-switcher\""`), `live/school/class_live_test.exs:29,51` (`html =~ "Awa"`, `render(view) =~ "matricule"`), `live/auth_smoke_test.exs:17-24,42-46,54-55,62-63` (marketing copy + `~s(hidden)`), `locale_test.exs:21,26` ("Tableau de bord"/"Teacher dashboard"), `components/kit_test.exs:14-24` (asserts CSS class `"ta-num"`) | Copy changes (and the i18n cleanup in WEB-35) will break these; text regexes also can't distinguish hidden from visible content. | `assert has_element?(view, "#workspace-switcher-item-#{school.id}", "École Deux")`, `has_element?(view, "#roster-row-#{e.id}")`, etc. The DOM ids largely exist already; add the missing ones from WEB-11. |
| WEB-38 | Low | test seams shouldn't shape production code | `test/support/conn_case.ex:39-56` logs in by `put_session(:user_id, user.id)`; production fallbacks `conn.assigns[:current_user] \|\| load_user(get_session(conn, :user_id))` exist only for this (comment `controllers/school_invitation_controller.ex:63-65`) | Every controller carries a second auth path that AshAuthentication never uses. | Log in with `AshAuthentication.Plug.Helpers.store_in_session(conn, user)` in the helper, then delete the fallbacks (with WEB-02). |
| WEB-39 | Low | test hygiene | `live/auth_smoke_test.exs:2-8` self-described "temporary" smoke test asserting French copy and `hidden` class | Brittle by design. | Convert to `has_element?` on form ids or delete once WEB-36 lands. |
| WEB-40 | — | good | 291 tests, `async: true`, `render_submit`/`render_change` 145×, form ids used (`form("#enroll-form")`, `form("#marks-form")`), no `Process.sleep`/`Process.alive?`, controller tests for all four print/invitation controllers, isolation tests (`marks_isolation_test.exs`, `school_teaching_scope_test.exs`). | — |

### 3.9 Accessibility / mobile (at a glance)

| ID | Sev | Location | What's wrong | Recommended fix |
|---|---|---|---|---|
| WEB-41 | Low | Teacher pages use the responsive card/table pattern (`live/teacher/roster_live.ex:198-249`, `marks_summary_live.ex:177-226`, `lesson_plan_live.ex:211-305`) — good. School pages are wide daisyUI tables in `overflow-x-auto` (17 of 20 tables): `live/school/register_live.ex:161-217` (N period columns + inline justify forms), `class_live.ex:109-164,258-350` (inline `<select>`s per row), `fees_live.ex:317-415,450-487` | On a phone the head/censeur scrolls horizontally through forms embedded in cells; project is mobile-first. | Card rows on `< md` for register/class/fees (as the teacher side does), move per-row actions into a row menu. |
| WEB-42 | Low | Unlabelled controls: raw `<select>` `live/school/class_live.ex:144,182,246,312,330,360,363`, `discipline_live.ex:267,272`, `members_live.ex:71`, `timetable_live.ex:185`; search input `class_live.ex:206-215` (no `<label>`/`aria-label`); date input `register_live.ex:149` labelled by a `<span>` not `<label for>` | Screen readers announce "combo box" with no name. | Use `<.input label=…>` (fixes with WEB-09) or `aria-label`. Icon-only buttons are already labelled (`lesson_plan_live.ex:276,287,298`, `fiche_live.ex:445,460,465`, attendance toggles `attendance_live.ex:309-318` with `aria-pressed`). |
| WEB-43 | Low | `components/layouts.ex:113-117,160-164` dropdown triggers are `<div tabindex="0" role="button">` without `aria-haspopup`/`aria-expanded` | daisyUI idiom; keyboard works, state isn't announced. | Add `aria-haspopup="menu"` or switch to `<details>`. |

### 3.10 Controllers / print pages

| ID | Sev | Location | What's wrong | Recommended fix |
|---|---|---|---|---|
| WEB-44 | Low | Print templates (`controllers/bulletin_print_html/show.html.heex:7-42`, `fiche_print_html/show.html.heex:9-31`, `timetable_print_html/show.html.heex:7-…`) each carry a near-identical `<style>` block; rendered with `put_layout(false)`/`put_root_layout(false)` (correct for print) | CSS duplicated three times; `lang="fr"` hard-coded (WEB-14). | One `print.css` (or a `@layer` in `app.css` linked from a tiny `print` root layout). Otherwise the print controllers are clean: `with` chains, ownership checks, `Enrollment.form_master`, and `BulletinPrintController` correctly reuses `Attendance.class_conduct/2` + `Discipline.class_discipline/2` (the batched calls the LiveViews should also use, WEB-21). |
| WEB-45 | Low | `controllers/school_invitation_html/show.html.heex:1` passes `current_scope={assigns[:current_scope]}` (always `nil` — the controller never assigns it) | Invitation page always renders the logged-out header even for a signed-in user (`school_invitation_controller.ex:24-29` assigns `current_user` but not a scope). | Assign the scope (WEB-02 plug). |

## 4. LiveView size table

| File | Lines | `handle_event` | `handle_params`/`handle_info` | Notable |
|---|---|---|---|---|
| live/onboarding/setup_wizard_live.ex | 675 | 7 | 0 | 4 panels as function components fed `{assigns}` (WEB-10); 3 forms; manual `Permissions` per event; `to_existing_atom` on roles |
| live/teacher/marks_live.ex | 672 | 5 | 1 | Two full `render/1` clauses (solo/combined) duplicating the toolbar; double load mount+params; unsaved-edit stash across `push_patch` (nice) |
| live/school/class_live.ex | 669 | 12 | 0 | 7 raw `<form>`s inside table cells; `load_roster/1` after every event; `manage?` always true; `:ok =`/`{:ok,_} =` crashes |
| live/school/settings_live.ex | 651 | 14 | 0 | Largest handler count; 5 AshPhoenix forms done right (`prepare_source`) + one inline per-row form (`:236`); upload handling |
| live/teacher/fiche_live.ex | 630 | 11 | 0 | Sortable hook (WEB-23); forms built in template incl. `:let` (WEB-08); `assign_modules` N+1 per event |
| live/school/fees_live.ex | 613 | 10 | 0 | All forms raw `<form>`/`<input>` (WEB-09); good whitelist parsing; per-student payment/adjustment forms rendered for every roster row |
| live/teacher/import_live.ex | 419 | 6 | 0 | Upload + review; `for={%{}}` forms; rows capped at 300 (good); `{:ok,…} = FicheParser.parse` crash path |
| live/school/discipline_live.ex | 345 | 4 | 1 | Period selector dup; raw forms; renders `issued_by_user_id` |
| live/school/attendance_live.ex | 332 | 2 | 0 | Clean: whitelist statuses, two render clauses share `roster_list/1`, `operating_allowed?` gate |
| live/school/members_live.ex | 330 | 5 | 0 | Invite form dup with wizard; `find_membership` refetches list per event; partial `case` |
| live/teacher/lesson_plan_live.ex | 327 | 5 | 0 | `step_form(s)` ×6 per row in template; `{:ok,_} =` in 3 handlers; autosave via `phx-change` + `phx-debounce="blur"` |
| live/school/bulletin_live.ex | 294 | 1 | 2 | Double load; period selector dup |
| live/teacher/roster_live.ex | 279 | 5 | 0 | Responsive table pattern (good); scaffold forms; read-only guard clause via function head (nice) |
| live/teacher/dashboard_live.ex | 253 | 0 | 0 | N+1 `coverage_for_plan`/`get_course` per plan |
| live/teacher/marks_summary_live.ex | 251 | 1 | 1 | Double `assign_summary`; responsive table |
| live/school/classes_live.ex | 236 | 3 | 0 | `list_roster` per class for effectif; proper `AshPhoenix.Form` w/ `prepare_source` |
| live/school/results_live.ex | 229 | 1 | 1 | Double `select_period`; period selector dup |
| live/school/register_live.ex | 228 | 3 | 1 | `student_conduct` per student ×2; raw forms |
| live/school/timetable_live.ex | 225 | 1 | 0 | One raw `<form>` per cell (days × periods); `:ok =` on clear |
| live/school/periods_live.ex | 214 | 3 | 0 | Per-row inline `for_update` form; `:ok = build_default_periods` |
| live/teacher/setup_live.ex | 206 | 2 | 0 | Scaffold form; hard-coded 2025 defaults; `to_existing_atom` |
| live/onboarding/create_school_live.ex | 200 | 2 | 0 | Correct `prepare_source` + `Form.submit`; `to_existing_atom` for profile enums |
| live/school/dashboard_live.ex | 182 | 0 | 0 | N+1 counts |
| live/school/enroll_import_live.ex | 181 | 3 | 0 | `for={%{}}` form; preview rows without ids |
| live/teacher/log_live.ex | 143 | 2 | 0 | Scaffold form; `Decimal.new`/`to_existing_atom` crash path; `add_error` pattern (good) |
| live/teacher/coverage_live.ex | 134 | 0 | 0 | Clean read-only page |
| live/admin/schools_live.ex | 110 | 2 | 0 | Raw `<form>`; `{:ok,_} =`; no actor |
| live/school/my_timetable_live.ex | 94 | 0 | 0 | Grid dup with timetable_live |

Top 10 by size: setup_wizard (675), marks (672), class (669), settings (651), fiche (630), fees (613), import (419), discipline (345), attendance (332), members (330). Also large non-LiveView: `components/layouts.ex` 574, `core_components.ex` 626, `page_html/home.html.heex` 680.

## 5. Things done well

- **Layout/scope discipline**: 27/27 LiveViews start with `<Layouts.app flash={@flash} current_scope={@current_scope}>`; `current_scope` comes from one `on_mount` (`live_user_auth.ex:88-103`) with per-`live_session` gates (`:require_teaching_scope`, `:require_school_setup`, `:require_operator`) and `session_context/1` carrying workspace/context/locale; no `current_scope` bugs found.
- **Zero compile warnings**, no deprecated APIs (`live_redirect`/`live_patch`/`phx-update="append"`/`~E`/`Heroicons.` all 0 hits), no LiveComponents, no inline scripts in LiveView templates, `<.icon>` used exclusively, `<%!-- --%>` comments, class lists always `[...]`, `:for`/`:if` everywhere (one `<%= for %>` in core_components is the sanctioned form).
- **URL-driven state**: seq/period/date/assessment live in the URL via `push_patch` + `handle_params` (`marks_live.ex:149-160,375-409`, `results_live.ex:34-40`, `register_live.ex:75-84`), so pages are bookmarkable; `marks_live.ex:376-418` preserves unsaved marks across a selector change.
- **AshPhoenix done right where it's used**: `prepare_source` for server-controlled ids (`classes_live.ex:217-228`, `settings_live.ex:624-650`, `setup_wizard_live.ex:448-459`, `create_school_live.ex:36-47`, `marks_live.ex:213-224`), `validate` on `phx-change`, `{:error, form}` reassigned (`create_school_live.ex:25-33`, `settings_live.ex:357-362`), `AshPhoenix.Form.add_error/2` for a UI-only rule (`log_live.ex:27-40`).
- **Input hardening patterns exist**: whitelist maps for enums (`discipline_live.ex:18,135-142`, `fees_live.ex:11,267-274`, `attendance_live.ex:13,146-148`, `timetable_live.ex:131-134`), safe return_to (`teacher_context_controller.ex:22-27`), logo path traversal guard (`school_logo_controller.ex:27-36`), upload limits (`import_live.ex:6,27`, `settings_live.ex:27-31`), verification gate on writes (`marks_live.ex:174`, `attendance_live.ex:159`, `bulletin_print_controller.ex:42`).
- **Mobile-first on the teacher side**: responsive card/table rows (`roster_live.ex`, `marks_summary_live.ex`, `lesson_plan_live.ex`), 44px tap targets and `inputmode` on mark inputs (`marks_live.ex:648-661`), one-tap attendance toggles with `aria-pressed` (`attendance_live.ex:300-331`), daisyUI drawer sidebar with `aria-label`s and `aria-current="page"` (`layouts.ex:85-111,386`), sticky toolbar.
- **Assets**: `app.css` follows the Tailwind v4/daisyUI contract exactly, theme expressed as daisyUI tokens with a `prefers-reduced-motion` block; hooks vendored and registered properly; keyboard fallback for drag-and-drop with a live region (`module_layout.js:59-93`).
- **Print**: dedicated controllers with ownership/role checks, layout-less A4 templates, batched `class_conduct`/`class_discipline` loads.
- **Tests**: 291 tests, `async: true`, forms driven by ids + `render_submit/render_change`, controller tests for every controller, isolation/scope tests, no sleeps.
