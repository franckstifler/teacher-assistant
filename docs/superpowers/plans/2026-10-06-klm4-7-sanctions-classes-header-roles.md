# KLM4–7 — Sanctions page, class size, official header, rights matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four small increments on one branch: the SG's school-wide « Sanctions » page (KLM4), maximum class
size, class naming rule and one-query enrolment counts (KLM5), an editable official header with signature
and stamp images (KLM6), and a read-only rights matrix (KLM7).

**Architecture:** Each increment is a block of tasks that ends green on its own. KLM4 adds a paginated
`SanctionEntry :school_list` read and `SanctionsLive`, and moves the « types in use » check into
`Discipline.add_sanction/3`. KLM5 adds two profile fields, a `ClassGroup.enrollment_count` aggregate and a
pure `SchoolTemplates.next_class_label/3`. KLM6 adds three profile fields behind a head-only action, two
bulletin elements, a `kind` parameter on the logo controller and `OfficialHeaderLive`. KLM7 adds
`SchoolRole.rights/0` (checked against the real policies by a test) and `RolesLive`.

**Tech Stack:** Phoenix 1.8 LiveView (uploads), Ash 3.33 (aggregates, policies), AshPostgres, Gettext.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"KLM4", §"KLM5", §"KLM6", §"KLM7".

## Global Constraints

- Worktree `.claude/worktrees/klm4-7`, branch `klm4-7-sanctions-classes-header-roles` (the user asked to batch
  KLM4–7 on one branch), `MIX_TEST_PARTITION=3` for every `mix test`. Stage explicit paths only.
- Migrations: `mix ash.codegen --dev` while iterating; one named `mix ash.codegen klm4_7_classes_header` in
  Task 8; read it (new columns only); `mix ash.codegen --check` clean at the end.
- KLM4: page on the `:conduct` axis; paginated by 50; filters class, type, « À notifier »; quick entry offers
  the **types in use** only, and `Discipline.add_sanction/3` itself refuses a type not in use
  (`{:error, :type_not_in_use}`); Surveillant menu badge = this year's sanctions whose parents are not yet
  notified.
- KLM5: `max_class_size` integer 1..200, nullable (no limit); `class_suffix` enum `:letters | :numbers`,
  default `:letters`; over the limit is a **warning, never a block**; the message is « La classe dépasse
  l'effectif maximum (60) »; the count shows « 68 / 60 ».
- KLM6: `official_header_lines` list of strings, at most 6, each ≤ 120 characters, nil = today's generated
  lines; `signature_path`, `stamp_path` stored like `logo_path`; **head** axis only; PNG or JPEG ≤ 1 MB;
  served at `/school/logo?kind=signature|stamp`, members only; bulletin elements « Signature » and « Cachet »
  on by default, printed only when an image exists.
- KLM7: admin axis; « Les droits suivent le rôle ; ils ne sont pas modifiables pour l'instant. »
- Strings through gettext; after `mix gettext.extract --merge`, fill new `en` msgstr, clear new fuzzy flags.
- `mix precommit` before the last commit.

## Review Focus

1. A sanction type switched off in KLM2 sent through `Discipline.add_sanction/3` from any page — refused,
   nothing written (test in Task 1).
2. The « À notifier » filter combined with a class filter, then « Marquer les parents notifiés » on the
   selected row — the row leaves the filtered list and the menu badge drops by one (test in Task 2).
3. Enrolling the 61st student of a class limited to 60 — enrolled, with the over-capacity message; no limit
   set → no message (test in Task 4).
4. Suggesting a label when the level already has « 6ème A » and « 6ème C » — the next free is « 6ème B »,
   never a duplicate (test in Task 3).
5. A Censeur (admin, not head) posting a header or signature change — refused by policy (test in Task 5).

---

### Task 0: Worktree

- [ ] **Step 1**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/klm4-7 -b klm4-7-sanctions-classes-header-roles main
cd .claude/worktrees/klm4-7 && mix deps.get
MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/discipline_live_test.exs
```

Expected: 0 failures.

---

## KLM4 — School-wide sanctions page

### Task 1: Sanctions data — school list, parents-to-notify count, types in use enforced

**Files:**
- Modify: `lib/teacher_assistant/academics/sanction_entry.ex` (read `:school_list`)
- Modify: `lib/teacher_assistant/discipline.ex` (`list_school_sanctions/3`, `count_parents_to_notify/2`,
  types-in-use check in `add_sanction/3`, `require Ash.Query`)
- Test: `test/teacher_assistant/discipline_school_sanctions_test.exs`

**Interfaces:**
- Produces:
  - `Discipline.list_school_sanctions(scope, %AcademicYear{}, opts) :: %Ash.Page.Offset{}` — opts
    `class_group_id`, `type` (atom), `to_notify` (boolean), `offset`; results newest first, each with
    `enrollment: %{class_group, student: %{primary_guardian_link: %{guardian}}}` loaded;
  - `Discipline.count_parents_to_notify(scope, %AcademicYear{}) :: non_neg_integer`;
  - `Discipline.add_sanction/3` returns `{:error, :type_not_in_use}` for a type outside
    `Attendance.school_life_rules(scope).sanction_types_in_use`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.DisciplineSchoolSanctionsTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Discipline, Enrollment, Organization}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg_a, cg_b | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg_a, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg_b, %{full_name: "Bob", sex: :m})
    [%{enrollment: awa}] = Enrollment.list_roster(scope, cg_a)
    [%{enrollment: bob}] = Enrollment.list_roster(scope, cg_b)
    %{scope: scope, year: year, cg_a: cg_a, awa: awa, bob: bob}
  end

  test "the school list filters by class, type and parents to notify, newest first", ctx do
    {:ok, s1} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :avertissement, date: ~D[2025-09-10]})
    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :blame, date: ~D[2025-09-12]})
    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.bob, %{type: :consigne, date: ~D[2025-09-11]})
    {:ok, _} = Discipline.mark_parents_notified(ctx.scope, s1)

    page = Discipline.list_school_sanctions(ctx.scope, ctx.year, [])
    assert page.count == 3
    assert Enum.map(page.results, & &1.type) == [:blame, :consigne, :avertissement]
    assert hd(page.results).enrollment.student.full_name == "Awa"

    assert [%{type: :consigne}] =
             Discipline.list_school_sanctions(ctx.scope, ctx.year, type: :consigne).results

    assert [_, _] =
             Discipline.list_school_sanctions(ctx.scope, ctx.year, class_group_id: ctx.cg_a.id).results

    assert [%{type: :blame}] =
             Discipline.list_school_sanctions(ctx.scope, ctx.year,
               class_group_id: ctx.cg_a.id,
               to_notify: true
             ).results

    assert Discipline.count_parents_to_notify(ctx.scope, ctx.year) == 2
  end

  test "a type switched off is refused wherever the sanction comes from", ctx do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{sanction_types_in_use: [:avertissement]},
        scope: ctx.scope
      )
      |> Ash.update()

    assert {:error, :type_not_in_use} =
             Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :blame, date: ~D[2025-09-10]})

    assert Discipline.list_school_sanctions(ctx.scope, ctx.year, []).count == 0
    assert {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :avertissement, date: ~D[2025-09-10]})
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/discipline_school_sanctions_test.exs`
Expected: FAIL — `Discipline.list_school_sanctions/3 is undefined`.

- [ ] **Step 3: The read**

In `sanction_entry.ex` `actions do`, after `read :parents_to_notify`:

```elixir
    # Spec KLM4: the SG's school-wide list, newest first, paginated.
    read :school_list do
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :class_group_id, :uuid
      argument :type, TeacherAssistant.Academics.SanctionType
      argument :to_notify, :boolean, default: false

      pagination offset?: true, countable: true, required?: false, default_limit: 50

      filter expr(enrollment.academic_year_id == ^arg(:academic_year_id))
      filter expr(is_nil(^arg(:class_group_id)) or enrollment.class_group_id == ^arg(:class_group_id))
      filter expr(is_nil(^arg(:type)) or type == ^arg(:type))
      filter expr(^arg(:to_notify) == false or is_nil(parents_notified_on))

      prepare build(
                sort: [date: :desc, inserted_at: :desc],
                load: [enrollment: [:class_group, student: [primary_guardian_link: :guardian]]]
              )
    end
```

- [ ] **Step 4: Domain functions**

In `discipline.ex`: add `require Ash.Query` under `use Ash.Domain`; then, after `list_sanctions/3`:

```elixir
  @doc "Spec KLM4: one page (50) of `year`'s sanctions, newest first; opts class_group_id, type, to_notify, offset."
  def list_school_sanctions(%Scope{} = scope, %AcademicYear{id: year_id}, opts) do
    SanctionEntry
    |> Ash.Query.for_read(
      :school_list,
      %{
        academic_year_id: year_id,
        class_group_id: opts[:class_group_id],
        type: opts[:type],
        to_notify: opts[:to_notify] == true
      },
      scope: scope
    )
    |> Ash.read!(page: [limit: 50, offset: opts[:offset] || 0, count: true])
  end

  @doc "Spec KLM4: `year`'s sanctions whose parents are not yet notified (menu badge)."
  def count_parents_to_notify(%Scope{} = scope, %AcademicYear{id: year_id}) do
    SanctionEntry
    |> Ash.Query.filter(is_nil(parents_notified_on) and enrollment.academic_year_id == ^year_id)
    |> Ash.count!(scope: scope)
  end
```

In `add_sanction/3`, after `with :ok <- validate_type(type)` add a second clause
`:ok <- in_use(scope, type)`, and:

```elixir
  # Spec KLM2/KLM4: a type the school switched off is refused, whatever the page.
  defp in_use(scope, type) do
    if type in TeacherAssistant.Attendance.school_life_rules(scope).sanction_types_in_use,
      do: :ok,
      else: {:error, :type_not_in_use}
  end
```

Update its `@doc` with « Rejects a type not in use (spec KLM2) with `{:error, :type_not_in_use}`. »

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/discipline_school_sanctions_test.exs test/teacher_assistant_web/live/school/discipline_live_test.exs test/teacher_assistant/academics/school_life_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/sanction_entry.ex lib/teacher_assistant/discipline.ex \
  test/teacher_assistant/discipline_school_sanctions_test.exs
git commit -m "feat: school-wide sanction list; types in use enforced in add_sanction"
```

---

### Task 2: The « Sanctions » page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/sanctions_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex`, `lib/teacher_assistant_web/spaces.ex`
- Test: `test/teacher_assistant_web/live/school/sanctions_live_test.exs`, `test/teacher_assistant_web/spaces_test.exs`

**Interfaces:**
- Consumes: Task 1; `Enrollment.list_school_students/3` (KLM1, for the student search);
  `Attendance.school_life_rules/1`; `Discipline.add_sanction/3`, `mark_parents_notified/2`,
  `delete_sanction/2` (code interface, `scope:` opt); `Accounts.list_members/1` (issuer names).
- Produces: route `/school/sanctions` (`School.SanctionsLive`); nav id `nav-school-sanctions` with badge
  `facts[:parents_to_notify]`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.SanctionsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Discipline, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    [cg_a, cg_b | _] = Enrollment.list_class_groups(scope, year)
    {:ok, awa} = Enrollment.add_student(scope, cg_a, %{full_name: "Awa Nkolo", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg_b, %{full_name: "Bob Eyong", sex: :m})
    [%{enrollment: awa_e}] = Enrollment.list_roster(scope, cg_a)
    [%{enrollment: bob_e}] = Enrollment.list_roster(scope, cg_b)
    {:ok, _} = Enrollment.add_guardian(scope, awa, %{full_name: "Jean Nkolo", relationship: :pere, phone: "677123456"})
    {:ok, s1} = Discipline.add_sanction(scope, awa_e, %{type: :blame, date: ~D[2025-09-12], reason: "Insolence"})
    {:ok, _} = Discipline.add_sanction(scope, bob_e, %{type: :consigne, date: ~D[2025-09-11]})
    %{cg_a: cg_a, awa_e: awa_e, s1: s1}
  end

  test "lists the year's sanctions and filters them", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sanctions")
    rows = view |> element("#sanction-rows") |> render()
    assert rows =~ "Awa Nkolo" and rows =~ "Bob Eyong"
    assert rows =~ "À notifier"

    {:ok, view, _} = live(conn, ~p"/school/sanctions?class=#{ctx.cg_a.id}")
    refute view |> element("#sanction-rows") |> render() =~ "Bob Eyong"

    {:ok, view, _} = live(conn, ~p"/school/sanctions?type=consigne")
    refute view |> element("#sanction-rows") |> render() =~ "Awa Nkolo"
  end

  test "the panel shows the guardian; notifying removes the row from « À notifier »", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sanctions?notify=1&class=#{ctx.cg_a.id}")
    view |> element("#sanction-#{ctx.s1.id}") |> render_click()

    panel = view |> element("#sanction-panel") |> render()
    assert panel =~ "Jean Nkolo"
    assert panel =~ "tel:677123456"
    assert panel =~ "Insolence"

    view |> element("#notify-#{ctx.s1.id}") |> render_click()
    refute has_element?(view, "#sanction-#{ctx.s1.id}")
    assert Discipline.count_parents_to_notify(ctx.scope, ctx.year) == 1
  end

  test "quick entry: search a student, pick a type in use, save", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sanctions")

    view |> form("#student-search", %{"q" => "awa"}) |> render_change()
    view |> element("#pick-#{ctx.awa_e.id}") |> render_click()
    view |> element("#type-avertissement") |> render_click()

    view
    |> form("#sanction-entry", %{"entry" => %{"reason" => "Retards", "date" => "2025-09-15"}})
    |> render_submit()

    assert Discipline.list_school_sanctions(ctx.scope, ctx.year, type: :avertissement).count == 1
  end

  test "types switched off are not offered", %{conn: conn, scope: scope} do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{sanction_types_in_use: [:blame]}, scope: scope)
      |> Ash.update()

    {:ok, view, _} = live(conn, ~p"/school/sanctions")
    assert has_element?(view, "#type-blame")
    refute has_element?(view, "#type-consigne")
  end

  test "a plain teacher is sent back", %{workspace: ws, scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/sanctions")
  end
end
```

(`register_and_log_in_user` binds `scope` with the active year and seeded starter classes; if
`list_class_groups/2` returns fewer than two classes, create two with `Enrollment.create_class_group/3`. The
`year` binding is available as `ctx.year`.)

In `spaces_test.exs`, the Surveillant list becomes day, absences, conduct, **sanctions**, classes, students,
school-life (insert `"nav-school-sanctions"` after `"nav-school-conduct"`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/sanctions_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: FAIL — no route `/school/sanctions`.

- [ ] **Step 3: Route and menu**

Router, after `live "/school/conduct", …`: `live "/school/sanctions", School.SanctionsLive, :index`.

`spaces.ex`: in the Surveillant section insert `sanctions(facts[:parents_to_notify])` after `conduct()`;
helper beside `conduct/0`:

```elixir
  defp sanctions(to_notify),
    do: item("sanctions", gettext("Sanctions"), "hero-flag", ~p"/school/sanctions", to_notify)
```

In `counts(:surveillant, scope)` add to the returned map:

```elixir
      parents_to_notify:
        case scope.current_academic_year do
          nil -> 0
          year -> Discipline.count_parents_to_notify(scope, year)
        end
```

(alias `TeacherAssistant.Discipline` at the top of `spaces.ex` if it is not already there).

- [ ] **Step 4: The page**

```elixir
defmodule TeacherAssistantWeb.School.SanctionsLive do
  @moduledoc """
  SG → Sanctions (spec KLM4, L1): the year's sanctions with filters (class,
  type, parents to notify), a quick entry (student, type, reason) and a detail
  panel with the main guardian's phone and « Marquer les parents notifiés ».
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Attendance, Discipline, Enrollment}
  alias TeacherAssistant.Academics.{GuardianRelationship, Reference, SanctionType}
  alias TeacherAssistantWeb.Authz

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Discipline.can_manage_conduct?(scope) do
      {:ok,
       assign(socket,
         classes: Enrollment.list_class_groups(scope, scope.current_academic_year),
         types: Attendance.school_life_rules(scope).sanction_types_in_use,
         issuers: Map.new(Accounts.list_members(scope), &{&1.user_id, member_name(&1)}),
         q: "",
         matches: [],
         entry: %{enrollment: nil, type: nil},
         selected: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    filters = %{
      class: Enum.find_value(socket.assigns.classes, &(&1.id == params["class"] && &1.id)),
      type: Enum.find(SanctionType.values(), &(Atom.to_string(&1) == params["type"])),
      notify: params["notify"] == "1",
      page: parse_page(params["page"])
    }

    {:noreply, socket |> assign(filters: filters) |> load()}
  end

  defp load(socket) do
    %{current_scope: scope, filters: f} = socket.assigns

    page =
      Discipline.list_school_sanctions(scope, scope.current_academic_year,
        class_group_id: f.class,
        type: f.type,
        to_notify: f.notify,
        offset: (f.page - 1) * 50
      )

    selected = socket.assigns.selected && Enum.find(page.results, &(&1.id == socket.assigns.selected.id))
    assign(socket, page: page, selected: selected)
  end

  def handle_event("filter", params, socket) do
    query =
      %{"class" => params["class"], "type" => params["type"], "notify" => params["notify"]}
      |> Enum.reject(fn {_k, v} -> v in [nil, "", "false"] end)

    {:noreply, push_patch(socket, to: ~p"/school/sanctions?#{query}")}
  end

  def handle_event("select", %{"id" => id}, socket),
    do: {:noreply, assign(socket, selected: Enum.find(socket.assigns.page.results, &(&1.id == id)))}

  def handle_event("search", %{"q" => q}, socket) do
    matches =
      if String.length(String.trim(q)) >= 2 do
        scope = socket.assigns.current_scope
        Enrollment.list_school_students(scope, scope.current_academic_year, query: q).results |> Enum.take(8)
      else
        []
      end

    {:noreply, assign(socket, q: q, matches: matches)}
  end

  def handle_event("pick", %{"id" => id}, socket) do
    enrollment = Enum.find(socket.assigns.matches, &(&1.id == id))
    {:noreply, assign(socket, entry: %{socket.assigns.entry | enrollment: enrollment}, matches: [], q: "")}
  end

  def handle_event("type", %{"type" => type}, socket) do
    type = Enum.find(socket.assigns.types, &(Atom.to_string(&1) == type))
    {:noreply, assign(socket, entry: %{socket.assigns.entry | type: type})}
  end

  def handle_event("add", %{"entry" => params}, socket) do
    %{entry: %{enrollment: enrollment, type: type}, current_scope: scope} = socket.assigns

    with %{} <- enrollment,
         true <- not is_nil(type),
         {:ok, date} <- Date.from_iso8601(params["date"] || "") do
      attrs = %{
        type: type,
        date: date,
        reason: blank_to_nil(params["reason"]),
        duration_days: if(type == :exclusion_temporaire, do: parse_int(params["duration_days"]))
      }

      case Discipline.add_sanction(scope, enrollment, attrs) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Sanction enregistrée."))
           |> assign(entry: %{enrollment: nil, type: nil})
           |> load()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Sanction non enregistrée."))}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Choisissez un élève, un type et une date."))}
    end
  end

  def handle_event("notify", %{"id" => id}, socket) do
    with %{} = s <- Enum.find(socket.assigns.page.results, &(&1.id == id)),
         {:ok, _} <- Discipline.mark_parents_notified(socket.assigns.current_scope, s) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Action impossible."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %{} = s <- Enum.find(socket.assigns.page.results, &(&1.id == id)),
         :ok <- Discipline.delete_sanction(s, scope: socket.assigns.current_scope) do
      {:noreply, socket |> assign(selected: nil) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Action impossible."))}
    end
  end

  defp member_name(member), do: member.user && (member.user.full_name || to_string(member.user.email))
  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: String.trim(v)

  defp parse_int(v) do
    case Integer.parse(to_string(v || "")) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_page(v) do
    case Integer.parse(to_string(v || "")) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp guardian(sanction) do
    case sanction.enrollment.student.primary_guardian_link do
      %{guardian: g} -> g
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="sanctions" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Vie scolaire")} title={gettext("Sanctions")}>
          <:actions>
            <.side_chip id="sanctions-count">
              {ngettext("%{count} sanction", "%{count} sanctions", @page.count || 0)}
            </.side_chip>
          </:actions>
        </.page_header>

        <div class="ta-panel flex flex-col gap-3">
          <h2 class="ta-eyebrow">{gettext("Nouvelle sanction")}</h2>
          <form id="student-search" phx-change="search" class="flex flex-col gap-1">
            <input
              name="q"
              value={@q}
              placeholder={gettext("Rechercher un élève (nom ou matricule)")}
              phx-debounce="300"
              autocomplete="off"
              class="input input-sm w-full sm:w-80"
            />
          </form>
          <div :if={@matches != []} class="flex flex-wrap gap-1.5">
            <button
              :for={e <- @matches}
              id={"pick-#{e.id}"}
              type="button"
              phx-click="pick"
              phx-value-id={e.id}
              class="btn btn-ghost btn-xs"
            >
              {e.student.full_name} · {e.class_group.label}
            </button>
          </div>
          <p :if={@entry.enrollment} class="text-sm font-semibold">
            {@entry.enrollment.student.full_name} · {@entry.enrollment.class_group.label}
          </p>
          <div class="flex flex-wrap gap-1.5">
            <button
              :for={t <- @types}
              id={"type-#{t}"}
              type="button"
              phx-click="type"
              phx-value-type={t}
              class={["btn btn-xs", if(@entry.type == t, do: "btn-primary", else: "btn-outline")]}
            >
              {SanctionType.label(t)}
            </button>
          </div>
          <form id="sanction-entry" phx-submit="add" class="flex flex-wrap items-end gap-2">
            <input
              :if={@entry.type == :exclusion_temporaire}
              name="entry[duration_days]"
              inputmode="numeric"
              placeholder={gettext("jours")}
              class="input input-sm w-20"
            />
            <input name="entry[reason]" placeholder={gettext("Motif (facultatif)")} class="input input-sm w-full sm:w-64" />
            <input type="date" name="entry[date]" value={Date.to_iso8601(Reference.today())} class="input input-sm" />
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
          </form>
        </div>

        <form id="sanction-filters" phx-change="filter" class="flex flex-wrap items-center gap-2">
          <select name="class" class="select select-sm">
            <option value="">{gettext("Toutes les classes")}</option>
            <option :for={c <- @classes} value={c.id} selected={c.id == @filters.class}>{c.label}</option>
          </select>
          <select name="type" class="select select-sm">
            <option value="">{gettext("Tous les types")}</option>
            <option :for={t <- SanctionType.values()} value={t} selected={t == @filters.type}>
              {SanctionType.label(t)}
            </option>
          </select>
          <label class="flex items-center gap-1.5 text-sm">
            <input type="checkbox" name="notify" value="1" checked={@filters.notify} class="checkbox checkbox-sm" />
            {gettext("À notifier")}
          </label>
        </form>

        <div class="flex flex-wrap items-start gap-4">
          <div class="min-w-0 flex-[1_1_560px] overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Élève")}</th>
                  <th>{gettext("Classe")}</th>
                  <th>{gettext("Type")}</th>
                  <th>{gettext("Date")}</th>
                  <th>{gettext("Motif")}</th>
                  <th>{gettext("Parents")}</th>
                </tr>
              </thead>
              <tbody id="sanction-rows">
                <tr
                  :for={s <- @page.results}
                  id={"sanction-#{s.id}"}
                  phx-click="select"
                  phx-value-id={s.id}
                  class={["cursor-pointer hover:bg-base-200/60", @selected && @selected.id == s.id && "bg-primary/10"]}
                >
                  <td class="font-semibold">{s.enrollment.student.full_name}</td>
                  <td>{s.enrollment.class_group.label}</td>
                  <td>{SanctionType.label(s.type)}</td>
                  <td class="ta-num">{date(s.date)}</td>
                  <td class="max-w-48 truncate">{s.reason}</td>
                  <td>
                    <span :if={s.parents_notified_on} class="text-primary">
                      {gettext("notifiés le %{date}", date: date(s.parents_notified_on))}
                    </span>
                    <span :if={!s.parents_notified_on} class="text-warning">{gettext("À notifier")}</span>
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@page.results == []} class="p-4 text-sm text-base-content/60">{gettext("Aucune sanction.")}</p>
          </div>

          <aside :if={@selected} id="sanction-panel" class="ta-panel flex min-w-0 max-w-[420px] flex-[1_1_300px] flex-col gap-2">
            <.link navigate={~p"/school/students/#{@selected.enrollment.student_id}"} class="font-display text-lg font-semibold hover:text-primary">
              {@selected.enrollment.student.full_name}
            </.link>
            <span class="text-sm">{@selected.enrollment.class_group.label} · {SanctionType.label(@selected.type)} · {date(@selected.date)}</span>
            <span :if={@selected.duration_days} class="text-sm">
              {ngettext("%{count} jour", "%{count} jours", @selected.duration_days)}
            </span>
            <span :if={@selected.reason} class="text-sm">{@selected.reason}</span>
            <span :if={@issuers[@selected.issued_by_user_id]} class="text-xs text-base-content/70">
              {gettext("Par %{name}", name: @issuers[@selected.issued_by_user_id])}
            </span>
            <%= case guardian(@selected) do %>
              <% nil -> %>
                <.link navigate={~p"/school/students/#{@selected.enrollment.student_id}"} class="link text-sm text-warning">
                  {gettext("Aucun contact")}
                </.link>
              <% g -> %>
                <span class="text-sm">
                  {g.full_name} · {GuardianRelationship.label(g.relationship)}
                  <a href={"tel:#{g.phone_key}"} class="link link-primary font-mono">{g.phone}</a>
                  <a :if={g.phone_2} href={"tel:#{g.phone_2}"} class="link link-primary font-mono">{g.phone_2}</a>
                </span>
            <% end %>
            <div class="flex flex-wrap gap-2 pt-1">
              <button
                :if={!@selected.parents_notified_on}
                id={"notify-#{@selected.id}"}
                phx-click="notify"
                phx-value-id={@selected.id}
                class="btn btn-primary btn-sm"
              >
                {gettext("Marquer les parents notifiés")}
              </button>
              <button
                id={"delete-#{@selected.id}"}
                phx-click="delete"
                phx-value-id={@selected.id}
                data-confirm={gettext("Supprimer cette sanction ?")}
                class="btn btn-ghost btn-sm text-error"
              >
                {gettext("Supprimer")}
              </button>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

Check while implementing: the field names of a member returned by `Accounts.list_members/1` (user and its
name field) — read the function and adapt `member_name/1`; `delete_sanction/2` returns `:ok` (the
discipline page matches on it). Pagination links (as in `StudentsLive`) are only needed past 50 rows: add the
same `join` nav, patching `page`.

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/sanctions_live_test.exs test/teacher_assistant_web/spaces_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/sanctions_live.ex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/spaces.ex test/teacher_assistant_web/live/school/sanctions_live_test.exs \
  test/teacher_assistant_web/spaces_test.exs
git commit -m "feat: « Sanctions » page for the SG with quick entry and parents' contact"
```

---

## KLM5 — Class size, naming rule, enrolment counts

### Task 3: Data — two profile fields, the count aggregate, the label rule

**Files:**
- Create: `lib/teacher_assistant/academics/class_suffix.ex`
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (two attributes, accepted by `:update`)
- Modify: `lib/teacher_assistant/academics/class_group.ex` (`aggregates`)
- Modify: `lib/teacher_assistant/academics/school_templates.ex` (`next_class_label/3`)
- Modify: `lib/teacher_assistant/enrollment.ex` (`list_class_groups/3` with `load:`)
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex:179` (students count from the aggregate)
- Test: `test/teacher_assistant/academics/class_size_test.exs`

**Interfaces:**
- Produces: `ClassSuffix` enum; `SchoolProfile.max_class_size`, `class_suffix`; `ClassGroup.enrollment_count`;
  `Enrollment.list_class_groups(scope, year, opts \\ [])` (`opts[:load]`);
  `SchoolTemplates.next_class_label(base :: String.t(), existing :: [String.t()], suffix :: :letters | :numbers) :: String.t()`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.ClassSizeTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Accounts, Enrollment, Organization}
  alias TeacherAssistant.Academics.SchoolTemplates

  describe "next_class_label/3" do
    test "letters take the first free one" do
      assert SchoolTemplates.next_class_label("6ème", ["6ème A", "6ème C", "5ème B"], :letters) == "6ème B"
      assert SchoolTemplates.next_class_label("6ème", [], :letters) == "6ème A"
      assert SchoolTemplates.next_class_label("2nde C", ["2nde C A"], :letters) == "2nde C B"
    end

    test "numbers do the same" do
      assert SchoolTemplates.next_class_label("6ème", ["6ème 1", "6ème 2"], :numbers) == "6ème 3"
    end
  end

  test "the class's enrolment count is one aggregate; the profile holds the limit and the rule" do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})

    [first | _] = Enrollment.list_class_groups(scope, year, load: [:enrollment_count])
    assert first.id == cg.id
    assert first.enrollment_count == 2

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.max_class_size == nil
    assert profile.class_suffix == :letters

    {:ok, profile} =
      Accounts.update_school_profile(profile, %{max_class_size: 60, class_suffix: :numbers}, scope: scope)

    assert profile.max_class_size == 60
    assert {:error, _} = Accounts.update_school_profile(profile, %{max_class_size: 0}, scope: scope)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/class_size_test.exs`
Expected: FAIL — `next_class_label/3` undefined.

- [ ] **Step 3: Implement**

```elixir
# lib/teacher_assistant/academics/class_suffix.ex
defmodule TeacherAssistant.Academics.ClassSuffix do
  @moduledoc "Spec KLM5: how a school tells classes of one level apart (6e A, 6e B or 6e 1, 6e 2)."
  use Ash.Type.Enum, values: [:letters, :numbers]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:letters), do: gettext("Lettres (6e A, 6e B)")
  def label(:numbers), do: gettext("Numéros (6e 1, 6e 2)")
end
```

`school_profile.ex` attributes (after `statutory_hours`) and add both to the `:update` accept list:

```elixir
    # Spec KLM5: a warning above it, never a block; nil = no limit.
    attribute :max_class_size, :integer, public?: true, constraints: [min: 1, max: 200]

    attribute :class_suffix, TeacherAssistant.Academics.ClassSuffix,
      allow_nil?: false,
      default: :letters,
      public?: true
```

`class_group.ex`, a new block after `calculations`:

```elixir
  aggregates do
    # Spec KLM5 (R05): one query for every class's headcount.
    count :enrollment_count, :enrollments
  end
```

`school_templates.ex`:

```elixir
  @doc "Spec KLM5: the first free label `base <suffix>` for a level, given the existing labels."
  def next_class_label(base, existing, suffix) do
    taken = MapSet.new(existing)

    suffix
    |> candidates()
    |> Enum.map(&"#{base} #{&1}")
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  defp candidates(:letters), do: Enum.map(?A..?Z, &<<&1>>)
  defp candidates(:numbers), do: Enum.map(1..99, &Integer.to_string/1)
```

`enrollment.ex`:

```elixir
  def list_class_groups(%Scope{} = scope, %AcademicYear{id: year_id}, opts \\ []) do
    ClassGroup
    |> Ash.Query.for_read(:for_workspace_and_year, %{academic_year_id: year_id}, scope: scope)
    |> Ash.Query.load(opts[:load] || [])
    |> Ash.read!()
  end
```

`dashboard_live.ex` `load_stats/1`: load classes with `load: [:enrollment_count]` and
`students_count = classes |> Enum.map(& &1.enrollment_count) |> Enum.sum()`.

- [ ] **Step 4: Dev migration and tests**

```bash
mix ash.codegen --dev
MIX_TEST_PARTITION=3 MIX_ENV=test mix ash.migrate
MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/class_size_test.exs test/teacher_assistant_web/live/school/dashboard_live_test.exs
```

Expected: the migration adds two `school_profiles` columns; PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/class_suffix.ex lib/teacher_assistant/accounts/school_profile.ex \
  lib/teacher_assistant/academics/class_group.ex lib/teacher_assistant/academics/school_templates.ex \
  lib/teacher_assistant/enrollment.ex lib/teacher_assistant_web/live/school/dashboard_live.ex \
  priv/repo/migrations priv/resource_snapshots test/teacher_assistant/academics/class_size_test.exs
git commit -m "feat: maximum class size, class naming rule, enrolment count in one query"
```

---

### Task 4: Class size in the screens; label suggestion; settings fields

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/classes_live.ex` (count from the aggregate, « 68 / 60 »,
  label suggestion)
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex` (header chip, message after enrolling)
- Modify: `lib/teacher_assistant_web/live/school/enroll_import_live.ex` (message after import)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (two fields in the profile form)
- Modify: `lib/teacher_assistant/enrollment.ex` (`capacity/2`)
- Test: `test/teacher_assistant_web/live/school/class_size_live_test.exs`

**Interfaces:**
- Consumes: Task 3.
- Produces: `Enrollment.capacity(scope, %ClassGroup{}) :: %{count: integer, max: integer | nil, over?: boolean}`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.ClassSizeLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Accounts, Enrollment}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6ème A", level: "6ème"})
    {:ok, _} = Enrollment.create_class_group(scope, year, %{label: "6ème C", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    %{cg: cg}
  end

  defp limit(scope, max) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    {:ok, _} = Accounts.update_school_profile(profile, %{max_class_size: max}, scope: scope)
  end

  test "no limit: plain count; over the limit: « n / max » as a warning", %{conn: conn, scope: scope, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes")
    refute render(view) =~ "2 / "

    limit(scope, 1)
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#class-size-#{cg.id}.text-warning", "2 / 1")

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    assert has_element?(view, "#class-size", "2 / 1")
  end

  test "enrolling past the limit succeeds with the message", %{conn: conn, scope: scope, cg: cg} do
    limit(scope, 2)
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{"student" => %{"full_name" => "Zoé", "sex" => "f"}})
    |> render_submit()

    assert render(view) =~ "La classe dépasse l&#39;effectif maximum (2)"
    assert length(Enrollment.list_roster(scope, cg)) == 3
  end

  test "the add-class form proposes the next free label", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")

    view
    |> form("#class-form", %{"class_group" => %{"level" => "6ème", "label" => ""}})
    |> render_change()

    assert has_element?(view, "#class-form input[name='class_group[label]'][value='6ème B']")
  end

  test "settings holds the limit and the rule", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#school-profile-form", %{"profile" => %{"max_class_size" => "55", "class_suffix" => "numbers"}})
    |> render_submit()

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.max_class_size == 55
    assert profile.class_suffix == :numbers
  end
end
```

(Use the real ids: the add-class form id and the profile form id are in `classes_live.ex` (≈ line 118) and
`settings_live.ex` (≈ line 77) — read them and adjust `#class-form` / `#school-profile-form`. The enrol form
is `#enroll-form` with fields `student[full_name]`, `student[sex]`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/class_size_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: `Enrollment.capacity/2`**

```elixir
  @doc "Spec KLM5: a class's headcount against the school's maximum (a warning, never a block)."
  def capacity(%Scope{} = scope, %ClassGroup{} = cg) do
    count = length(list_roster(scope, cg))

    max =
      case TeacherAssistant.Accounts.fetch_school_profile(scope) do
        {:ok, profile} -> profile.max_class_size
        _ -> nil
      end

    %{count: count, max: max, over?: is_integer(max) and count > max}
  end
```

- [ ] **Step 4: Screens**

- `classes_live.ex`: in `mount` keep `max_class_size` from the already-fetched profile
  (`assign(:max_class_size, …)`); `load_classes/1` lists with `load: [:enrollment_count]` and
  `effectif: cg.enrollment_count`; the effectif cell becomes

```heex
                  <td
                    id={"class-size-#{row.cg.id}"}
                    class={[@max_class_size && row.effectif > @max_class_size && "text-warning font-semibold"]}
                  >
                    {if @max_class_size, do: "#{row.effectif} / #{@max_class_size}", else: row.effectif}
                  </td>
```

- `classes_live.ex` label suggestion — in `handle_event("validate_class", …)`, before validating:

```elixir
    params = suggest_label(socket, params)
```

```elixir
  # Spec KLM5: a blank (or still-suggested) label follows the level and the school's rule.
  defp suggest_label(socket, %{"level" => level} = params) when level not in [nil, ""] do
    if params["label"] in [nil, "", socket.assigns[:suggested_label]] do
      base = Enum.join(Enum.reject([level, params["serie"]], &(&1 in [nil, ""])), " ")
      labels = Enum.map(socket.assigns.classes, & &1.cg.label)
      label = SchoolTemplates.next_class_label(base, labels, socket.assigns.class_suffix)
      Map.put(params, "label", label)
    else
      params
    end
  end

  defp suggest_label(_socket, params), do: params
```

  and assign `class_suffix` from the profile in `mount` (default `:letters`) and `suggested_label` to the
  value put in `params` (so a later level change replaces it but a typed label is kept).
- `class_live.ex`: in the `page_header`, add

```heex
          <:actions>
            <.side_chip id="class-size" class={@capacity.over? && "text-warning"}>
              {if @capacity.max, do: "#{@capacity.count} / #{@capacity.max}", else: ngettext("%{count} élève", "%{count} élèves", @capacity.count)}
            </.side_chip>
          </:actions>
```

  (if `side_chip` has no `class` attr, wrap its content in a `<span class=…>`); assign
  `capacity: Enrollment.capacity(scope, cg)` in `load_roster/1`; after a successful `enroll_new`, when
  `capacity.over?`, flash
  `gettext("Élève inscrit. La classe dépasse l'effectif maximum (%{max}).", max: capacity.max)` instead of
  « Student enrolled. ». The test greps « La classe dépasse l'effectif maximum (2) ».
- `enroll_import_live.ex` done stage: `<p :if={@capacity.over?} class="text-sm text-warning">{gettext("La
  classe dépasse l'effectif maximum (%{max}).", max: @capacity.max)}</p>`, with
  `capacity: Enrollment.capacity(scope, cg)` assigned after `import_rows`.
- `settings_live.ex` profile form, after the registration number input:

```heex
                <.input field={@profile_form[:max_class_size]} type="number" label={gettext("Effectif maximum par classe")} />
                <.input
                  field={@profile_form[:class_suffix]}
                  type="select"
                  label={gettext("Nommage des classes")}
                  options={Enum.map(TeacherAssistant.Academics.ClassSuffix.values(), &{TeacherAssistant.Academics.ClassSuffix.label(&1), &1})}
                />
```

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/class_size_live_test.exs test/teacher_assistant_web/live/school/classes_live_test.exs test/teacher_assistant_web/live/school/class_live_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs test/teacher_assistant_web/live/school/settings_profile_test.exs test/teacher_assistant_web/live/school/enroll_import_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/enrollment.ex lib/teacher_assistant_web/live/school/classes_live.ex \
  lib/teacher_assistant_web/live/school/class_live.ex lib/teacher_assistant_web/live/school/enroll_import_live.ex \
  lib/teacher_assistant_web/live/school/settings_live.ex test/teacher_assistant_web/live/school/class_size_live_test.exs
git commit -m "feat: class size warnings, label suggestion, class settings"
```

---

## KLM6 — Official header, signature and stamp

### Task 5: Data — header lines, signature and stamp, head-only action, bulletin elements

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (three attributes, `:update_official_header`,
  head policy)
- Modify: `lib/teacher_assistant/academics/bulletin_element.ex` (`:signature`, `:stamp`)
- Modify: `lib/teacher_assistant/academics/bulletin_template.ex` (`header` keys, `official_lines/1`,
  `generated_official_lines/1`)
- Modify: `lib/teacher_assistant/accounts.ex` (`update_official_header/3`, `can_edit_official_header?/1`)
- Test: `test/teacher_assistant/academics/official_header_test.exs`

**Interfaces:**
- Produces: `SchoolProfile.official_header_lines :: [String.t()] | nil`, `signature_path`, `stamp_path`;
  `Accounts.update_official_header(scope, attrs) :: {:ok, profile} | {:error, term}`;
  `Accounts.can_edit_official_header?(scope) :: boolean`; `BulletinTemplate.resolve/…` header gains
  `official_lines`, `signature?`, `stamp?`; `BulletinTemplate.official_lines(header)` returns saved lines when
  set; `BulletinTemplate.generated_official_lines(header)`; `BulletinElement` values `:signature`, `:stamp`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.OfficialHeaderTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Academics.{BulletinElement, BulletinTemplate}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    %{scope: scope}
  end

  test "saved lines replace the generated ones; nil brings them back", %{scope: scope} do
    header = %{region: nil, department: nil}
    assert hd(BulletinTemplate.official_lines(header)) == "République du Cameroun"

    assert {:ok, _} =
             Accounts.update_official_header(scope, %{official_header_lines: ["République du Cameroun", "Délégation X"]})

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == ["République du Cameroun", "Délégation X"]
    assert BulletinTemplate.official_lines(Map.put(header, :official_lines, profile.official_header_lines)) ==
             ["République du Cameroun", "Délégation X"]

    assert {:ok, _} = Accounts.update_official_header(scope, %{official_header_lines: nil})
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == nil
  end

  test "at most six lines of 120 characters", %{scope: scope} do
    assert {:error, _} = Accounts.update_official_header(scope, %{official_header_lines: List.duplicate("x", 7)})
    assert {:error, _} = Accounts.update_official_header(scope, %{official_header_lines: [String.duplicate("x", 121)]})
  end

  test "only the head may change the header or the images", %{scope: scope} do
    censeur = member_scope_fixture(scope, %{roles: [:vice_principal]})
    refute Accounts.can_edit_official_header?(censeur)
    assert Accounts.can_edit_official_header?(scope)
    assert_forbidden(Accounts.update_official_header(censeur, %{signature_path: "x.png"}))
  end

  test "signature and stamp are bulletin elements on by default" do
    assert :signature in BulletinElement.defaults()
    assert :stamp in BulletinElement.defaults()
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/official_header_test.exs`
Expected: FAIL — `Accounts.update_official_header/2 is undefined`.

- [ ] **Step 3: Implement**

`school_profile.ex` attributes:

```elixir
    # Spec KLM6: the bulletin's official header (nil = generated) and the head's signature and stamp.
    attribute :official_header_lines, {:array, :string},
      public?: true,
      constraints: [max_length: 6, items: [max_length: 120]]

    attribute :signature_path, :string, public?: true
    attribute :stamp_path, :string, public?: true
```

action and policy:

```elixir
    update :update_official_header do
      accept [:official_header_lines, :signature_path, :stamp_path]
    end
```

```elixir
    policy action(:update_official_header) do
      authorize_if {Checks.SchoolRole, any_of: :head}
    end
```

`accounts.ex`:

```elixir
  @doc "Spec KLM6: saves the official header lines and the signature and stamp paths (head only)."
  def update_official_header(%Scope{} = scope, attrs) do
    with {:ok, profile} <- fetch_school_profile(scope) do
      profile
      |> Ash.Changeset.for_update(:update_official_header, attrs, scope: scope)
      |> Ash.update()
    end
  end

  def can_edit_official_header?(%Scope{} = scope) do
    case fetch_school_profile(scope) do
      {:ok, profile} -> Ash.can?({profile, :update_official_header}, scope)
      _ -> false
    end
  end
```

`bulletin_element.ex`: add `:signature, :stamp` to `values` (before `:qr_code`) and

```elixir
  def label(:signature), do: gettext("Signature du chef d'établissement")
  def label(:stamp), do: gettext("Cachet")
```

`bulletin_template.ex`: in `resolve`'s `header:` map add

```elixir
        official_lines: profile.official_header_lines,
        signature?: is_binary(profile.signature_path),
        stamp?: is_binary(profile.stamp_path),
```

and replace `official_lines/1`:

```elixir
  @doc "The header's official lines: the school's own when saved (spec KLM6), else the generated ones."
  def official_lines(header) do
    case Map.get(header, :official_lines) do
      [_ | _] = lines -> lines
      _ -> generated_official_lines(header)
    end
  end

  @doc "The national lines generated from the region and department, in the current locale."
  def generated_official_lines(header) do
    # (the former body of official_lines/1, unchanged)
  end
```

(Published snapshots made before this change have no `:official_lines` key; `Map.get` keeps them on the
generated lines.)

- [ ] **Step 4: Dev migration and tests**

```bash
mix ash.codegen --dev
MIX_TEST_PARTITION=3 MIX_ENV=test mix ash.migrate
MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/official_header_test.exs test/teacher_assistant/academics/bulletin_settings_test.exs test/teacher_assistant_web/live/school/bulletin_template_live_test.exs
```

Expected: three new `school_profiles` columns; PASS. `bulletin_settings_test` pins the default element count
(9 since KLM1): it becomes 11 — update it and say so in the ledger.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/accounts/school_profile.ex lib/teacher_assistant/academics/bulletin_element.ex \
  lib/teacher_assistant/academics/bulletin_template.ex lib/teacher_assistant/accounts.ex \
  priv/repo/migrations priv/resource_snapshots test/teacher_assistant/academics/official_header_test.exs \
  test/teacher_assistant/academics/bulletin_settings_test.exs
git commit -m "feat: editable official header, signature and stamp on the school profile"
```

---

### Task 6: Header page, image serving, printed signature block

**Files:**
- Create: `lib/teacher_assistant_web/live/school/official_header_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`/school/settings/header`)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (link `#official-header-link` in the
  Établissement section)
- Modify: `lib/teacher_assistant_web/controllers/school_logo_controller.ex` (`kind` param)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex` (head's slot, CSS)
- Modify: `lib/teacher_assistant_web/live/school/bulletin_template_live.ex` (preview of the images)
- Test: `test/teacher_assistant_web/live/school/official_header_live_test.exs`,
  `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` (add)

**Interfaces:**
- Consumes: Task 5.
- Produces: route `/school/settings/header` (`School.OfficialHeaderLive`); `GET /school/logo?kind=signature|stamp`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.OfficialHeaderLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "the head edits the lines and resets them", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#official-header-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/header")
    assert render(view) =~ "République du Cameroun"

    view
    |> form("#header-lines-form", %{"lines" => "République du Cameroun\nPaix – Travail – Patrie\nDélégation X"})
    |> render_submit()

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == ["République du Cameroun", "Paix – Travail – Patrie", "Délégation X"]

    view |> element("#reset-header") |> render_click()
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == nil
  end

  test "the head uploads a signature, served to members", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/header")

    upload =
      file_input(view, "#signature-form", :signature, [
        %{name: "sig.png", content: File.read!("test/support/fixtures/files/logo.png"), type: "image/png"}
      ])

    render_upload(upload, "sig.png")
    view |> form("#signature-form") |> render_submit()

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert is_binary(profile.signature_path)

    assert conn |> get(~p"/school/logo?kind=signature") |> response(200)
    assert conn |> get(~p"/school/logo?kind=stamp") |> response(404)
  end

  test "a Censeur is sent back to settings", %{workspace: ws, scope: scope} do
    censeur = TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, censeur.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} = live(conn, ~p"/school/settings/header")
  end
end
```

(Check `test/support/fixtures/files/` for the PNG the logo test uses — `settings_logo_test.exs` shows the name
and the upload calls; copy them.)

Add to `bulletin_print_controller_test.exs`:

```elixir
  test "the head's slot prints the signature and the stamp when set", %{conn: conn, cg: cg, seq: seq, roster: roster, scope: scope} do
    %{enrollment: enr} = hd(roster)
    {:ok, _} = TeacherAssistant.Accounts.update_official_header(scope, %{signature_path: "s.png", stamp_path: "c.png"})

    body =
      conn
      |> get(~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}")
      |> html_response(200)

    assert body =~ "/school/logo?kind=signature"
    assert body =~ "/school/logo?kind=stamp"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/official_header_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: FAIL.

- [ ] **Step 3: Logo controller `kind`**

```elixir
  def show(conn, params) do
    field =
      case params["kind"] do
        "signature" -> :signature_path
        "stamp" -> :stamp_path
        _ -> :logo_path
      end

    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         stored when is_binary(stored) <- Map.fetch!(profile, field),
         {:ok, path} <- safe_logo_path(stored) do
      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end
```

- [ ] **Step 4: The page**

```elixir
defmodule TeacherAssistantWeb.School.OfficialHeaderLive do
  @moduledoc """
  Settings → Établissement → En-tête et signature (spec KLM6, S04): the
  bulletin's official header lines (editable, resettable), the head's
  signature and the school stamp (PNG or JPEG, 1 MB). Head only.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Academics.BulletinTemplate
  alias TeacherAssistantWeb.Authz

  @kinds [signature: :signature_path, stamp: :stamp_path]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Accounts.can_edit_official_header?(scope) do
      {:ok,
       socket
       |> allow_upload(:signature, accept: ~w(.png .jpg .jpeg), max_entries: 1, max_file_size: 1_000_000)
       |> allow_upload(:stamp, accept: ~w(.png .jpg .jpeg), max_entries: 1, max_file_size: 1_000_000)
       |> load()}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket) do
    {:ok, profile} = Accounts.fetch_school_profile(socket.assigns.current_scope)
    header = %{region: profile.region, department: profile.department}

    assign(socket,
      profile: profile,
      lines: profile.official_header_lines || BulletinTemplate.generated_official_lines(header),
      custom?: profile.official_header_lines != nil,
      error: nil
    )
  end

  def handle_event("save_lines", %{"lines" => text}, socket) do
    lines = text |> String.split(["\r\n", "\n"]) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    save(socket, %{official_header_lines: if(lines == [], do: nil, else: lines)}, gettext("En-tête enregistré."))
  end

  def handle_event("reset_lines", _params, socket),
    do: save(socket, %{official_header_lines: nil}, gettext("En-tête rétabli."))

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("upload", %{"kind" => kind}, socket) do
    with {kind, field} <- Enum.find(@kinds, fn {k, _} -> Atom.to_string(k) == kind end),
         [relative] <- store(socket, kind) do
      save(socket, %{field => relative}, gettext("Image enregistrée."))
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove", %{"kind" => kind}, socket) do
    case Enum.find(@kinds, fn {k, _} -> Atom.to_string(k) == kind end) do
      {_kind, field} -> save(socket, %{field => nil}, gettext("Image retirée."))
      nil -> {:noreply, socket}
    end
  end

  defp store(socket, kind) do
    uploads_dir = Application.fetch_env!(:teacher_assistant, :uploads_dir)
    ws = socket.assigns.current_scope.current_workspace.id

    consume_uploaded_entries(socket, kind, fn %{path: tmp}, entry ->
      relative = Path.join(["school_signatures", ws, Ash.UUIDv7.generate() <> Path.extname(entry.client_name)])
      dest = Path.join(uploads_dir, relative)
      dest |> Path.dirname() |> File.mkdir_p!()
      File.cp!(tmp, dest)
      {:ok, relative}
    end)
  end

  defp save(socket, attrs, message) do
    case Accounts.update_official_header(socket.assigns.current_scope, attrs) do
      {:ok, _} -> {:noreply, socket |> load() |> put_flash(:info, message)}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, assign(socket, error: gettext("Au plus 6 lignes de 120 caractères."))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="official-header" class="space-y-6">
        <.page_header eyebrow={gettext("Établissement")} title={gettext("En-tête et signature")} />

        <.form for={%{}} id="header-lines-form" phx-submit="save_lines" class="ta-panel space-y-3">
          <h2 class="ta-eyebrow">{gettext("En-tête officiel")}</h2>
          <p class="text-xs text-base-content/60">{gettext("Une ligne par ligne d'en-tête, 6 au plus.")}</p>
          <textarea name="lines" rows="6" class="textarea textarea-bordered w-full">{Enum.join(@lines, "\n")}</textarea>
          <p :if={@error} id="header-error" class="text-sm text-error">{@error}</p>
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
            <button :if={@custom?} type="button" id="reset-header" phx-click="reset_lines" class="btn btn-ghost btn-sm">
              {gettext("Rétablir l'en-tête par défaut")}
            </button>
          </div>
        </.form>

        <div class="grid gap-4 sm:grid-cols-2">
          <.form
            :for={{kind, title} <- [signature: gettext("Signature du chef d'établissement"), stamp: gettext("Cachet")]}
            for={%{}}
            id={"#{kind}-form"}
            phx-submit="upload"
            phx-change="validate"
            class="ta-panel space-y-3"
          >
            <input type="hidden" name="kind" value={kind} />
            <h2 class="ta-eyebrow">{title}</h2>
            <img
              :if={Map.fetch!(@profile, Keyword.fetch!([signature: :signature_path, stamp: :stamp_path], kind))}
              src={~p"/school/logo?kind=#{kind}"}
              alt={title}
              class="h-20 object-contain"
            />
            <.live_file_input upload={@uploads[kind]} />
            <div class="flex gap-2">
              <button type="submit" class="btn btn-secondary btn-sm">{gettext("Téléverser")}</button>
              <button
                :if={Map.fetch!(@profile, Keyword.fetch!([signature: :signature_path, stamp: :stamp_path], kind))}
                type="button"
                id={"remove-#{kind}"}
                phx-click="remove"
                phx-value-kind={kind}
                class="btn btn-ghost btn-sm text-error"
              >
                {gettext("Retirer")}
              </button>
            </div>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

Router: `live "/school/settings/header", School.OfficialHeaderLive, :index` after the passage route.
`settings_live.ex`: after the logo form in `#profil`, `<.link id="official-header-link" navigate={~p"/school/settings/header"} class="link link-primary text-sm">{gettext("En-tête officiel, signature et cachet")}</.link>`.

- [ ] **Step 5: Printed signature block and template preview**

In `bulletin_print_html/show.html.heex`, the head's slot becomes

```heex
        <div class="slot head">
          <div class="marks">
            <img
              :if={show?(@template, :stamp) and Map.get(@template.header, :stamp?)}
              class="stamp"
              src={~p"/school/logo?kind=stamp"}
              alt=""
            />
            <img
              :if={show?(@template, :signature) and Map.get(@template.header, :signature?)}
              class="signature"
              src={~p"/school/logo?kind=signature"}
              alt=""
            />
          </div>
          <div class="line">{tr(@lang, fn -> gettext("Visa Chef d'établissement") end)}</div>
        </div>
```

and add to its `<style>` block:
`.visa .head .marks { position: relative; height: 56px; } .visa .head .stamp { position: absolute; left: 10%; height: 56px; opacity: .85; } .visa .head .signature { position: absolute; right: 10%; height: 48px; }`.

In `bulletin_template_live.ex`, inside `#header-preview` after the school lines, add the same two images
(guarded by `@header.signature?` / `@header.stamp?`, class `h-10 inline-block`), and change the help line to
`gettext("Modifiable dans « En-tête et signature ».")` linking to `/school/settings/header`.

- [ ] **Step 6: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/official_header_live_test.exs test/teacher_assistant_web/controllers test/teacher_assistant_web/live/school/bulletin_template_live_test.exs test/teacher_assistant_web/live/school/settings_logo_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/school/official_header_live.ex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/live/school/settings_live.ex lib/teacher_assistant_web/controllers/school_logo_controller.ex \
  lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex \
  lib/teacher_assistant_web/live/school/bulletin_template_live.ex \
  test/teacher_assistant_web/live/school/official_header_live_test.exs \
  test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs
git commit -m "feat: official header page, signature and stamp on the printed bulletin"
```

---

## KLM7 — Rights matrix

### Task 7: Rights list, checked against the policies, and the page

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_role.ex` (`rights/0`, `cell/2`)
- Create: `lib/teacher_assistant_web/live/school/roles_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex`, `lib/teacher_assistant_web/spaces.ex` (Proviseur and Censeur
  « Paramètres »), `lib/teacher_assistant_web/live/school/settings_live.ex` (link `#roles-link`)
- Test: `test/teacher_assistant/accounts/school_role_rights_test.exs`,
  `test/teacher_assistant_web/live/school/roles_live_test.exs`, `test/teacher_assistant_web/spaces_test.exs`

**Interfaces:**
- Produces: `SchoolRole.rights() :: [%{key: atom, label: String.t(), axis: atom, resource: module, notes:
  %{role => String.t()}}]`; `SchoolRole.cell(right, role) :: :yes | :no | {:note, String.t()}`; route
  `/school/settings/roles`; nav id `nav-school-roles`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Accounts.SchoolRoleRightsTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Accounts.SchoolRole

  @axes [:member, :admin, :head, :conduct, :fees]

  test "every right names a real axis and a resource whose policies use it" do
    for right <- SchoolRole.rights() do
      assert right.axis in @axes, "#{right.key}: unknown axis #{right.axis}"

      checks =
        for policy <- Ash.Policy.Info.policies(right.resource),
            check <- policy.policies,
            do: check

      assert Enum.any?(checks, &(&1.check_module == Checks.SchoolRole and &1.check_opts[:any_of] == right.axis)),
             "#{right.key}: #{inspect(right.resource)} has no #{right.axis} check"
    end
  end

  test "cells follow the axis, with notes for row rules" do
    discipline = Enum.find(SchoolRole.rights(), &(&1.key == :discipline))
    assert SchoolRole.cell(discipline, :discipline_master) == :yes
    assert SchoolRole.cell(discipline, :bursar) == :no
    assert {:note, _} = SchoolRole.cell(Enum.find(SchoolRole.rights(), &(&1.key == :marks)), :teacher)
  end
end
```

```elixir
defmodule TeacherAssistantWeb.School.RolesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "shows rights × roles, read only", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#roles-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/roles")
    html = render(view)
    assert html =~ "Gérer la discipline et la conduite"
    assert html =~ "Surveillant général"
    assert html =~ "ses cours"
    assert html =~ "Les droits suivent le rôle"
    refute has_element?(view, "form")
  end

  test "a plain teacher is sent back to settings", %{workspace: ws, scope: scope} do
    teacher = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} = live(conn, ~p"/school/settings/roles")
  end
end
```

In `spaces_test.exs` add `assert "nav-school-roles" in item_ids(:proviseur, facts([:head]))` and the same for
the Censeur.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/accounts/school_role_rights_test.exs test/teacher_assistant_web/live/school/roles_live_test.exs`
Expected: FAIL — `SchoolRole.rights/0 is undefined`.

- [ ] **Step 3: `rights/0` and `cell/2`**

In `school_role.ex` (resources named in a function body, not a module attribute, to avoid compile-time
dependencies):

```elixir
  @doc """
  Spec KLM7: what each role may do, in plain words, for the read-only rights
  matrix. `axis` is the policy axis that grants the right; `resource` is one
  resource whose policies use that axis (checked by a test); `notes` carries
  row-level rules (a teacher's own courses, a form master's class).
  """
  def rights do
    alias TeacherAssistant.Academics, as: A
    alias TeacherAssistant.Accounts, as: Acc

    [
      %{key: :marks, label: gettext("Saisir les notes"), axis: :admin, resource: A.Mark,
        notes: %{teacher: gettext("ses cours"), hod: gettext("ses cours")}},
      %{key: :corrections, label: gettext("Valider les corrections de notes"), axis: :admin, resource: A.MarkCorrection,
        notes: %{teacher: gettext("demander, pour ses cours")}},
      %{key: :discipline, label: gettext("Gérer la discipline et la conduite"), axis: :conduct, resource: A.SanctionEntry,
        notes: %{teacher: gettext("sa classe, en lecture (professeur principal)")}},
      %{key: :fees, label: gettext("Frais et paiements"), axis: :fees, resource: A.Payment, notes: %{}},
      %{key: :settings, label: gettext("Paramètres de l'école"), axis: :admin, resource: Acc.SchoolProfile,
        notes: %{discipline_master: gettext("assiduité et discipline")}},
      %{key: :members, label: gettext("Membres et invitations"), axis: :head, resource: Acc.SchoolInvitation, notes: %{}},
      %{key: :timetable, label: gettext("Emploi du temps"), axis: :admin, resource: A.TimetableSlot, notes: %{}},
      %{key: :bulletins, label: gettext("Bulletins et conseils de classe"), axis: :admin, resource: A.ClassCouncil,
        notes: %{teacher: gettext("sa classe (professeur principal)")}},
      %{key: :assignments, label: gettext("Affectations"), axis: :admin, resource: A.TeachingContext, notes: %{}}
    ]
  end

  @doc "A matrix cell: `{:note, text}` for a row rule, else `:yes` when the role is on the axis, else `:no`."
  def cell(%{notes: notes, axis: axis}, role) do
    cond do
      Map.has_key?(notes, role) -> {:note, notes[role]}
      role in axis(axis) -> :yes
      true -> :no
    end
  end
```

(`mix format` lays these maps out one key per line.)

- [ ] **Step 4: The page, route, menus, link**

```elixir
defmodule TeacherAssistantWeb.School.RolesLive do
  @moduledoc "Settings → Rôles et droits (spec KLM7, S06): rights × roles, read only."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.SchoolRole

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok, assign(socket, rights: SchoolRole.rights(), roles: SchoolRole.values())}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="roles" class="space-y-4">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Rôles et droits")} />
        <p class="text-sm text-base-content/70">
          {gettext("Les droits suivent le rôle ; ils ne sont pas modifiables pour l'instant.")}
        </p>
        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table id="rights-matrix" class="table table-sm">
            <thead>
              <tr>
                <th></th>
                <th :for={role <- @roles} class="text-center text-xs">{SchoolRole.label(role)}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={right <- @rights} id={"right-#{right.key}"}>
                <th class="font-normal">{right.label}</th>
                <td :for={role <- @roles} class="text-center text-xs">
                  <%= case SchoolRole.cell(right, role) do %>
                    <% :yes -> %>
                      <.icon name="hero-check" class="size-4 text-primary" />
                    <% :no -> %>
                      <span class="text-base-content/30">—</span>
                    <% {:note, text} -> %>
                      <span class="text-base-content/80">{text}</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

Router: `live "/school/settings/roles", School.RolesLive, :index`. `spaces.ex`: add `roles()` at the end of
the Proviseur and Censeur « Paramètres » sections, helper
`defp roles, do: item("roles", gettext("Rôles et droits"), "hero-key", ~p"/school/settings/roles")`.
`settings_live.ex`: a `#roles-link` link beside `#passage-link`, label « Rôles et droits ».

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/accounts/school_role_rights_test.exs test/teacher_assistant_web/live/school/roles_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: PASS. If a right's resource has no check for its axis, fix the right (pick the axis the policy really
uses) — never the policy.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/accounts/school_role.ex lib/teacher_assistant_web/live/school/roles_live.ex \
  lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/spaces.ex lib/teacher_assistant_web/live/school/settings_live.ex \
  test/teacher_assistant/accounts/school_role_rights_test.exs test/teacher_assistant_web/live/school/roles_live_test.exs \
  test/teacher_assistant_web/spaces_test.exs
git commit -m "feat: read-only rights matrix checked against the policies"
```

---

### Task 8: Named migration, translations, status, full checks

- [ ] **Step 1: Named migration**

```bash
mix ash.codegen klm4_7_classes_header
MIX_TEST_PARTITION=3 MIX_ENV=test mix ecto.drop && MIX_TEST_PARTITION=3 MIX_ENV=test mix ecto.create
MIX_TEST_PARTITION=3 MIX_ENV=test mix ash.migrate
mix ash.codegen --check
```

Expected: one migration adding `max_class_size`, `class_suffix`, `official_header_lines`, `signature_path`,
`stamp_path` to `school_profiles`; nothing else.

- [ ] **Step 2: Translations** — `mix gettext.extract --merge`; fill every new `en` msgstr; clear new
  fuzzy flags in both locales; `grep -c "#, fuzzy"` prints 0 for both.

- [ ] **Step 3: Roadmap status** — under each of `## KLM4 …`, `## KLM5 …`, `## KLM6 …`, `## KLM7 …` add
  `Status: implemented 2026-10-06 (branch \`klm4-7-sanctions-classes-header-roles\`, plan
  \`docs/superpowers/plans/2026-10-06-klm4-7-sanctions-classes-header-roles.md\`); no visual check done.`

- [ ] **Step 4: Full checks** — `MIX_TEST_PARTITION=3 mix precommit`; exit 0; stage what it reformatted.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations priv/resource_snapshots priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git add -u lib test
git commit -m "chore: KLM4–7 migration, translations and status"
```
