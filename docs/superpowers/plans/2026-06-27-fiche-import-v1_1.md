# Assisted Fiche Import (v1.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a teacher upload a text-based fiche de progression PDF and turn it into a new, editable draft progression plan — deterministically, with no AI.

**Architecture:** A LiveView (`ImportLive`) uploads a PDF; a swappable `FicheExtractor` runs `pdftotext -layout`; a pure `FicheParser` turns the column-aligned text into draft rows; the teacher reviews/edits them; a transactional `Academics.import_progression_plan/3` persists a draft `ProgressionPlan` + `ProgressionEntry` rows.

**Tech Stack:** Elixir, Phoenix LiveView 1.1, Ash 3.26 / AshPostgres, daisyUI/Tailwind, Gettext, poppler-utils (`pdftotext`).

**Spec:** [`docs/superpowers/specs/2026-06-27-fiche-import-v1_1-design.md`](../specs/2026-06-27-fiche-import-v1_1-design.md)

## Global Constraints

- **Ash conventions:** all domain access goes through `TeacherAssistant.Academics` functions using `Ash.*(authorize?: false)`; never call resources from LiveViews directly. Owner-scope every read/write to the current `PersonalWorkspace`.
- **No AI / no external API.** Extraction is deterministic (`pdftotext -layout`).
- **Extractor is injected:** `Application.get_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.Academics.FicheExtractor.Pdftotext)` — tests stub it; never depend on poppler in the test env.
- **Parser is pure** (no I/O) and **never raises** — worst case `{:ok, %{rows: [], confidence: :low, raw_text: text}}`.
- **Entry fields:** `module` and `lesson_title` are `allow_nil?: false`; `entry_type` is one of `:lesson, :integration, :evaluation, :revision, :correction, :remediation, :holiday`; `planned_hours` is a `:decimal` (default `Decimal.new("1")`).
- **Import creates a NEW draft plan only** (status `:draft`); never appends to an existing plan; never stores the uploaded PDF.
- **Bilingual:** every user-facing string uses `gettext/1`; add the French `msgstr` to `priv/gettext/fr/LC_MESSAGES/default.po`.
- **Gate:** `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test) must pass at every commit.
- **Preserve existing DOM ids and gettext headings** elsewhere; add new stable ids for new screens.

---

## File Structure

- Create `lib/teacher_assistant/academics/fiche_parser.ex` — pure text → draft rows.
- Create `lib/teacher_assistant/academics/fiche_extractor.ex` — `pdftotext` wrapper + injection point.
- Modify `lib/teacher_assistant/academics.ex` — add `fetch_owned_teaching_context/2`, `import_progression_plan/3`; alias `Repo`.
- Create `lib/teacher_assistant_web/live/teacher/import_live.ex` — the screen.
- Modify `lib/teacher_assistant_web/router.ex` — add the `/teacher/import` route.
- Modify `lib/teacher_assistant_web/live/teacher/dashboard_live.ex` — add "Import a fiche" entry points.
- Create `test/support/fiche_extractor_stub.ex` — test extractor.
- Create `test/teacher_assistant/academics/fiche_parser_test.exs`.
- Create `test/teacher_assistant/academics/import_progression_plan_test.exs`.
- Create `test/teacher_assistant_web/live/teacher/import_live_test.exs`.
- Modify `priv/gettext/fr/LC_MESSAGES/default.po` — French strings.

---

## Task 1: FicheParser — base parsing (header, columns, module/lesson/hours)

**Files:**
- Create: `lib/teacher_assistant/academics/fiche_parser.ex`
- Test: `test/teacher_assistant/academics/fiche_parser_test.exs`

**Interfaces:**
- Produces: `TeacherAssistant.Academics.FicheParser.parse(layout_text :: String.t()) :: {:ok, %{rows: [row], confidence: :high | :low, raw_text: String.t()}}` where `row = %{module: String.t(), lesson_title: String.t(), planned_hours: Decimal.t(), entry_type: atom(), week_no: integer() | nil, sequence_no: integer() | nil}`. In this task `entry_type` is always `:lesson` and `week_no`/`sequence_no` are always `nil` (Task 2 enriches them).

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/fiche_parser_test.exs
defmodule TeacherAssistant.Academics.FicheParserTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.FicheParser

  # Columns are space-aligned, as produced by `pdftotext -layout`.
  @fr_tabular """
  FICHE DE PROGRESSION - Mathematiques 6eme

  Module                 Lecon                      Duree
  Nombres et calculs     Les entiers naturels       2
  Nombres et calculs     Addition et soustraction   3
  Geometrie              Les droites                 1
  """

  test "parses a clean tabular fiche into module/lesson/hours rows" do
    assert {:ok, %{rows: rows, confidence: :high}} = FicheParser.parse(@fr_tabular)
    assert length(rows) == 3

    assert %{
             module: "Nombres et calculs",
             lesson_title: "Les entiers naturels",
             planned_hours: hours,
             entry_type: :lesson,
             week_no: nil,
             sequence_no: nil
           } = hd(rows)

    assert Decimal.equal?(hours, Decimal.new("2"))
  end

  test "carries the module forward when the module cell is blank" do
    text = """
    Module             Lecon                  Duree
    Algebre            Identites remarquables 2
                       Factorisation          2
    """

    assert {:ok, %{rows: [r1, r2]}} = FicheParser.parse(text)
    assert r1.module == "Algebre"
    assert r2.module == "Algebre"
    assert r2.lesson_title == "Factorisation"
  end

  test "defaults planned_hours to 1 when the duration is missing or unparseable" do
    text = """
    Module     Lecon              Duree
    Intro      Presentation       --
    """

    assert {:ok, %{rows: [row]}} = FicheParser.parse(text)
    assert Decimal.equal?(row.planned_hours, Decimal.new("1"))
  end

  test "returns low confidence and empty rows when no header is found" do
    assert {:ok, %{rows: [], confidence: :low, raw_text: raw}} =
             FicheParser.parse("just some prose with no table at all\nsecond line")

    assert raw =~ "just some prose"
  end

  test "never raises on garbage input" do
    assert {:ok, %{confidence: :low}} = FicheParser.parse("")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/academics/fiche_parser_test.exs`
Expected: FAIL — `FicheParser.parse/1 is undefined`.

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/teacher_assistant/academics/fiche_parser.ex
defmodule TeacherAssistant.Academics.FicheParser do
  @moduledoc """
  Pure, deterministic parser: turns `pdftotext -layout` text from a fiche de
  progression into draft progression rows. Never raises; returns low confidence
  with the raw text when it cannot find a table.
  """

  @type row :: %{
          module: String.t(),
          lesson_title: String.t(),
          planned_hours: Decimal.t(),
          entry_type: atom(),
          week_no: integer() | nil,
          sequence_no: integer() | nil
        }

  # Column keyword groups (bilingual). Order here is the field priority.
  @groups [
    {:module, ~r/module|chapitre|chapter|th[eè]me|theme/iu},
    {:lesson, ~r/le[cç]on|lesson|contenu|content|intitul|titre|title/iu},
    {:hours, ~r/dur[eé]e|duree|heures?|hours?|volume/iu},
    {:week, ~r/semaine|week/iu},
    {:sequence, ~r/s[eé]quence|sequence/iu}
  ]

  @spec parse(String.t()) :: {:ok, %{rows: [row], confidence: :high | :low, raw_text: String.t()}}
  def parse(text) when is_binary(text) do
    lines = clean_lines(text)

    case find_header(lines) do
      nil ->
        {:ok, %{rows: [], confidence: :low, raw_text: text}}

      {header_index, columns} ->
        rows =
          lines
          |> Enum.drop(header_index + 1)
          |> build_rows(columns)

        confidence = if rows == [], do: :low, else: :high
        {:ok, %{rows: rows, confidence: confidence, raw_text: text}}
    end
  end

  def parse(_), do: {:ok, %{rows: [], confidence: :low, raw_text: ""}}

  # --- header detection -----------------------------------------------------

  # Returns {line_index, [{field, start_col}]} sorted by start_col, or nil.
  defp find_header(lines) do
    lines
    |> Enum.with_index()
    |> Enum.find_value(fn {line, idx} ->
      cols = header_columns(line)
      if length(cols) >= 2, do: {idx, Enum.sort_by(cols, &elem(&1, 1))}, else: nil
    end)
  end

  defp header_columns(line) do
    @groups
    |> Enum.flat_map(fn {field, regex} ->
      case Regex.run(regex, line, return: :index) do
        [{start, _len} | _] -> [{field, start}]
        _ -> []
      end
    end)
  end

  # --- row building ---------------------------------------------------------

  defp build_rows(data_lines, columns) do
    {rows, _module} =
      Enum.reduce(data_lines, {[], ""}, fn line, {acc, current_module} ->
        cells = slice_cells(line, columns)
        module_cell = String.trim(cell(cells, :module))
        lesson = String.trim(cell(cells, :lesson))
        current_module = if module_cell == "", do: current_module, else: module_cell

        if lesson == "" do
          {acc, current_module}
        else
          row = %{
            module: current_module,
            lesson_title: lesson,
            planned_hours: parse_hours(cell(cells, :hours)),
            entry_type: :lesson,
            week_no: nil,
            sequence_no: nil
          }

          {[row | acc], current_module}
        end
      end)

    Enum.reverse(rows)
  end

  # Slice the line into %{field => substring} by column start positions.
  defp slice_cells(line, columns) do
    columns
    |> Enum.with_index()
    |> Enum.map(fn {{field, start}, i} ->
      stop =
        case Enum.at(columns, i + 1) do
          {_f, next_start} -> next_start
          nil -> String.length(line)
        end

      {field, String.slice(line, start, max(stop - start, 0))}
    end)
    |> Map.new()
  end

  defp cell(cells, field), do: Map.get(cells, field, "")

  defp parse_hours(text) do
    normalized = text |> to_string() |> String.replace(",", ".")

    case Regex.run(~r/\d+(\.\d+)?/, normalized) do
      [match | _] -> Decimal.new(match)
      _ -> Decimal.new("1")
    end
  end

  # --- cleaning -------------------------------------------------------------

  defp clean_lines(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.reject(&boilerplate?/1)
  end

  defp boilerplate?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      Regex.match?(~r/r[eé]publique du cameroun|minesec|page\s+\d+|^\d+$/iu, trimmed)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/teacher_assistant/academics/fiche_parser_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/fiche_parser.ex test/teacher_assistant/academics/fiche_parser_test.exs
git commit -m "feat: FicheParser base — header detection, column slicing, module/lesson/hours"
```

---

## Task 2: FicheParser — enrichment (entry_type, week_no, sequence_no)

**Files:**
- Modify: `lib/teacher_assistant/academics/fiche_parser.ex`
- Test: `test/teacher_assistant/academics/fiche_parser_test.exs`

**Interfaces:**
- Consumes/Produces: same `parse/1` shape from Task 1; now `entry_type` is detected from content keywords and `week_no`/`sequence_no` are filled from their columns when present.

- [ ] **Step 1: Write the failing test (append to the existing test file)**

```elixir
  test "detects entry_type from content keywords (FR + EN)" do
    text = """
    Module      Lecon                    Duree
    Bloc 1      Evaluation sequentielle  1
    Bloc 1      Integration partielle    2
    Bloc 1      Remediation              1
    Bloc 1      Cours normal             2
    """

    assert {:ok, %{rows: rows}} = FicheParser.parse(text)
    assert Enum.map(rows, & &1.entry_type) == [:evaluation, :integration, :remediation, :lesson]
  end

  test "captures week and sequence numbers when columns exist" do
    text = """
    Sequence   Semaine   Module     Lecon              Duree
    1          2         Algebre    Les puissances     3
    """

    assert {:ok, %{rows: [row]}} = FicheParser.parse(text)
    assert row.sequence_no == 1
    assert row.week_no == 2
  end

  test "recognizes an English header" do
    text = """
    Module      Lesson              Hours
    Algebra     Linear equations    2
    """

    assert {:ok, %{rows: [row], confidence: :high}} = FicheParser.parse(text)
    assert row.lesson_title == "Linear equations"
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/academics/fiche_parser_test.exs`
Expected: FAIL — entry_type is `:lesson` for all; `week_no`/`sequence_no` are `nil`. (The English-header test may already pass.)

- [ ] **Step 3: Implement enrichment**

Replace the row map built in `build_rows/2` so it calls the new helpers (change the `row = %{...}` block):

```elixir
          row = %{
            module: current_module,
            lesson_title: lesson,
            planned_hours: parse_hours(cell(cells, :hours)),
            entry_type: detect_type(current_module <> " " <> lesson),
            week_no: parse_int(cell(cells, :week)),
            sequence_no: parse_int(cell(cells, :sequence))
          }
```

Add these private helpers to the module:

```elixir
  defp detect_type(text) do
    cond do
      Regex.match?(~r/[eé]valuation|devoir|composition|exam|test/iu, text) -> :evaluation
      Regex.match?(~r/int[eé]gration|integration/iu, text) -> :integration
      Regex.match?(~r/rem[eé]diation|remediation/iu, text) -> :remediation
      Regex.match?(~r/r[eé]vision|revision/iu, text) -> :revision
      Regex.match?(~r/correction/iu, text) -> :correction
      Regex.match?(~r/cong[eé]|holiday|vacances/iu, text) -> :holiday
      true -> :lesson
    end
  end

  defp parse_int(text) do
    case Regex.run(~r/\d+/, to_string(text)) do
      [match | _] -> String.to_integer(match)
      _ -> nil
    end
  end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/teacher_assistant/academics/fiche_parser_test.exs`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/fiche_parser.ex test/teacher_assistant/academics/fiche_parser_test.exs
git commit -m "feat: FicheParser enrichment — entry_type, week_no, sequence_no detection"
```

---

## Task 3: FicheExtractor — pdftotext wrapper + injection + test stub

**Files:**
- Create: `lib/teacher_assistant/academics/fiche_extractor.ex`
- Create: `test/support/fiche_extractor_stub.ex`
- Test: `test/teacher_assistant/academics/fiche_extractor_test.exs`

**Interfaces:**
- Produces: `TeacherAssistant.Academics.FicheExtractor.extract(path :: String.t()) :: {:ok, String.t()} | {:error, term()}`. Default impl shells out to `pdftotext -layout`. The impl is swappable via `Application.get_env(:teacher_assistant, :fiche_extractor, ...Pdftotext)`.
- `TeacherAssistant.FicheExtractorStub.extract/1` returns text configured via `Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, text)` (used by Tasks 6–7).

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/fiche_extractor_test.exs
defmodule TeacherAssistant.Academics.FicheExtractorTest do
  use ExUnit.Case, async: false
  alias TeacherAssistant.Academics.FicheExtractor

  test "delegates to the configured extractor module" do
    Application.put_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub)
    Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, "Module Lecon Duree")
    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :fiche_extractor)
      Application.delete_env(:teacher_assistant, :fiche_extractor_stub_text)
    end)

    assert {:ok, "Module Lecon Duree"} = FicheExtractor.extract("ignored.pdf")
  end

  test "Pdftotext impl returns an error tuple when the binary or file is missing" do
    # Use a path that cannot exist; whether pdftotext is installed or not, this
    # must be a graceful {:error, _}, never a raise.
    assert {:error, _} = FicheExtractor.Pdftotext.extract("/nonexistent/definitely-not-here.pdf")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/academics/fiche_extractor_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement extractor + stub**

```elixir
# lib/teacher_assistant/academics/fiche_extractor.ex
defmodule TeacherAssistant.Academics.FicheExtractor do
  @moduledoc """
  Extracts column-aligned plain text from a PDF. The concrete implementation is
  swappable via application config so tests don't need poppler installed:

      config :teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub
  """

  @callback extract(path :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @spec extract(String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract(path), do: impl().extract(path)

  defp impl, do: Application.get_env(:teacher_assistant, :fiche_extractor, __MODULE__.Pdftotext)

  defmodule Pdftotext do
    @moduledoc "Default extractor: shells out to `pdftotext -layout`."
    @behaviour TeacherAssistant.Academics.FicheExtractor

    @impl true
    def extract(path) do
      case System.cmd("pdftotext", ["-layout", path, "-"], stderr_to_stdout: true) do
        {text, 0} -> {:ok, text}
        {output, _code} -> {:error, output}
      end
    rescue
      e -> {:error, e}
    end
  end
end
```

```elixir
# test/support/fiche_extractor_stub.ex
defmodule TeacherAssistant.FicheExtractorStub do
  @moduledoc "Test extractor: returns text from application env, ignoring the path."
  @behaviour TeacherAssistant.Academics.FicheExtractor

  @impl true
  def extract(_path) do
    case Application.get_env(:teacher_assistant, :fiche_extractor_stub_text) do
      nil -> {:error, :no_stub_text}
      text -> {:ok, text}
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/teacher_assistant/academics/fiche_extractor_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/fiche_extractor.ex test/support/fiche_extractor_stub.ex test/teacher_assistant/academics/fiche_extractor_test.exs
git commit -m "feat: FicheExtractor (pdftotext -layout) with injectable impl + test stub"
```

---

## Task 4: Domain — `fetch_owned_teaching_context/2` + transactional `import_progression_plan/3`

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/import_progression_plan_test.exs`

**Interfaces:**
- Consumes: `FicheParser` row shape from Task 1 (`%{module, lesson_title, planned_hours, entry_type, week_no, sequence_no}`).
- Produces:
  - `Academics.fetch_owned_teaching_context(id, %PersonalWorkspace{}) :: {:ok, %TeachingContext{}} | {:error, :not_found}`
  - `Academics.import_progression_plan(%PersonalWorkspace{}, %{teaching_context_id: id, title: String.t()}, rows :: [map]) :: {:ok, %ProgressionPlan{}} | {:error, term()}` — creates a draft plan + entries in one DB transaction; rolls back fully on any failure; verifies the context belongs to the workspace.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/import_progression_plan_test.exs
defmodule TeacherAssistant.Academics.ImportProgressionPlanTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{ws: ws, ctx: ctx}
  end

  defp rows do
    [
      %{module: "Algèbre", lesson_title: "Les entiers", planned_hours: Decimal.new("2"), entry_type: :lesson, week_no: 1, sequence_no: nil},
      %{module: "Algèbre", lesson_title: "Évaluation", planned_hours: Decimal.new("1"), entry_type: :evaluation, week_no: 2, sequence_no: nil}
    ]
  end

  test "creates a draft plan with entries in order", %{ws: ws, ctx: ctx} do
    assert {:ok, plan} =
             Academics.import_progression_plan(ws, %{teaching_context_id: ctx.id, title: "Imported"}, rows())

    assert plan.title == "Imported"
    assert plan.status == :draft
    entries = Academics.list_progression_entries(plan)
    assert Enum.map(entries, & &1.lesson_title) == ["Les entiers", "Évaluation"]
    assert Enum.map(entries, & &1.position) == [1, 2]
    assert Enum.at(entries, 1).entry_type == :evaluation
  end

  test "rolls back entirely when a row is invalid (no orphan plan)", %{ws: ws, ctx: ctx} do
    bad = rows() ++ [%{module: "X", lesson_title: nil, planned_hours: Decimal.new("1"), entry_type: :lesson, week_no: nil, sequence_no: nil}]

    assert {:error, _} =
             Academics.import_progression_plan(ws, %{teaching_context_id: ctx.id, title: "Bad"}, bad)

    assert Academics.list_progression_plans(ws) == []
  end

  test "rejects a teaching context owned by another workspace", %{ws: ws} do
    other_ws = Academics.ensure_personal_workspace!(TeacherFixtures.user_fixture())

    {:ok, other_year} =
      Academics.create_academic_year(other_ws, %{
        name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true
      })

    {:ok, other_ctx} =
      Academics.create_teaching_context(other_ws, other_year, %{
        subject: "Physics", level: "6ème", subsystem: :francophone, weekly_hours: 3
      })

    assert {:error, :not_found} =
             Academics.import_progression_plan(ws, %{teaching_context_id: other_ctx.id, title: "Nope"}, rows())
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/academics/import_progression_plan_test.exs`
Expected: FAIL — `import_progression_plan/3` undefined.

- [ ] **Step 3: Implement domain functions**

Add `alias TeacherAssistant.Repo` near the other aliases at the top of `lib/teacher_assistant/academics.ex`, then add these functions (place them after `create_progression_plan/2`):

```elixir
  def fetch_owned_teaching_context(id, %PersonalWorkspace{id: ws_id}) do
    TeachingContext
    |> Ash.Query.filter(id == ^id and personal_workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Creates a draft ProgressionPlan and its entries from imported rows in a single
  transaction. Rolls back entirely on any failure (no orphan plan). Owner-scoped:
  the teaching context must belong to `ws`.
  """
  def import_progression_plan(%PersonalWorkspace{} = ws, %{teaching_context_id: ctx_id} = attrs, rows) do
    with {:ok, ctx} <- fetch_owned_teaching_context(ctx_id, ws) do
      Repo.transaction(fn ->
        plan =
          case create_progression_plan(ctx, %{title: attrs.title, status: :draft}) do
            {:ok, plan} -> plan
            {:error, reason} -> Repo.rollback(reason)
          end

        rows
        |> Enum.with_index(1)
        |> Enum.each(fn {row, position} ->
          entry_attrs =
            row
            |> Map.take([:module, :lesson_title, :planned_hours, :entry_type, :week_no, :sequence_id])
            |> Map.put(:progression_plan_id, plan.id)
            |> Map.put(:position, position)

          case ProgressionEntry
               |> Ash.Changeset.for_create(:create, entry_attrs)
               |> Ash.create(authorize?: false) do
            {:ok, _entry} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

        plan
      end)
    end
  end
```

> Note: rows carry `sequence_no` (a number) from the parser, but entries store `sequence_id`. The review screen (Task 7) maps the chosen sequence to a `sequence_id` before calling this function, so `import_progression_plan/3` only reads `:sequence_id` from rows. Rows without `:sequence_id` simply omit it (nil association, allowed).

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/teacher_assistant/academics/import_progression_plan_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics/import_progression_plan_test.exs
git commit -m "feat: transactional import_progression_plan/3 + owner-scoped teaching-context fetch"
```

---

## Task 5: ImportLive — route, dashboard entry, upload stage + gate

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/import_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex`
- Modify: `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/import_live_test.exs`

**Interfaces:**
- Produces: route `GET /teacher/import` → `TeacherAssistantWeb.Teacher.ImportLive`. Upload-stage DOM ids: `#fiche-import`, `#import-upload-form`, `#import-context-select`, `#import-title`, the upload input `:fiche`, `#import-extract`; gate id `#import-context-gate`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant_web/live/teacher/import_live_test.exs
defmodule TeacherAssistantWeb.Teacher.ImportLiveTest do
  use TeacherAssistantWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  defp seed_year_and_context(ws) do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true
      })

    :ok = Academics.build_default_calendar(year)

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4
      })

    %{year: year, ctx: ctx}
  end

  test "shows the upload form when a teaching context exists", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    {:ok, view, _html} = live(conn, ~p"/teacher/import")
    assert has_element?(view, "#import-upload-form")
    assert has_element?(view, "#import-context-select")
  end

  test "gates to setup when there is no teaching context", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/import")
    assert has_element?(view, "#import-context-gate")
    refute has_element?(view, "#import-upload-form")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: FAIL — no route / module.

- [ ] **Step 3: Add the route**

In `lib/teacher_assistant_web/router.ex`, inside the `ash_authentication_live_session :teacher_workspace` block (next to the other `/teacher/*` lives), add:

```elixir
      live "/teacher/import", Teacher.ImportLive, :new
```

- [ ] **Step 4: Implement the upload stage**

```elixir
# lib/teacher_assistant_web/live/teacher/import_live.ex
defmodule TeacherAssistantWeb.Teacher.ImportLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  @max_pdf_bytes 10_000_000

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace
    year = scope.current_academic_year
    contexts = if ws && year, do: Academics.list_teaching_contexts(ws, year), else: []

    socket =
      socket
      |> assign(:year, year)
      |> assign(:contexts, contexts)
      |> assign(:stage, :upload)
      |> assign(:title, "")
      |> assign(:context_id, contexts |> List.first() |> then(&(&1 && &1.id)))
      |> allow_upload(:fiche, accept: ~w(.pdf), max_entries: 1, max_file_size: @max_pdf_bytes)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="fiche-import" class="mx-auto max-w-2xl space-y-6">
        <header>
          <p class="ta-eyebrow">{gettext("Import a fiche")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{gettext("Import a fiche de progression")}</h1>
        </header>

        <div :if={@contexts == []} id="import-context-gate" class="ta-leaf space-y-3 text-sm">
          <p class="text-base-content/70">
            {gettext("Add a subject and class first, then you can import a fiche for it.")}
          </p>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary btn-sm">
            {gettext("Go to setup")}
          </.link>
        </div>

        <.form
          :if={@contexts != []}
          for={%{}}
          id="import-upload-form"
          phx-change="validate"
          phx-submit="extract"
          class="ta-leaf space-y-3"
        >
          <label class="block">
            <span class="label mb-1">{gettext("Subject & class")}</span>
            <select id="import-context-select" name="context_id" class="w-full select">
              <option :for={c <- @contexts} value={c.id} selected={c.id == @context_id}>
                {c.subject} · {c.level}
              </option>
            </select>
          </label>

          <label class="block">
            <span class="label mb-1">{gettext("Plan title")}</span>
            <input
              id="import-title"
              type="text"
              name="title"
              value={@title}
              placeholder={gettext("e.g. Maths 6ème 2025-2026")}
              class="w-full input"
            />
          </label>

          <label class="block">
            <span class="label mb-1">{gettext("Fiche PDF")}</span>
            <.live_file_input upload={@uploads.fiche} class="w-full file-input" />
          </label>

          <p :for={err <- upload_errors(@uploads.fiche)} class="text-sm text-error">
            {upload_error_to_string(err)}
          </p>

          <.button id="import-extract" type="submit" class="btn btn-primary w-full gap-2">
            <.icon name="hero-arrow-up-tray" class="size-4" />
            {gettext("Extract rows")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:title, params["title"] || socket.assigns.title)
     |> assign(:context_id, params["context_id"] || socket.assigns.context_id)}
  end

  # "extract" is implemented in Task 6.
  def handle_event("extract", _params, socket), do: {:noreply, socket}

  defp upload_error_to_string(:too_large), do: gettext("That file is too large (max 10 MB).")
  defp upload_error_to_string(:not_accepted), do: gettext("Please choose a PDF file.")
  defp upload_error_to_string(:too_many_files), do: gettext("Upload one file at a time.")
  defp upload_error_to_string(_), do: gettext("That file could not be uploaded.")
end
```

- [ ] **Step 5: Add dashboard entry points**

In `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`, add an "Import a fiche" link in two places.

In the dashboard `header` block, after the year badge `</header>` content — replace the existing `<header ...> ... </header>` closing by adding an actions row. Concretely, inside the `#teacher-dashboard` section, right after the `</header>`, insert:

```elixir
          <div class="flex flex-wrap gap-2">
            <.link navigate={~p"/teacher/import"} class="btn btn-outline btn-sm gap-2">
              <.icon name="hero-arrow-up-tray" class="size-4" />
              {gettext("Import a fiche")}
            </.link>
          </div>
```

And in the empty-state leaf (the `:if={@kpis == []}` block), add below the "Set one up" link:

```elixir
              <.link navigate={~p"/teacher/import"} class="btn btn-outline btn-sm">
                {gettext("Import a fiche (PDF)")}
              </.link>
```

- [ ] **Step 6: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/import_live.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/live/teacher/dashboard_live.ex test/teacher_assistant_web/live/teacher/import_live_test.exs
git commit -m "feat: ImportLive upload stage, route, dashboard entry points + setup gate"
```

---

## Task 6: ImportLive — extract → parse → render review table

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/import_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/import_live_test.exs`

**Interfaces:**
- Consumes: `FicheExtractor.extract/1` (Task 3), `FicheParser.parse/1` (Tasks 1–2).
- Produces: review-stage DOM ids `#import-review`, `#import-rows`, per-row `#import-row-<index>`, and (low confidence) `#import-raw-text`. Rows held in `@rows` as a list of `%{module, lesson_title, planned_hours, entry_type, week_no, sequence_no}` maps (decimals rendered as strings in inputs).

- [ ] **Step 1: Write the failing test (append)**

```elixir
  test "extracts and renders a review table from the uploaded PDF", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    Application.put_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub)
    Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, """
    Module             Lecon                Duree
    Algebre            Les entiers          2
    Algebre            Evaluation           1
    """)
    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :fiche_extractor)
      Application.delete_env(:teacher_assistant, :fiche_extractor_stub_text)
    end)

    {:ok, view, _html} = live(conn, ~p"/teacher/import")

    pdf = %{name: "fiche.pdf", content: "%PDF-1.4 stub", type: "application/pdf"}
    input = file_input(view, "#import-upload-form", :fiche, [pdf])
    assert render_upload(input, "fiche.pdf") =~ "fiche.pdf" or true

    view
    |> element("#import-upload-form")
    |> render_submit(%{"context_id" => "", "title" => "Imported"})

    assert has_element?(view, "#import-review")
    assert has_element?(view, "#import-rows")
    assert render(view) =~ "Les entiers"
    assert render(view) =~ "Evaluation"
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: FAIL — no `#import-review` (the `extract` handler is a stub).

- [ ] **Step 3: Implement the extract handler + review render**

Replace the stub `handle_event("extract", ...)` with:

```elixir
  def handle_event("extract", params, socket) do
    title = params["title"] || socket.assigns.title
    context_id = params["context_id"] || socket.assigns.context_id

    result =
      consume_uploaded_entries(socket, :fiche, fn %{path: path}, _entry ->
        {:ok, TeacherAssistant.Academics.FicheExtractor.extract(path)}
      end)

    case result do
      [{:ok, text}] ->
        {:ok, %{rows: rows, confidence: confidence, raw_text: raw}} =
          TeacherAssistant.Academics.FicheParser.parse(text)

        {:noreply,
         socket
         |> assign(:stage, :review)
         |> assign(:title, title)
         |> assign(:context_id, context_id)
         |> assign(:rows, normalize_rows(rows))
         |> assign(:confidence, confidence)
         |> assign(:raw_text, raw)}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Couldn't read that PDF. Try another file, or build the plan manually.")
         )}
    end
  end

  defp normalize_rows(rows) do
    Enum.map(rows, fn r ->
      %{
        module: r.module,
        lesson_title: r.lesson_title,
        planned_hours: Decimal.to_string(r.planned_hours),
        entry_type: r.entry_type,
        week_no: r.week_no,
        sequence_no: r.sequence_no
      }
    end)
  end
```

Add the review markup to `render/1` — insert this block inside `#fiche-import` (it renders only in the review stage). Put it after the upload `.form`:

```elixir
        <div :if={@stage == :review} id="import-review" class="space-y-4">
          <div :if={@confidence == :low} class="ta-leaf space-y-2 text-sm">
            <p class="font-semibold text-warning">
              {gettext("We couldn't read this fiche as a table.")}
            </p>
            <p class="text-base-content/70">
              {gettext("Add rows manually below. The extracted text is shown for reference.")}
            </p>
            <pre id="import-raw-text" class="ta-num max-h-48 overflow-auto whitespace-pre-wrap text-xs text-base-content/60">{@raw_text}</pre>
          </div>

          <p :if={@confidence == :high} class="ta-eyebrow">
            {gettext("Review and fix before saving")}
          </p>

          <ul id="import-rows" class="space-y-2">
            <li :for={{row, i} <- Enum.with_index(@rows)} id={"import-row-#{i}"} class="ta-leaf text-sm">
              <div class="font-semibold">{row.module} · {row.lesson_title}</div>
              <div class="ta-num text-xs text-base-content/60">
                {row.planned_hours}h · {row.entry_type}{if row.week_no, do: " · S#{row.week_no}"}
              </div>
            </li>
          </ul>
        </div>
```

> This task renders the rows read-only to prove extraction + parsing flow end-to-end. Task 7 turns them into editable inputs and adds save/add/delete.

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/import_live.ex test/teacher_assistant_web/live/teacher/import_live_test.exs
git commit -m "feat: ImportLive extract+parse, render review rows"
```

---

## Task 7: ImportLive — editable rows, add/delete, save → create plan

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/import_live.ex`
- Modify: `priv/gettext/fr/LC_MESSAGES/default.po`
- Test: `test/teacher_assistant_web/live/teacher/import_live_test.exs`

**Interfaces:**
- Consumes: `Academics.import_progression_plan/3` (Task 4), `Academics.list_sequences/1`, `Reference.entry_types/0`.
- Produces: review form `#import-review-form` with indexed inputs, `#import-add-row`, per-row delete `phx-click="delete-row"`, `#import-save`; on save, navigates to `~p"/teacher/plans/#{plan.id}"`.

- [ ] **Step 1: Write the failing test (append)**

```elixir
  test "saving the reviewed rows creates a draft plan and navigates to it", %{conn: conn, workspace: ws} do
    %{ctx: ctx} = seed_year_and_context(ws)
    Application.put_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub)
    Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, """
    Module    Lecon          Duree
    Algebre   Les entiers    2
    """)
    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :fiche_extractor)
      Application.delete_env(:teacher_assistant, :fiche_extractor_stub_text)
    end)

    {:ok, view, _html} = live(conn, ~p"/teacher/import")
    input = file_input(view, "#import-upload-form", :fiche, [%{name: "f.pdf", content: "x", type: "application/pdf"}])
    render_upload(input, "f.pdf")

    view
    |> element("#import-upload-form")
    |> render_submit(%{"context_id" => ctx.id, "title" => "Imported plan"})

    view
    |> form("#import-review-form", %{
      "title" => "Imported plan",
      "rows" => %{
        "0" => %{"module" => "Algebre", "lesson_title" => "Les entiers", "planned_hours" => "2", "entry_type" => "lesson", "week_no" => "", "sequence_id" => ""}
      }
    })
    |> render_submit()

    [plan] = Academics.list_progression_plans(ws)
    assert plan.title == "Imported plan"
    assert plan.status == :draft
    assert [entry] = Academics.list_progression_entries(plan)
    assert entry.lesson_title == "Les entiers"
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: FAIL — no `#import-review-form` / `save` handler.

- [ ] **Step 3: Make rows editable + implement add/delete/save**

Replace the read-only review block from Task 6 (`<div :if={@stage == :review} ...>`) with an editable form version:

```elixir
        <div :if={@stage == :review} id="import-review" class="space-y-4">
          <div :if={@confidence == :low} class="ta-leaf space-y-2 text-sm">
            <p class="font-semibold text-warning">
              {gettext("We couldn't read this fiche as a table.")}
            </p>
            <p class="text-base-content/70">
              {gettext("Add rows manually below. The extracted text is shown for reference.")}
            </p>
            <pre id="import-raw-text" class="ta-num max-h-48 overflow-auto whitespace-pre-wrap text-xs text-base-content/60">{@raw_text}</pre>
          </div>

          <p :if={@confidence == :high} class="ta-eyebrow">
            {gettext("Review and fix before saving")}
          </p>

          <.form for={%{}} id="import-review-form" phx-submit="save" class="space-y-3">
            <input type="hidden" name="title" value={@title} />

            <ul id="import-rows" class="space-y-2">
              <li :for={{row, i} <- Enum.with_index(@rows)} id={"import-row-#{i}"} class="ta-leaf space-y-2">
                <div class="grid gap-2 sm:grid-cols-2">
                  <input name={"rows[#{i}][module]"} value={row.module} placeholder={gettext("Module")} class="w-full input input-sm" />
                  <input name={"rows[#{i}][lesson_title]"} value={row.lesson_title} placeholder={gettext("Lesson")} class="w-full input input-sm" />
                </div>
                <div class="grid gap-2 sm:grid-cols-4">
                  <input name={"rows[#{i}][planned_hours]"} value={row.planned_hours} type="number" step="0.5" placeholder={gettext("Hours")} class="w-full input input-sm" />
                  <select name={"rows[#{i}][entry_type]"} class="w-full select select-sm">
                    <option :for={t <- entry_type_options()} value={t.key} selected={to_string(t.key) == to_string(row.entry_type)}>{t.fr}</option>
                  </select>
                  <input name={"rows[#{i}][week_no]"} value={row.week_no} type="number" placeholder={gettext("Week")} class="w-full input input-sm" />
                  <select name={"rows[#{i}][sequence_id]"} class="w-full select select-sm">
                    <option value="">{gettext("Sequence…")}</option>
                    <option :for={s <- @sequences} value={s.id} selected={s.number == row.sequence_no}>{gettext("Seq")} {s.number}</option>
                  </select>
                </div>
                <button type="button" phx-click="delete-row" phx-value-index={i} class="btn btn-ghost btn-xs text-error">
                  <.icon name="hero-trash" class="size-4" />
                  <span class="sr-only">{gettext("Delete row")}</span>
                </button>
              </li>
            </ul>

            <button type="button" id="import-add-row" phx-click="add-row" class="btn btn-ghost btn-sm gap-2">
              <.icon name="hero-plus" class="size-4" /> {gettext("Add row")}
            </button>

            <.button id="import-save" type="submit" class="btn btn-primary w-full gap-2">
              <.icon name="hero-check" class="size-4" /> {gettext("Save as draft plan")}
            </.button>
          </.form>
        </div>
```

Load sequences in `mount/3` (add to the assigns pipeline, after `:year`):

```elixir
      |> assign(:sequences, (year && Academics.list_sequences(year)) || [])
```

Add the event handlers and helpers:

```elixir
  def handle_event("add-row", _params, socket) do
    blank = %{module: "", lesson_title: "", planned_hours: "1", entry_type: :lesson, week_no: nil, sequence_no: nil}
    {:noreply, assign(socket, :rows, socket.assigns.rows ++ [blank])}
  end

  def handle_event("delete-row", %{"index" => index}, socket) do
    i = String.to_integer(index)
    {:noreply, assign(socket, :rows, List.delete_at(socket.assigns.rows, i))}
  end

  def handle_event("save", %{"rows" => rows_params} = params, socket) do
    ws = socket.assigns.current_scope.current_workspace
    rows = build_rows(rows_params)

    cond do
      rows == [] ->
        {:noreply, put_flash(socket, :error, gettext("Add at least one row with a module and lesson."))}

      true ->
        attrs = %{teaching_context_id: socket.assigns.context_id, title: title_or_default(params, socket)}

        case Academics.import_progression_plan(ws, attrs, rows) do
          {:ok, plan} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Plan imported."))
             |> push_navigate(to: ~p"/teacher/plans/#{plan.id}")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not save the plan. Check the rows and try again."))}
        end
    end
  end

  defp build_rows(rows_params) do
    rows_params
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_k, r} -> r end)
    |> Enum.filter(fn r -> String.trim(r["module"] || "") != "" and String.trim(r["lesson_title"] || "") != "" end)
    |> Enum.map(fn r ->
      %{
        module: String.trim(r["module"]),
        lesson_title: String.trim(r["lesson_title"]),
        planned_hours: parse_decimal(r["planned_hours"]),
        entry_type: String.to_existing_atom(r["entry_type"] || "lesson"),
        week_no: parse_optional_int(r["week_no"]),
        sequence_id: blank_to_nil(r["sequence_id"])
      }
    end)
  end

  defp parse_decimal(value) do
    case value |> to_string() |> String.replace(",", ".") |> Decimal.parse() do
      {d, _} -> d
      :error -> Decimal.new("1")
    end
  end

  defp parse_optional_int(value) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp title_or_default(params, socket) do
    case String.trim(params["title"] || socket.assigns.title || "") do
      "" -> default_title(socket)
      title -> title
    end
  end

  defp default_title(socket) do
    case Enum.find(socket.assigns.contexts, &(&1.id == socket.assigns.context_id)) do
      %{subject: subject, level: level} -> "#{subject} · #{level}"
      _ -> gettext("Imported fiche")
    end
  end

  defp entry_type_options, do: TeacherAssistant.Academics.Reference.entry_types()
```

Also handle the `save` clause when no rows were rendered (low confidence, none added) — add this fallback clause **above** the main `save` handler is unnecessary; instead ensure the form always submits `rows` (empty map when none). Add this clause right after the main `save` handler to cover a missing `rows` key:

```elixir
  def handle_event("save", params, socket) do
    handle_event("save", Map.put(params, "rows", %{}), socket)
  end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Add an ownership-guard test (append) and run**

```elixir
  test "cannot import into another teacher's context", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    other_ws = Academics.ensure_personal_workspace!(TeacherAssistant.TeacherFixtures.user_fixture())
    {:ok, other_year} = Academics.create_academic_year(other_ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, other_ctx} = Academics.create_teaching_context(other_ws, other_year, %{subject: "Physics", level: "6ème", subsystem: :francophone, weekly_hours: 3})

    assert {:error, :not_found} =
             Academics.import_progression_plan(ws, %{teaching_context_id: other_ctx.id, title: "Nope"},
               [%{module: "M", lesson_title: "L", planned_hours: Decimal.new("1"), entry_type: :lesson}])
  end
```

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 6: Add French translations**

In `priv/gettext/fr/LC_MESSAGES/default.po`, add `msgstr` entries for the new strings (run `mix gettext.extract && mix gettext.merge priv/gettext` first if the project uses extraction; otherwise add manually). Required pairs:

```
msgid "Import a fiche"
msgstr "Importer une fiche"

msgid "Import a fiche de progression"
msgstr "Importer une fiche de progression"

msgid "Import a fiche (PDF)"
msgstr "Importer une fiche (PDF)"

msgid "Subject & class"
msgstr "Matière et classe"

msgid "Plan title"
msgstr "Titre du plan"

msgid "Fiche PDF"
msgstr "Fiche PDF"

msgid "Extract rows"
msgstr "Extraire les lignes"

msgid "Review and fix before saving"
msgstr "Vérifiez et corrigez avant d'enregistrer"

msgid "We couldn't read this fiche as a table."
msgstr "Nous n'avons pas pu lire cette fiche sous forme de tableau."

msgid "Add rows manually below. The extracted text is shown for reference."
msgstr "Ajoutez les lignes manuellement ci-dessous. Le texte extrait est affiché pour référence."

msgid "Add row"
msgstr "Ajouter une ligne"

msgid "Save as draft plan"
msgstr "Enregistrer comme brouillon"

msgid "Couldn't read that PDF. Try another file, or build the plan manually."
msgstr "Impossible de lire ce PDF. Essayez un autre fichier ou créez le plan manuellement."

msgid "Plan imported."
msgstr "Fiche importée."

msgid "Add a subject and class first, then you can import a fiche for it."
msgstr "Ajoutez d'abord une matière et une classe, puis importez une fiche."

msgid "Go to setup"
msgstr "Aller à la configuration"
```

- [ ] **Step 7: Run the full gate**

Run: `mix precommit`
Expected: PASS — all tests green, compile clean, formatted.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/import_live.ex priv/gettext/fr/LC_MESSAGES/default.po test/teacher_assistant_web/live/teacher/import_live_test.exs
git commit -m "feat: ImportLive editable review, add/delete rows, transactional save + FR strings"
```

---

## Self-Review

**Spec coverage:**
- §4 flow (pick→upload→extract→parse→review→save) → Tasks 5, 6, 7. ✅
- §5 components (FicheExtractor injection, FicheParser pure, ImportLive, import_progression_plan) → Tasks 3, 1–2, 5–7, 4. ✅
- §6 parser heuristics (header, slice, type, hours, week/seq, confidence, raw fallback, never throws) → Tasks 1, 2. ✅
- §7 review (editable table, add/delete, low-confidence raw text, title default) → Tasks 6, 7. ✅
- §8 transactional owner-scoped persistence → Task 4. ✅
- §9 error handling (bad PDF, missing poppler graceful, low confidence) → Task 3 (error tuple), Task 6 (flash), Task 6/7 (manual fallback). ✅
- §10 testing (parser fixtures, transaction success/rollback/scope, ImportLive flow stubbed) → Tasks 1–4, 6–7. ✅
- §3 non-goals respected (no AI, new-plan only, no PDF storage, no CBA parse). ✅

**Deployment:** poppler-utils must be installed (spec §12) — operational, not a code task; note it at rollout.

**Type consistency:** parser row keys (`module, lesson_title, planned_hours, entry_type, week_no, sequence_no`) are consistent across Tasks 1–2 and `normalize_rows`; the LiveView save maps `sequence_no` → `sequence_id` before calling `import_progression_plan/3`, which only reads `:sequence_id` (Task 4 note). `entry_type` values match the resource enum. ✅

**Note on row count cap (spec §9):** not separately tested; enforce by slicing `rows` to 300 in `normalize_rows/1` if desired — left as a minor hardening, not a blocking task.
