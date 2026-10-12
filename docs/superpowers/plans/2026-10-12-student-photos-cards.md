# Student Photos & School ID Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let school-life staff photograph a whole class fast from a phone (chained séance or per-student grid), show the photos in the app, on bulletins (frozen at publication) and on printable ID cards.

**Architecture:** Photos are JPEG files under `uploads_dir/student_photos/<workspace_id>/<uuid>.jpg`, never overwritten; `Student.photo_path` points at the current one and bulletin snapshots (v4) keep the path of the moment. The browser crops/compresses to 600×800 JPEG and uploads through a LiveView auto-upload; one JS hook (`PhotoStudio`) owns crop, séance camera and a retry queue. Files are served by an authenticated controller; cards are a standalone print HTML page like the bulletin print.

**Tech Stack:** Phoenix 1.8 LiveView uploads, Ash 3 (AshPostgres, policies), vanilla JS (canvas, getUserMedia, Wake Lock), daisyUI/Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-10-12-student-photos-cards-design.md` (read §13 Amendments — they override earlier sections).

## Global Constraints

- Who may add/remove photos and print cards: admin axis (`:head`, `:vice_principal`) and conduct axis (`:discipline_master`) — gate `Enrollment.can_manage_register?/1`; policy `{Checks.SchoolRole, any_of: :conduct}` (conduct axis includes head and vice principal).
- Server accepts only JPEG (magic bytes `FF D8 FF`), max **1 000 000 bytes**.
- Client output: **JPEG 600 × 800, quality 0.85**, file named `<student_id>.jpg`.
- Storage path: `student_photos/<workspace_id>/<uuidv7>.jpg` relative to `uploads_dir`. Never overwrite or delete photo files.
- Snapshot version becomes **4**; per-student snapshot entries gain `photo_path`.
- Card: **85.6 × 54 mm**, A4 portrait, **2 × 5 = 10** per page, crop marks.
- Migrations: never by hand — `mix ash.codegen --dev` while iterating, then `mix ash.codegen student_photos` at the end of Task 1.
- Work in a worktree (`.claude/worktrees/photos`, branch `feat/student-photos`) with `MIX_TEST_PARTITION=7`; stage explicit paths only (never `git commit -a`).
- Every new user-facing string through `gettext`; after `mix gettext.extract --merge`, fill EN and unflag every fuzzy entry (guard: `test/teacher_assistant_web/gettext_fuzzy_test.exs`).
- No inline `<script>` in templates; JS lives in `assets/js/` and is imported by `app.js`.
- Finish with `mix precommit` (it does NOT fail on warnings in tests output — also run `mix compile --warnings-as-errors`).

## Review Focus

1. **Upload for a student outside the class** (crafted file name) → refused, no file written, flash shown. Test in Task 3.
2. **Replacing a photo after publication** → the published bulletin still serves the old file; the draft shows the new one. Test in Task 6.
3. **Another school's member requests a photo URL** (current or frozen) → 404, never the file. Tests in Tasks 2 and 6.
4. **Non-JPEG / oversized / empty file reaching the server** (JS bypassed) → `{:error, :invalid_image | :too_large}`, nothing stored. Test in Task 1.
5. **Old snapshots (v1–v3) and students without photos** → bulletin prints without image and without broken `<img>`; card shows the empty « Photo » box. Tests in Tasks 6 and 7.

---

## File map

| File | Responsibility |
|---|---|
| `lib/teacher_assistant/uploads.ex` (new) | `dir/0`, `resolve/1` — the only safe relative→absolute path mapping |
| `lib/teacher_assistant/student_photos.ex` (new) | `store/3`, `remove/2` — file side effects + action call |
| `lib/teacher_assistant/academics/student.ex` | attributes, `:set_photo`, `:remove_photo`, policy |
| `lib/teacher_assistant/enrollment.ex` | code interfaces `set_student_photo`, `remove_student_photo` |
| `lib/teacher_assistant_web/controllers/school_logo_controller.ex` | use `Uploads.resolve/1` |
| `lib/teacher_assistant_web/controllers/student_photo_controller.ex` (new) | `show` (current), `frozen` (bulletin) |
| `lib/teacher_assistant_web/components/student_photo_components.ex` (new) | `student_avatar/1`, `student_photo_url/1`, `photo_studio/1` markup |
| `lib/teacher_assistant_web/live/school/class_photos_live.ex` (new) | grid, sheet, upload progress, séance queue |
| `assets/js/hooks/photo_studio.js` (new) | crop, camera séance, upload/retry queue |
| `assets/js/app.js` | register `PhotoStudio` |
| `lib/teacher_assistant/report_cards.ex`, `academics/bulletin_publication.ex`, `academics/bulletin_element.ex` | snapshot v4, `:photo` element |
| `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`, `bulletin_print_html/show.html.heex` | photo on bulletin |
| `lib/teacher_assistant_web/controllers/card_print_controller.ex`, `card_print_html.ex`, `card_print_html/show.html.heex` (new) | ID cards |
| `lib/teacher_assistant_web/router.ex` | 4 GET routes + 1 live route |

---

### Task 0: Worktree

- [ ] **Step 1:** Create the worktree and branch.

```bash
git -C /Users/franckstfiler/Documents/projects/teacher-assistant worktree add .claude/worktrees/photos -b feat/student-photos
cd .claude/worktrees/photos && mix deps.get && MIX_TEST_PARTITION=7 mix ecto.reset && MIX_TEST_PARTITION=7 mix test --max-failures 1
```

Expected: green baseline (≈1616 tests).

---

### Task 1: Data, storage and `StudentPhotos`

**Files:**
- Create: `lib/teacher_assistant/uploads.ex`, `lib/teacher_assistant/student_photos.ex`, `test/support/fixtures/files/1x1.jpg`, `test/teacher_assistant/student_photos_test.exs`
- Modify: `lib/teacher_assistant/academics/student.ex`, `lib/teacher_assistant/enrollment.ex:24-26`, `lib/teacher_assistant_web/controllers/school_logo_controller.ex`

**Interfaces:**
- Produces: `TeacherAssistant.Uploads.dir/0 :: String.t()`, `Uploads.resolve(String.t() | nil) :: {:ok, abs_path} | :error`;
  `StudentPhotos.store(Scope.t(), Student.t(), tmp_path) :: {:ok, Student.t()} | {:error, :too_large | :invalid_image | term}`;
  `StudentPhotos.remove(Scope.t(), Student.t()) :: {:ok, Student.t()} | {:error, term}`;
  `Enrollment.set_student_photo(student, %{photo_path: rel}, scope: scope)`, `Enrollment.remove_student_photo(student, scope: scope)`;
  `Student.photo_path :: String.t() | nil`, `Student.photo_taken_at :: DateTime.t() | nil`.

- [ ] **Step 1: JPEG fixture**

```bash
sips -s format jpeg test/support/fixtures/files/1x1.png --out test/support/fixtures/files/1x1.jpg
head -c 3 test/support/fixtures/files/1x1.jpg | xxd   # expect ffd8ff
```

- [ ] **Step 2: Write the failing tests** — `test/teacher_assistant/student_photos_test.exs`

```elixir
defmodule TeacherAssistant.StudentPhotosTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, StudentPhotos, Uploads}
  alias TeacherAssistant.TeacherFixtures

  @jpeg "test/support/fixtures/files/1x1.jpg"
  @png "test/support/fixtures/files/1x1.png"

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, st} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f})
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    %{scope: scope, cg: cg, st: st, sg: sg}
  end

  defp tmp_copy(src) do
    path = Path.join(System.tmp_dir!(), "ta-photo-#{System.unique_integer([:positive])}")
    File.cp!(src, path)
    path
  end

  defp stored_files(scope) do
    Path.join([Uploads.dir(), "student_photos", scope.current_workspace.id, "*.jpg"])
    |> Path.wildcard()
  end

  test "the SG stores a JPEG and the student points at it", %{sg: sg, st: st} do
    assert {:ok, updated} = StudentPhotos.store(sg, st, tmp_copy(@jpeg))
    assert updated.photo_path =~ ~r{^student_photos/#{sg.current_workspace.id}/.+\.jpg$}
    assert %DateTime{} = updated.photo_taken_at
    assert {:ok, abs} = Uploads.resolve(updated.photo_path)
    assert File.read!(abs) == File.read!(@jpeg)
  end

  test "replacing keeps the previous file", %{sg: sg, st: st} do
    {:ok, first} = StudentPhotos.store(sg, st, tmp_copy(@jpeg))
    {:ok, second} = StudentPhotos.store(sg, first, tmp_copy(@jpeg))
    refute first.photo_path == second.photo_path
    assert {:ok, _} = Uploads.resolve(first.photo_path)
  end

  test "a non-JPEG is refused and nothing is stored", %{sg: sg, st: st} do
    assert {:error, :invalid_image} = StudentPhotos.store(sg, st, tmp_copy(@png))
    assert stored_files(sg) == []
  end

  test "an empty file is refused", %{sg: sg, st: st} do
    path = tmp_copy(@jpeg)
    File.write!(path, "")
    assert {:error, :invalid_image} = StudentPhotos.store(sg, st, path)
  end

  test "a file over 1 MB is refused", %{sg: sg, st: st} do
    path = tmp_copy(@jpeg)
    File.write!(path, [<<0xFF, 0xD8, 0xFF>>, :binary.copy(<<0>>, 1_000_000)])
    assert {:error, :too_large} = StudentPhotos.store(sg, st, path)
  end

  test "a teacher or a form master is forbidden and the copied file is removed",
       %{scope: scope, cg: cg, st: st} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(scope, cg, teacher.current_user.id)

    assert {:error, %Ash.Error.Forbidden{}} = StudentPhotos.store(teacher, st, tmp_copy(@jpeg))
    assert stored_files(teacher) == []
  end

  test "remove clears the pointer but keeps the file", %{sg: sg, st: st} do
    {:ok, with_photo} = StudentPhotos.store(sg, st, tmp_copy(@jpeg))
    assert {:ok, removed} = StudentPhotos.remove(sg, with_photo)
    assert removed.photo_path == nil and removed.photo_taken_at == nil
    assert {:ok, _} = Uploads.resolve(with_photo.photo_path)
  end

  test "resolve refuses paths escaping the uploads dir" do
    assert :error = Uploads.resolve("../../etc/passwd")
    assert :error = Uploads.resolve(nil)
  end
end
```

Note: check `Enrollment.set_form_master/3`'s return shape in `enrollment.ex` and adapt the match if it returns `:ok`.

- [ ] **Step 3: Run — expect failure**

Run: `MIX_TEST_PARTITION=7 mix test test/teacher_assistant/student_photos_test.exs`
Expected: compile error, `TeacherAssistant.StudentPhotos` undefined.

- [ ] **Step 4: `Uploads`** — `lib/teacher_assistant/uploads.ex`

```elixir
defmodule TeacherAssistant.Uploads do
  @moduledoc "The uploads directory and the one safe way to turn a stored relative path into a file."

  def dir, do: :teacher_assistant |> Application.fetch_env!(:uploads_dir) |> Path.expand()

  @doc "The absolute path of a stored relative path, or `:error` when it escapes `dir/0` or is not a regular file."
  def resolve(relative) when is_binary(relative) do
    root = dir()
    path = Path.expand(Path.join(root, relative))

    if String.starts_with?(path, root <> "/") and File.regular?(path),
      do: {:ok, path},
      else: :error
  end

  def resolve(_), do: :error
end
```

In `SchoolLogoController`, delete `safe_logo_path/1` and replace `{:ok, path} <- safe_logo_path(stored)` with `{:ok, path} <- TeacherAssistant.Uploads.resolve(stored)`.

- [ ] **Step 5: Student resource** — in `student.ex` `attributes`, after `birth_place`:

```elixir
    attribute :photo_path, :string, allow_nil?: true, public?: true, constraints: [max_length: 255]
    attribute :photo_taken_at, :utc_datetime_usec, allow_nil?: true, public?: true
```

In `actions`, after `defaults`:

```elixir
    # Spec 2026-10-12 §2: photo files are written by `StudentPhotos`, never overwritten.
    update :set_photo do
      accept [:photo_path]
      require_atomic? false
      change set_attribute(:photo_taken_at, &DateTime.utc_now/0)
    end

    update :remove_photo do
      accept []
      change set_attribute(:photo_path, nil)
      change set_attribute(:photo_taken_at, nil)
    end
```

In `policies`, add (it applies together with the `action_type(:update)` policy, so the form-master clause no longer suffices):

```elixir
    policy action([:set_photo, :remove_photo]) do
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
```

In `enrollment.ex` `resource Student do`:

```elixir
      define :set_student_photo, action: :set_photo
      define :remove_student_photo, action: :remove_photo
```

- [ ] **Step 6: `StudentPhotos`** — `lib/teacher_assistant/student_photos.ex`

```elixir
defmodule TeacherAssistant.StudentPhotos do
  @moduledoc """
  Spec 2026-10-12 §3: student photo files. A file is never overwritten or
  deleted — published bulletins may still point at it.
  """
  alias TeacherAssistant.{Enrollment, Scope, Uploads}
  alias TeacherAssistant.Academics.Student

  @max_bytes 1_000_000

  def store(%Scope{current_workspace: %{id: ws_id}} = scope, %Student{} = student, tmp_path) do
    with :ok <- check_size(tmp_path),
         :ok <- check_jpeg(tmp_path) do
      relative = Path.join(["student_photos", ws_id, Ash.UUIDv7.generate() <> ".jpg"])
      dest = Path.join(Uploads.dir(), relative)
      dest |> Path.dirname() |> File.mkdir_p!()
      File.cp!(tmp_path, dest)

      case Enrollment.set_student_photo(student, %{photo_path: relative}, scope: scope) do
        {:ok, updated} ->
          {:ok, updated}

        {:error, error} ->
          File.rm(dest)
          {:error, error}
      end
    end
  end

  def remove(%Scope{} = scope, %Student{} = student),
    do: Enrollment.remove_student_photo(student, scope: scope)

  defp check_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_bytes -> {:error, :too_large}
      {:ok, %{size: size}} when size > 0 -> :ok
      _ -> {:error, :invalid_image}
    end
  end

  defp check_jpeg(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 3)) do
      {:ok, <<0xFF, 0xD8, 0xFF>>} -> :ok
      _ -> {:error, :invalid_image}
    end
  end
end
```

- [ ] **Step 7: Migration** — `MIX_TEST_PARTITION=7 mix ash.codegen --dev` then `MIX_TEST_PARTITION=7 mix ash.migrate`.

- [ ] **Step 8: Run** — `MIX_TEST_PARTITION=7 mix test test/teacher_assistant/student_photos_test.exs test/teacher_assistant_web/live/school/settings_logo_test.exs` → PASS.

- [ ] **Step 9: Final migration name** — squash dev migrations: `mix ash.codegen student_photos` (per house rule: `--dev` while iterating, named codegen at the end). Re-run Step 8.

- [ ] **Step 10: Commit**

```bash
git add lib/teacher_assistant/uploads.ex lib/teacher_assistant/student_photos.ex lib/teacher_assistant/academics/student.ex lib/teacher_assistant/enrollment.ex lib/teacher_assistant_web/controllers/school_logo_controller.ex priv/repo/migrations priv/resource_snapshots test/support/fixtures/files/1x1.jpg test/teacher_assistant/student_photos_test.exs
git commit -m "feat: student photo storage — set/remove actions, JPEG-only store, shared uploads path guard"
```

---

### Task 2: Serve photos and show avatars

**Files:**
- Create: `lib/teacher_assistant_web/controllers/student_photo_controller.ex`, `lib/teacher_assistant_web/components/student_photo_components.ex`, `test/teacher_assistant_web/controllers/student_photo_controller_test.exs`
- Modify: `router.ex` (scope with `get "/school/logo"`, ≈line 88), `class_live.ex:165`, `students_live.ex:256`, `student_live.ex:341`

**Interfaces:**
- Consumes: `StudentPhotos.store/3`, `Uploads.resolve/1`, `Enrollment.fetch_owned_student/2`.
- Produces: route `GET /school/students/:id/photo`; `StudentPhotoController.send_photo(conn, abs_path)` (public, reused by `frozen` in Task 6); `StudentPhotoComponents.student_avatar/1` (attrs `student` (map with `id, full_name, photo_path, photo_taken_at`), `class`), `student_photo_url/1 :: String.t()`.

- [ ] **Step 1: Failing tests** — controller test

```elixir
defmodule TeacherAssistantWeb.StudentPhotoControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, st} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f})
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
    {:ok, st} = StudentPhotos.store(scope, st, tmp)
    %{scope: scope, cg: cg, st: st}
  end

  test "a member gets the current photo, privately cached", %{conn: conn, st: st} do
    conn = get(conn, ~p"/school/students/#{st.id}/photo")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/jpeg"
    assert get_resp_header(conn, "cache-control") == ["private, max-age=86400"]
    assert conn.resp_body == File.read!("test/support/fixtures/files/1x1.jpg")
  end

  test "a student without photo is a 404", %{conn: conn, scope: scope, cg: cg} do
    {:ok, other} = Enrollment.add_student(scope, cg, %{full_name: "Ben", sex: :m})
    assert get(conn, ~p"/school/students/#{other.id}/photo").status == 404
  end

  test "another school's member gets a 404", %{st: st} do
    %{head_user: other_head, workspace: other_ws} = TeacherFixtures.setup_complete_school_fixture()

    conn =
      build_conn()
      |> log_in_user(other_head)
      |> Plug.Conn.put_session(:workspace_id, other_ws.id)
      |> get(~p"/school/students/#{st.id}/photo")

    assert conn.status == 404
  end
end
```

Add to the existing class roster test file (find it with `grep -rl '"/school/classes/#{' test/teacher_assistant_web/live/school/class_live*`) a test: after `StudentPhotos.store`, `render(view)` contains `~s(src="/school/students/#{st.id}/photo?v=)`.

- [ ] **Step 2: Run** — expect route/compile failures.

- [ ] **Step 3: Controller**

```elixir
defmodule TeacherAssistantWeb.StudentPhotoController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.{Enrollment, Uploads}

  @doc "Spec 2026-10-12 §4: the student's current photo, for members of the student's school."
  def show(conn, %{"id" => id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, %{photo_path: relative}} when is_binary(relative) <-
           Enrollment.fetch_owned_student(scope, id),
         {:ok, path} <- Uploads.resolve(relative) do
      send_photo(conn, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  def send_photo(conn, path) do
    conn
    |> put_resp_content_type("image/jpeg")
    |> put_resp_header("cache-control", "private, max-age=86400")
    |> send_file(200, path)
  end
end
```

Router, next to `get "/school/logo"`: `get "/school/students/:id/photo", StudentPhotoController, :show`.

- [ ] **Step 4: Components**

```elixir
defmodule TeacherAssistantWeb.StudentPhotoComponents do
  @moduledoc "Spec 2026-10-12 §5/§7: student avatars and the photo studio markup."
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use Phoenix.VerifiedRoutes,
    endpoint: TeacherAssistantWeb.Endpoint,
    router: TeacherAssistantWeb.Router,
    statics: TeacherAssistantWeb.static_paths()

  import TeacherAssistantWeb.CoreComponents, only: [initials_avatar: 1]

  @doc "The current photo URL; `v` changes with each new photo so caches never serve a replaced one."
  def student_photo_url(%{id: id} = student) do
    case Map.get(student, :photo_taken_at) do
      %DateTime{} = at -> ~p"/school/students/#{id}/photo?v=#{DateTime.to_unix(at)}"
      _ -> ~p"/school/students/#{id}/photo"
    end
  end

  attr :student, :map, required: true
  attr :class, :string, default: "size-8 text-xs"

  def student_avatar(assigns) do
    ~H"""
    <img
      :if={is_binary(Map.get(@student, :photo_path))}
      src={student_photo_url(@student)}
      alt=""
      loading="lazy"
      class={["shrink-0 rounded-full bg-base-300 object-cover", @class]}
    />
    <.initials_avatar
      :if={!is_binary(Map.get(@student, :photo_path))}
      name={@student.full_name}
      class={@class}
    />
    """
  end
end
```

(If `TeacherAssistantWeb` exposes `:verified_routes` via `use TeacherAssistantWeb, :verified_routes`, use that instead of the explicit `use Phoenix.VerifiedRoutes`.)

- [ ] **Step 5: Use the avatar** — in `class_live.ex`, `students_live.ex`, `student_live.ex`: `import TeacherAssistantWeb.StudentPhotoComponents, only: [student_avatar: 1]` and replace
  - `class_live.ex:165` `<.initials_avatar name={row.student.full_name} />` → `<.student_avatar student={row.student} />`
  - `students_live.ex:256` → `<.student_avatar student={e.student} />`
  - `student_live.ex:341` → `<.student_avatar student={@student} class="size-14 text-lg" />`

- [ ] **Step 6: Run** — new tests + `test/teacher_assistant_web/live/school` → PASS.

- [ ] **Step 7: Commit** — `git add` the 3 LiveViews, controller, components, router, tests; message `feat: serve student photos and show them as avatars`.

---

### Task 3: Class photos page — grid, server upload, delete

**Files:**
- Create: `lib/teacher_assistant_web/live/school/class_photos_live.ex`, `test/teacher_assistant_web/live/school/class_photos_live_test.exs`
- Modify: `router.ex` (live_session `:school_workspace`, after `live "/school/classes/:id"`), `class_live.ex` (mount assign + `<:actions>` link), `register_live.ex` (mount assign + `<:actions>` slot with link)

**Interfaces:**
- Consumes: `StudentPhotos.store/3`, `StudentPhotos.remove/2`, `Enrollment.list_roster/2` (rows `%{student, enrollment}`), `Enrollment.can_manage_register?/1`, `student_avatar/1`.
- Produces: live route `/school/classes/:id/photos`; upload name `:photo` inside form `#photo-upload-form`; DOM ids `#photo-count`, `#only-missing`, `#photo-<student_id>` (card), `#photo-sheet`, `#remove-photo`, `#confirm-remove-photo`, `#start-session`; events pushed to the client: `"photo:stored" %{student_id}`, `"photo:failed" %{student_id, message}`; assign `:queue` (list of `%{id, name}`) and `:redo_all?` used by Task 5.

- [ ] **Step 1: Failing tests**

```elixir
defmodule TeacherAssistantWeb.School.ClassPhotosLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistant.TeacherFixtures

  @jpeg "test/support/fixtures/files/1x1.jpg"

  setup do
    %{scope: scope, year: year, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f})
    {:ok, ben} = Enrollment.add_student(scope, cg, %{full_name: "Ben Ateba", sex: :m})
    {:ok, other_cg} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})
    {:ok, outsider} = Enrollment.add_student(scope, other_cg, %{full_name: "Zoe", sex: :f})
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    %{scope: scope, ws: ws, cg: cg, awa: awa, ben: ben, outsider: outsider, sg: sg}
  end

  defp conn_for(scope, ws),
    do: build_conn() |> log_in_user(scope.current_user) |> Plug.Conn.put_session(:workspace_id, ws.id)

  defp upload(view, name) do
    input =
      file_input(view, "#photo-upload-form", :photo, [
        %{name: name, content: File.read!(@jpeg), type: "image/jpeg"}
      ])

    render_upload(input, name)
  end

  test "the SG uploads a photo for a student of the class", %{sg: sg, ws: ws, cg: cg, awa: awa} do
    {:ok, view, html} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/photos")
    assert html =~ "0/2"

    upload(view, "#{awa.id}.jpg")

    assert {:ok, %{photo_path: path}} = Enrollment.fetch_owned_student(sg, awa.id)
    assert is_binary(path)
    assert view |> element("#photo-count") |> render() =~ "1/2"
    assert_push_event(view, "photo:stored", %{student_id: student_id})
    assert student_id == awa.id
  end

  test "a file named after a student of another class is refused",
       %{sg: sg, ws: ws, cg: cg, outsider: outsider} do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/photos")
    html = upload(view, "#{outsider.id}.jpg")

    assert html =~ "pas dans cette classe"
    assert {:ok, %{photo_path: nil}} = Enrollment.fetch_owned_student(sg, outsider.id)
  end

  test "filter and delete with in-page confirmation", %{sg: sg, ws: ws, cg: cg, awa: awa, ben: ben} do
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!(@jpeg, tmp)
    {:ok, _} = StudentPhotos.store(sg, awa, tmp)

    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/photos")
    view |> element("#only-missing") |> render_click()
    refute has_element?(view, "#photo-#{awa.id}")
    assert has_element?(view, "#photo-#{ben.id}")
    view |> element("#only-missing") |> render_click()

    view |> element("#photo-#{awa.id} button") |> render_click()
    view |> element("#remove-photo") |> render_click()
    view |> element("#confirm-remove-photo") |> render_click()

    assert {:ok, %{photo_path: nil}} = Enrollment.fetch_owned_student(sg, awa.id)
    assert view |> element("#photo-count") |> render() =~ "0/2"
  end

  test "a teacher is sent away and sees no Photos link", %{scope: scope, ws: ws, cg: cg} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(scope, cg, teacher.current_user.id)
    conn = conn_for(teacher, ws)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/photos")

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    refute has_element?(view, "#go-to-photos")
  end

  test "the SG finds the Photos link on the register tab", %{sg: sg, ws: ws, cg: cg} do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/register")
    assert has_element?(view, ~s(#go-to-photos[href="/school/classes/#{cg.id}/photos"]))
  end
end
```

(`setup_complete_school_fixture/0` returns `workspace`; the head's `scope` acts as admin. If `set_form_master` returns a different shape, adapt the match.)

- [ ] **Step 2: Run** — expect route error.

- [ ] **Step 3: LiveView** — `class_photos_live.ex`

```elixir
defmodule TeacherAssistantWeb.School.ClassPhotosLive do
  @moduledoc "Spec 2026-10-12 §7: a class's photos — grid, per-student sheet, chained séance."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistantWeb.Authz
  import TeacherAssistantWeb.StudentPhotoComponents

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Enrollment.can_manage_register?(scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id) do
      {:ok,
       socket
       |> assign(cg: cg, only_missing?: false, sheet: nil, confirm_remove?: false, redo_all?: false)
       |> assign(roster: Enrollment.list_roster(scope, cg))
       |> assign_queue()
       |> allow_upload(:photo,
         accept: ~w(.jpg .jpeg),
         max_entries: 5,
         max_file_size: 1_000_000,
         auto_upload: true,
         progress: &handle_progress/3
       )}
    else
      _ -> {:ok, socket |> Authz.put_not_allowed() |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_event("validate_photo", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_missing", _params, socket),
    do: {:noreply, update(socket, :only_missing?, &(!&1))}

  def handle_event("open_sheet", %{"id" => id}, socket),
    do: {:noreply, assign(socket, sheet: id, confirm_remove?: false)}

  def handle_event("close_sheet", _params, socket),
    do: {:noreply, assign(socket, sheet: nil, confirm_remove?: false)}

  def handle_event("ask_remove", _params, socket),
    do: {:noreply, assign(socket, confirm_remove?: true)}

  def handle_event("toggle_redo_all", _params, socket),
    do: {:noreply, socket |> update(:redo_all?, &(!&1)) |> assign_queue()}

  def handle_event("remove_photo", _params, socket) do
    with %{student: student} <- row(socket, socket.assigns.sheet),
         {:ok, updated} <- StudentPhotos.remove(socket.assigns.current_scope, student) do
      {:noreply, socket |> replace_student(updated) |> assign(sheet: nil, confirm_remove?: false)}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Impossible de supprimer la photo."))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :photo, ref)}

  defp handle_progress(:photo, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_progress(:photo, entry, socket) do
    student_id = Path.rootname(entry.client_name)

    case row(socket, student_id) do
      nil ->
        consume_uploaded_entry(socket, entry, fn _ -> {:ok, nil} end)
        {:noreply, failed(socket, student_id, gettext("Cet élève n'est pas dans cette classe."))}

      %{student: student} ->
        result =
          consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
            {:ok, StudentPhotos.store(socket.assigns.current_scope, student, tmp)}
          end)

        case result do
          {:ok, updated} ->
            {:noreply,
             socket
             |> replace_student(updated)
             |> assign(sheet: nil)
             |> push_event("photo:stored", %{student_id: student_id})}

          {:error, %Ash.Error.Forbidden{}} ->
            {:noreply, failed(socket, student_id, Authz.not_allowed_message())}

          {:error, _} ->
            {:noreply, failed(socket, student_id, gettext("Photo refusée : fichier JPEG d'1 Mo maximum."))}
        end
    end
  end

  defp failed(socket, student_id, message) do
    socket
    |> put_flash(:error, message)
    |> push_event("photo:failed", %{student_id: student_id, message: message})
  end

  defp row(socket, id), do: Enum.find(socket.assigns.roster, &(&1.student.id == id))

  defp replace_student(socket, updated) do
    socket
    |> update(:roster, fn rows ->
      Enum.map(rows, fn
        %{student: %{id: id}} = r when id == updated.id -> %{r | student: updated}
        r -> r
      end)
    end)
    |> assign_queue()
  end

  # Séance order (§7.2): without photo first, then — when redoing — everyone else; class list order.
  defp assign_queue(socket) do
    {missing, done} = Enum.split_with(socket.assigns.roster, &is_nil(&1.student.photo_path))
    rows = if socket.assigns.redo_all?, do: missing ++ done, else: missing
    assign(socket, :queue, Enum.map(rows, &%{id: &1.student.id, name: &1.student.full_name}))
  end

  defp with_photo(roster), do: Enum.count(roster, &is_binary(&1.student.photo_path))

  defp visible(roster, true), do: Enum.filter(roster, &is_nil(&1.student.photo_path))
  defp visible(roster, false), do: roster

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="class-photos" class="space-y-5">
        <.breadcrumb>
          <:crumb navigate={~p"/school/classes"}>{gettext("Classes")}</:crumb>
          <:crumb navigate={~p"/school/classes/#{@cg.id}"}>{@cg.label}</:crumb>
          <:crumb>{gettext("Photos")}</:crumb>
        </.breadcrumb>

        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="font-display text-3xl font-semibold leading-none">{gettext("Photos")}</h1>
            <p id="photo-count" class="ta-num mt-2 text-sm text-base-content/70">
              {gettext("%{done}/%{total} photos", done: with_photo(@roster), total: length(@roster))}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link navigate={~p"/school/classes/#{@cg.id}/cards/print"} id="go-to-cards" class="btn btn-ghost btn-sm">
              <.icon name="hero-identification" class="size-4" /> {gettext("Cartes scolaires")}
            </.link>
            <button
              id="start-session"
              type="button"
              class="btn btn-primary btn-sm gap-1.5"
              disabled={@queue == []}
              phx-click={Phoenix.LiveView.JS.dispatch("photo:session-start", to: "#photo-studio")}
            >
              <.icon name="hero-camera" class="size-4" /> {gettext("Lancer la séance")}
            </button>
          </div>
        </header>

        <div class="flex flex-wrap items-center gap-4 text-sm">
          <label class="flex cursor-pointer items-center gap-2">
            <input id="only-missing" type="checkbox" class="toggle toggle-sm" checked={@only_missing?} phx-click="toggle_missing" />
            {gettext("Sans photo uniquement")}
          </label>
          <label class="flex cursor-pointer items-center gap-2">
            <input id="redo-all" type="checkbox" class="toggle toggle-sm" checked={@redo_all?} phx-click="toggle_redo_all" />
            {gettext("Séance : refaire toute la classe")}
          </label>
        </div>

        <form id="photo-upload-form" phx-change="validate_photo" phx-submit="validate_photo" class="hidden">
          <.live_file_input upload={@uploads.photo} />
        </form>

        <ul :if={@uploads.photo.entries != []} id="photo-uploads" class="space-y-1 text-sm">
          <li :for={entry <- @uploads.photo.entries} class="flex items-center gap-2">
            <progress class="progress progress-primary w-24" value={entry.progress} max="100"></progress>
            <span :for={err <- upload_errors(@uploads.photo, entry)} class="text-error">{upload_error(err)}</span>
            <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_upload" phx-value-ref={entry.ref}>×</button>
          </li>
        </ul>

        <ul id="photo-grid" class="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
          <li :for={row <- visible(@roster, @only_missing?)} id={"photo-#{row.student.id}"} data-photo-drop={row.student.id}>
            <button
              type="button"
              phx-click="open_sheet"
              phx-value-id={row.student.id}
              class="group block w-full overflow-hidden rounded-box border border-base-300 bg-base-100 text-left transition hover:-translate-y-0.5 hover:shadow-md"
            >
              <div class="relative aspect-[3/4] bg-base-200">
                <img
                  :if={row.student.photo_path}
                  src={student_photo_url(row.student)}
                  alt=""
                  loading="lazy"
                  class="size-full object-cover"
                />
                <div :if={!row.student.photo_path} class="grid size-full place-items-center">
                  <.student_avatar student={row.student} class="size-16 text-xl" />
                  <span class="badge badge-warning badge-sm absolute bottom-2 left-2">{gettext("Sans photo")}</span>
                </div>
              </div>
              <p class="truncate px-2 py-1.5 text-sm font-medium">{row.student.full_name}</p>
            </button>
          </li>
        </ul>

        <.photo_sheet :if={@sheet} student={row_student(@roster, @sheet)} confirm_remove?={@confirm_remove?} />
        <.photo_studio id="photo-studio" queue={@queue} student_id={@sheet} />
      </section>
    </Layouts.app>
    """
  end

  defp row_student(roster, id), do: Enum.find_value(roster, &(&1.student.id == id && &1.student))

  defp upload_error(:too_large), do: gettext("Fichier trop lourd (1 Mo maximum).")
  defp upload_error(:not_accepted), do: gettext("Seules les photos JPEG sont acceptées.")
  defp upload_error(:too_many_files), do: gettext("Trop d'envois en même temps.")
  defp upload_error(_), do: gettext("Envoi impossible.")
end
```

Add to `StudentPhotoComponents` (studio markup is filled in by Task 4/5; here a minimal version keeps Task 3 green):

```elixir
  attr :student, :map, required: true
  attr :confirm_remove?, :boolean, default: false

  def photo_sheet(assigns) do
    ~H"""
    <div id="photo-sheet" class="fixed inset-0 z-40 flex items-end justify-center bg-black/40 sm:items-center" phx-window-keydown="close_sheet" phx-key="Escape">
      <div class="w-full max-w-sm space-y-3 rounded-t-box bg-base-100 p-4 shadow-xl sm:rounded-box" phx-click-away="close_sheet">
        <p class="font-semibold">{@student.full_name}</p>
        <button
          id="pick-photo"
          type="button"
          class="btn btn-primary w-full"
          phx-click={Phoenix.LiveView.JS.dispatch("photo:pick", to: "#photo-studio")}
        >
          <.icon name="hero-camera" class="size-4" /> {gettext("Prendre / choisir une photo")}
        </button>
        <button :if={@student.photo_path && !@confirm_remove?} id="remove-photo" type="button" class="btn btn-ghost w-full text-error" phx-click="ask_remove">
          {gettext("Supprimer la photo")}
        </button>
        <button :if={@confirm_remove?} id="confirm-remove-photo" type="button" class="btn btn-error w-full" phx-click="remove_photo">
          {gettext("Confirmer la suppression")}
        </button>
        <button type="button" class="btn btn-ghost w-full" phx-click="close_sheet">{gettext("Annuler")}</button>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :queue, :list, default: []
  attr :student_id, :string, default: nil

  def photo_studio(assigns) do
    ~H"""
    <div id={@id} phx-hook="PhotoStudio" data-student-id={@student_id} data-queue={Jason.encode!(@queue)}>
    </div>
    """
  end
```

Router: `live "/school/classes/:id/photos", School.ClassPhotosLive, :index` in the `:school_workspace` live_session.

Entry links: in `class_live.ex` mount add `can_manage_register?: Enrollment.can_manage_register?(scope)`, and as the first item of `<:actions>`:

```heex
          <.link
            :if={@can_manage_register?}
            navigate={~p"/school/classes/#{@cg.id}/photos"}
            id="go-to-photos"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Photos")}
          </.link>
```

Same assign in `register_live.ex` mount, and add a `<:actions>` slot with the same link inside `<.class_shell cg={@cg} shell={@shell} tab={:register}>` (register_live.ex:145).

- [ ] **Step 4: Run** — `MIX_TEST_PARTITION=7 mix test test/teacher_assistant_web/live/school/class_photos_live_test.exs test/teacher_assistant_web/live/school/class_shell_test.exs` → PASS.

- [ ] **Step 5: Commit** — explicit paths; `feat: class photos page — grid, upload, delete, entry links`.

---

### Task 4: `PhotoStudio` hook — upload queue + crop screen (grid & student page)

**Files:**
- Create: `assets/js/hooks/photo_studio.js`
- Modify: `assets/js/app.js`, `student_photo_components.ex` (`photo_studio/1` markup), `student_live.ex` (sheet + studio + upload for one student)
- Test: `test/teacher_assistant_web/live/school/student_live_test.exs` (add upload test)

**Interfaces:**
- Consumes: DOM contract from Task 3 (`#photo-upload-form` with upload `:photo`, `data-student-id`, `data-queue`, `data-photo-drop`, window events `photo:pick`, server events `photo:stored`/`photo:failed`).
- Produces: `PhotoStudio` hook with `this.submit(studentId, blob)` (crop → upload, queued, retried on reconnect) used by Task 5's séance.

- [ ] **Step 1: Studio markup** — replace `photo_studio/1` body (server renders static, translated labels; `phx-update="ignore"` keeps client state, container data attributes still update):

```heex
    <div id={@id} phx-hook="PhotoStudio" phx-update="ignore" data-student-id={@student_id} data-queue={Jason.encode!(@queue)}>
      <input type="file" accept="image/*" class="hidden" data-role="file" />

      <div data-role="crop" class="fixed inset-0 z-50 hidden flex-col items-center justify-center gap-4 bg-black/90 p-4 text-white">
        <p class="text-sm opacity-80">{gettext("Faites glisser pour cadrer, zoomez avec le curseur.")}</p>
        <canvas data-role="crop-canvas" width="600" height="800" class="aspect-[3/4] w-[min(80vw,22rem)] touch-none rounded-box bg-black"></canvas>
        <input data-role="zoom" type="range" min="1" max="3" step="0.01" value="1" class="range range-sm w-[min(80vw,22rem)]" aria-label={gettext("Zoom")} />
        <div class="flex gap-3">
          <button type="button" data-role="crop-cancel" class="btn btn-ghost">{gettext("Annuler")}</button>
          <button type="button" data-role="crop-ok" class="btn btn-primary">{gettext("Valider")}</button>
        </div>
      </div>

      <p data-role="pending" class="fixed bottom-4 right-4 z-50 hidden rounded-full bg-base-content px-3 py-1.5 text-sm text-base-100 shadow-lg"
         data-label-one={gettext("1 photo en cours d'envoi")}
         data-label-many={gettext("%{count} photos en cours d'envoi", count: "__N__")}
         data-label-failed={gettext("Réessayer")}></p>

      <%!-- Séance overlay: filled in Task 5. --%>
    </div>
```

(`gettext("... %{count} ...", count: "__N__")` keeps a placeholder the JS replaces.)

- [ ] **Step 2: Hook** — `assets/js/hooks/photo_studio.js`

```js
// Spec 2026-10-12 §7: crop / séance / upload queue for student photos.
// Output is always a 600×800 JPEG (q 0.85) named `<studentId>.jpg`.
const W = 600, H = 800, QUALITY = 0.85

export const toJpeg = (canvas) =>
  new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", QUALITY))

// Draws `source` (ImageBitmap | HTMLVideoElement) cover-fit into a W×H canvas,
// scaled by `zoom` and shifted by `dx, dy` (output pixels).
export function drawCover(ctx, source, sw, sh, zoom = 1, dx = 0, dy = 0) {
  const scale = Math.max(W / sw, H / sh) * zoom
  const w = sw * scale, h = sh * scale
  ctx.fillStyle = "#000"
  ctx.fillRect(0, 0, W, H)
  ctx.drawImage(source, (W - w) / 2 + dx, (H - h) / 2 + dy, w, h)
}

export const PhotoStudio = {
  mounted() {
    this.pending = new Map() // studentId -> File, until the server acks
    this.failed = new Set()
    this.$ = (role) => this.el.querySelector(`[data-role="${role}"]`)

    this.$("file").addEventListener("change", (e) => {
      const file = e.target.files[0]
      e.target.value = ""
      if (file) this.openCrop(file, this.targetId || this.el.dataset.studentId)
    })
    this.el.addEventListener("photo:pick", () => {
      this.targetId = this.el.dataset.studentId
      this.$("file").click()
    })

    this.onDragOver = (e) => { if (e.target.closest("[data-photo-drop]")) e.preventDefault() }
    this.onDrop = (e) => {
      const card = e.target.closest("[data-photo-drop]")
      const file = e.dataTransfer?.files?.[0]
      if (!card || !file) return
      e.preventDefault()
      this.openCrop(file, card.dataset.photoDrop)
    }
    document.addEventListener("dragover", this.onDragOver)
    document.addEventListener("drop", this.onDrop)

    this.setupCrop()
    this.handleEvent("photo:stored", ({student_id}) => {
      this.pending.delete(student_id)
      this.failed.delete(student_id)
      this.renderPending()
    })
    this.handleEvent("photo:failed", ({student_id}) => {
      if (this.pending.has(student_id)) this.failed.add(student_id)
      this.renderPending()
    })
    this.$("pending").addEventListener("click", () => this.retry())
    if (this.setupSession) this.setupSession()
  },

  reconnected() { this.retry() },

  destroyed() {
    document.removeEventListener("dragover", this.onDragOver)
    document.removeEventListener("drop", this.onDrop)
    this.stopCamera?.()
  },

  // --- queue -------------------------------------------------------------
  async submit(studentId, blob) {
    const file = new File([blob], `${studentId}.jpg`, {type: "image/jpeg"})
    this.pending.set(studentId, file)
    this.failed.delete(studentId)
    this.renderPending()
    this.upload("photo", [file])
  },

  retry() {
    for (const [id, file] of this.pending) {
      this.failed.delete(id)
      this.upload("photo", [file])
    }
    this.renderPending()
  },

  renderPending() {
    const el = this.$("pending")
    const n = this.pending.size
    el.classList.toggle("hidden", n === 0)
    if (n === 0) return
    const label = this.failed.size > 0
      ? el.dataset.labelFailed
      : (n === 1 ? el.dataset.labelOne : el.dataset.labelMany.replace("__N__", n))
    el.textContent = label
    el.classList.toggle("bg-error", this.failed.size > 0)
  },

  // --- crop ----------------------------------------------------------------
  setupCrop() {
    const canvas = this.$("crop-canvas"), zoom = this.$("zoom")
    this.cropCtx = canvas.getContext("2d")
    this.crop = null
    const redraw = () => {
      const c = this.crop
      if (c) drawCover(this.cropCtx, c.bitmap, c.bitmap.width, c.bitmap.height, c.zoom, c.dx, c.dy)
    }
    zoom.addEventListener("input", () => { if (this.crop) { this.crop.zoom = +zoom.value; redraw() } })
    let last = null
    canvas.addEventListener("pointerdown", (e) => { last = [e.clientX, e.clientY]; canvas.setPointerCapture(e.pointerId) })
    canvas.addEventListener("pointermove", (e) => {
      if (!last || !this.crop) return
      const k = W / canvas.getBoundingClientRect().width // screen px -> output px
      this.crop.dx += (e.clientX - last[0]) * k
      this.crop.dy += (e.clientY - last[1]) * k
      last = [e.clientX, e.clientY]
      redraw()
    })
    canvas.addEventListener("pointerup", () => { last = null })
    this.$("crop-cancel").addEventListener("click", () => this.closeCrop())
    this.$("crop-ok").addEventListener("click", async () => {
      const {studentId, onDone} = this.crop
      const blob = await toJpeg(canvas)
      this.closeCrop()
      this.submit(studentId, blob)
      onDone?.()
    })
    this.redrawCrop = redraw
  },

  async openCrop(file, studentId, onDone) {
    if (!studentId) return
    let bitmap
    try {
      bitmap = await createImageBitmap(file, {imageOrientation: "from-image"})
    } catch (_e) {
      this.pushEvent("photo_unreadable", {})
      return
    }
    this.crop = {bitmap, studentId, onDone, zoom: 1, dx: 0, dy: 0}
    this.$("zoom").value = 1
    this.$("crop").classList.replace("hidden", "flex")
    this.redrawCrop()
  },

  closeCrop() {
    this.crop?.bitmap.close?.()
    this.crop = null
    this.$("crop").classList.replace("flex", "hidden")
  },
}
```

Server side, add to `ClassPhotosLive` and `StudentLive`:

```elixir
  def handle_event("photo_unreadable", _params, socket),
    do: {:noreply, put_flash(socket, :error, gettext("Format d'image non pris en charge par ce navigateur."))}
```

- [ ] **Step 3: Register** — `assets/js/app.js`: `import {PhotoStudio} from "./hooks/photo_studio"` and `hooks: {...colocatedHooks, PhotoStudio},`.

- [ ] **Step 4: Student page** — in `student_live.ex`, for `@access == :manage` (assign name: use whatever mount assigns from `Enrollment.student_access/2`):
  - wrap the header avatar in `<button id="student-photo-button" phx-click="open_sheet" aria-label={gettext("Changer la photo")}>`;
  - render `<.photo_sheet :if={@sheet} student={@student} confirm_remove?={@confirm_remove?} />`, the hidden `#photo-upload-form` and `<.photo_studio id="photo-studio" student_id={@student.id} />`;
  - `allow_upload(:photo, …same options…, progress: &handle_progress/3)` only for `:manage`; `handle_progress` stores when `Path.rootname(entry.client_name) == @student.id`, otherwise fails like Task 3; `remove_photo`/`ask_remove`/`open_sheet`/`close_sheet` events as in Task 3 (single student, `sheet: true`).
  - add a « Carte scolaire » link when the student has a current-year enrollment: `~p"/school/classes/#{class_id}/cards/print?student=#{@student.id}"` (class id from the page's current enrollment).

  Test (in the student LiveView test file): SG uploads `"#{st.id}.jpg"` via `file_input(view, "#photo-upload-form", :photo, …)` → `photo_path` set; a teacher of the class (access `:read`) has no `#student-photo-button`.

  To avoid duplicating `handle_progress`/remove handlers between the two LiveViews, put them in `StudentPhotoComponents` as plain functions taking `(socket, student, entry)` and returning `{:ok, updated} | {:error, message}` (`store_entry/3`, `remove/2`), and keep the LiveViews' callbacks thin.

- [ ] **Step 5: Run** — LiveView tests for photos and student page → PASS; `mix assets.build` → no esbuild error.

- [ ] **Step 6: Manual check (Chrome, 390px, demo school as SG)** — grid: tap a card → sheet → choose a file → crop drag/zoom → Valider → thumbnail updates; desktop drop on a card; a PNG/HEIC from gallery is converted to JPEG (network tab shows `image/jpeg`); kill the server mid-upload → pill turns « Réessayer », restart → auto-retry on reconnect.

- [ ] **Step 7: Commit** — `feat: photo studio hook — crop, drop, upload queue with retry; student page photo`.

---

### Task 5: Séance enchaînée (camera)

**Files:**
- Modify: `assets/js/hooks/photo_studio.js`, `student_photo_components.ex` (séance overlay markup)

**Interfaces:**
- Consumes: `PhotoStudio.submit/2`, `openCrop/3`, `data-queue` (`[{id, name}]`), window event `photo:session-start` (Task 3 button).

- [ ] **Step 1: Overlay markup** — inside `photo_studio/1`, replace the Task 4 comment:

```heex
      <div data-role="session" class="fixed inset-0 z-50 hidden flex-col bg-black text-white">
        <header class="flex items-center justify-between gap-2 p-3">
          <div class="min-w-0">
            <p data-role="progress" class="ta-num text-xs opacity-70"></p>
            <p data-role="name" class="truncate text-lg font-semibold"></p>
          </div>
          <div class="flex gap-2">
            <button type="button" data-role="skip" class="btn btn-ghost btn-sm text-white">{gettext("Passer")}</button>
            <button type="button" data-role="quit" class="btn btn-ghost btn-sm text-white">{gettext("Quitter")}</button>
          </div>
        </header>
        <div class="relative flex-1 overflow-hidden">
          <video data-role="video" playsinline muted class="absolute inset-0 size-full object-cover"></video>
          <canvas data-role="still" width="600" height="800" class="absolute inset-0 m-auto hidden aspect-[3/4] h-full max-w-full"></canvas>
          <div class="pointer-events-none absolute inset-0 m-auto aspect-[3/4] h-[85%] max-w-[92%] rounded-box border-2 border-white/80">
            <div class="absolute left-1/2 top-[12%] h-[62%] w-[62%] -translate-x-1/2 rounded-[50%] border-2 border-dashed border-white/60"></div>
          </div>
          <p data-role="camera-error" class="absolute inset-x-4 top-1/3 hidden rounded-box bg-base-100 p-4 text-center text-base-content">
            {gettext("Caméra indisponible. Choisissez une photo à la place.")}
            <button type="button" data-role="fallback" class="btn btn-primary btn-sm mt-3 w-full">{gettext("Choisir une photo")}</button>
          </p>
        </div>
        <footer class="flex items-center justify-center gap-6 p-5">
          <button type="button" data-role="flip" class="btn btn-circle btn-ghost text-white" aria-label={gettext("Changer de caméra")}>
            <.icon name="hero-arrow-path" class="size-6" />
          </button>
          <button type="button" data-role="shutter" class="size-18 rounded-full border-4 border-white bg-white/20 transition active:scale-95" aria-label={gettext("Prendre la photo")}></button>
          <button type="button" data-role="retake" class="btn btn-ghost hidden text-white">{gettext("Reprendre")}</button>
          <button type="button" data-role="accept" class="btn btn-primary hidden">{gettext("Valider")} ✓</button>
        </footer>
        <div data-role="summary" class="absolute inset-0 hidden flex-col items-center justify-center gap-4 bg-black/95 p-6 text-center">
          <p data-role="summary-text" class="text-lg"
             data-template={gettext("%{taken} photos prises, %{skipped} passées", taken: "__T__", skipped: "__S__")}></p>
          <button type="button" data-role="summary-close" class="btn btn-primary">{gettext("Retour à la grille")}</button>
        </div>
      </div>
```

(Check `size-18` exists in the Tailwind v4 spacing scale — it does by default; otherwise use `size-[4.5rem]`.)

- [ ] **Step 2: Séance logic** — append to the `PhotoStudio` object in `photo_studio.js`:

```js
  setupSession() {
    const $ = this.$
    this.el.addEventListener("photo:session-start", () => this.startSession())
    $("quit").addEventListener("click", () => this.endSession())
    $("summary-close").addEventListener("click", () => this.closeSession())
    $("skip").addEventListener("click", () => { this.skipped++; this.next() })
    $("flip").addEventListener("click", () => {
      this.facing = this.facing === "environment" ? "user" : "environment"
      this.startCamera()
    })
    $("shutter").addEventListener("click", () => this.shoot())
    $("retake").addEventListener("click", () => this.showLive())
    $("accept").addEventListener("click", async () => {
      const blob = await toJpeg($("still"))
      this.submit(this.current().id, blob)
      this.taken++
      this.next()
    })
    $("fallback").addEventListener("click", () => {
      this.targetId = this.current().id
      this.afterCrop = () => { this.taken++; this.next() }
      this.$("file").click()
    })
    this.facing = "environment"
  },

  current() { return this.queue[this.index] },

  async startSession() {
    this.queue = JSON.parse(this.el.dataset.queue || "[]")
    if (this.queue.length === 0) return
    this.index = 0; this.taken = 0; this.skipped = 0
    this.$("session").classList.replace("hidden", "flex")
    this.$("summary").classList.replace("flex", "hidden")
    try { this.wakeLock = await navigator.wakeLock?.request("screen") } catch (_e) { this.wakeLock = null }
    await this.startCamera()
    this.showStudent()
  },

  async startCamera() {
    this.stopCamera()
    const video = this.$("video")
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {facingMode: this.facing, width: {ideal: 1280}, height: {ideal: 1280}}, audio: false,
      })
      video.srcObject = this.stream
      await video.play()
      this.$("camera-error").classList.add("hidden")
    } catch (_e) {
      this.$("camera-error").classList.remove("hidden")
    }
  },

  stopCamera() {
    this.stream?.getTracks().forEach((t) => t.stop())
    this.stream = null
  },

  showStudent() {
    const s = this.current()
    this.$("name").textContent = s.name
    this.$("progress").textContent = `${this.index + 1}/${this.queue.length}`
    this.showLive()
  },

  showLive() {
    for (const r of ["still", "retake", "accept"]) this.$(r).classList.add("hidden")
    for (const r of ["video", "shutter", "flip"]) this.$(r).classList.remove("hidden")
  },

  shoot() {
    const video = this.$("video")
    if (!video.videoWidth) return
    const ctx = this.$("still").getContext("2d")
    // The frame on screen is the centred 3:4 area of the cover-fitted video: same maths as drawCover.
    drawCover(ctx, video, video.videoWidth, video.videoHeight)
    for (const r of ["video", "shutter", "flip"]) this.$(r).classList.add("hidden")
    for (const r of ["still", "retake", "accept"]) this.$(r).classList.remove("hidden")
  },

  next() {
    this.index++
    if (this.index >= this.queue.length) return this.endSession()
    this.showStudent()
  },

  endSession() {
    this.stopCamera()
    this.wakeLock?.release?.()
    const el = this.$("summary-text")
    el.textContent = el.dataset.template.replace("__T__", this.taken).replace("__S__", this.skipped)
    this.$("summary").classList.replace("hidden", "flex")
  },

  closeSession() {
    this.$("session").classList.replace("flex", "hidden")
  },
```

And make the crop's « Valider » honour the séance fallback: in `setupCrop`'s `crop-ok` handler, after `onDone?.()` add `this.afterCrop?.(); this.afterCrop = null`.

Note on the framing: the visible frame is `h-[85%]` of the viewport while the capture takes the centred 3:4 area of the cover-fitted video at full height. Make them match: set the frame `div` to `inset-0 m-auto aspect-[3/4] h-full max-w-full` (no 85%), so WYSIWYG holds; keep the oval inside it.

- [ ] **Step 3: Build** — `mix assets.build` → OK.

- [ ] **Step 4: Manual check (Chrome phone emulation + a real phone on the LAN over HTTPS if available)** — Lancer la séance → name + `1/N` → shoot → Reprendre / Valider → next student instantly, pill counts uploads; Passer; Quitter → summary; refusing camera permission → fallback button → file → crop → next; « Séance : refaire toute la classe » includes students with photos; grid updates live after each ack.

- [ ] **Step 5: Commit** — `feat: chained photo séance with live camera, retake, skip and summary`.

---

### Task 6: Photo on the bulletin (frozen at publication)

**Files:**
- Modify: `academics/bulletin_element.ex`, `report_cards.ex:469-481` (`plain_entry/1`), `academics/bulletin_publication.ex:54,107`, `bulletin_print_controller.ex`, `bulletin_print_html/show.html.heex:23-25,87-118`, `student_photo_controller.ex`, `router.ex`
- Test: `test/teacher_assistant/report_cards_test.exs` (231, 301 → 4; new test), `test/teacher_assistant/academics/bulletin_template_test.exs:28`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`

**Interfaces:**
- Consumes: `StudentPhotos.store/3`, `StudentPhotoController.send_photo/2`, `Uploads.resolve/1`.
- Produces: route `GET /school/bulletins/:publication_id/photo/:student_id`; snapshot roster entry `student.photo_path`; bundle key `photo_url`.

- [ ] **Step 1: Failing tests**

In `report_cards_test.exs` change both `snapshot_version == 3` to `== 4` and add:

```elixir
  test "the snapshot freezes the student's photo path (v4)", ctx do
    %{scope: scope, cg: cg, term: term, st: st} = ctx
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
    {:ok, with_photo} = TeacherAssistant.StudentPhotos.store(scope, st, tmp)
    {:ok, _} = TeacherAssistant.Councils.hold(scope, cg, {:trimester, term})
    {:ok, pub} = ReportCards.publish(scope, cg, {:trimester, term})

    assert [%{student: %{photo_path: path}}] = pub.snapshot.roster
    assert path == with_photo.photo_path
  end
```

In `bulletin_template_test.exs:28` add `:photo` to `@new_elements`.

In `bulletin_print_controller_test.exs` (reuse its setup that publishes a trimester for a class with one student; read its first `describe`):

```elixir
  test "published bulletin keeps the photo of the publication; draft shows the current one", ctx do
    # ctx: conn (head), scope, cg, term, st — adapt names to the file's setup
    jpeg = "test/support/fixtures/files/1x1.jpg"
    tmp = fn -> p = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg"); File.cp!(jpeg, p); p end
    {:ok, first} = TeacherAssistant.StudentPhotos.store(ctx.scope, ctx.st, tmp.())
    {:ok, pub} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    {:ok, _second} = TeacherAssistant.StudentPhotos.store(ctx.scope, first, tmp.())

    html = ctx.conn |> get(~p"/school/classes/#{ctx.cg.id}/bulletin/print?period=#{"t#{ctx.term.id}"}") |> html_response(200)
    assert html =~ ~s(src="/school/bulletins/#{pub.id}/photo/#{ctx.st.id}")

    frozen = get(ctx.conn, ~p"/school/bulletins/#{pub.id}/photo/#{ctx.st.id}")
    {:ok, first_abs} = TeacherAssistant.Uploads.resolve(first.photo_path)
    assert frozen.status == 200
    assert frozen.resp_body == File.read!(first_abs)
  end

  test "a student published without photo prints no image", ctx do
    {:ok, _pub} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    html = ctx.conn |> get(~p"/school/classes/#{ctx.cg.id}/bulletin/print?period=#{"t#{ctx.term.id}"}") |> html_response(200)
    refute html =~ "student-photo"
  end

  test "photo_url/2: v1–v3 snapshot entries (no :photo_path key) give no image" do
    alias TeacherAssistantWeb.BulletinPrintController, as: C
    student = %{id: Ecto.UUID.generate(), full_name: "Awa"}
    assert C.photo_url(%{id: Ecto.UUID.generate()}, student) == nil
    assert C.photo_url(nil, Map.put(student, :photo_path, "x.jpg")) == "/school/students/#{student.id}/photo"
  end

  test "another school cannot read a frozen photo", ctx do
    {:ok, pub} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    %{head_user: h, workspace: w} = TeacherFixtures.setup_complete_school_fixture()
    conn = build_conn() |> log_in_user(h) |> Plug.Conn.put_session(:workspace_id, w.id)
    assert get(conn, ~p"/school/bulletins/#{pub.id}/photo/#{ctx.st.id}").status == 404
  end
```

Use the period param format the existing tests in that file use (copy it — `"t#{term.id}"` above is a guess).

- [ ] **Step 2: Run** — expect failures (version 3, no route, no photo).

- [ ] **Step 3: Element** — `bulletin_element.ex`: add `:photo` to `values` (after `:birth`), `def label(:photo), do: gettext("Photo de l'élève")`.

- [ ] **Step 4: Snapshot v4** — `report_cards.ex` `plain_entry/1` student map: add `photo_path: s.photo_path`. `bulletin_publication.ex:54` → `set_attribute(:snapshot_version, 4)`; comment at :107 append `; 4: adds student photo_path (spec 2026-10-12)`.

- [ ] **Step 5: Frozen route** — router: `get "/school/bulletins/:publication_id/photo/:student_id", StudentPhotoController, :frozen`. Controller:

```elixir
  alias TeacherAssistant.Academics.BulletinPublication

  @doc "Spec 2026-10-12 §4: the photo frozen in a published bulletin."
  def frozen(conn, %{"publication_id" => pub_id, "student_id" => student_id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, pub} <- Ash.get(BulletinPublication, pub_id, scope: scope),
         %{student: student} <-
           Enum.find(pub.snapshot.roster, &(&1.student.id == student_id)),
         {:ok, path} <- Uploads.resolve(Map.get(student, :photo_path)) do
      send_photo(conn, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end
```

(If the domain forbids `Ash.get` without a code interface, use the read the publication module already exposes, e.g. via `ReportCards` — grep `BulletinPublication` in `report_cards.ex`.) Note `Ash.get` raises nothing here: it returns `{:error, _}` for not found / forbidden, matched by `else`.

- [ ] **Step 6: Print** — `bulletin_print_controller.ex` bundle: add `photo_url: photo_url(pub, student),` and

```elixir
  @doc false
  # Spec 2026-10-12 §6: published → the frozen file; draft → the current one; none → no image.
  def photo_url(pub, student) do
    case {Map.get(student, :photo_path), pub} do
      {nil, _} -> nil
      {_, nil} -> ~p"/school/students/#{student.id}/photo"
      {_, pub} -> ~p"/school/bulletins/#{pub.id}/photo/#{student.id}"
    end
  end
```

`show.html.heex`: wrap the `<table class="cartouche">` (line 87) in

```heex
<div class="identity">
  <table class="cartouche">…unchanged…</table>
  <img :if={show?(@template, :photo) and b.photo_url} class="student-photo" src={b.photo_url} alt="" />
</div>
```

CSS (next to the cartouche rules ≈:23-25):

```css
.identity { display: flex; gap: 3mm; align-items: flex-start; }
.identity .cartouche { flex: 1; }
.student-photo { width: 25mm; height: 32mm; object-fit: cover; border: 0.3mm solid #000; }
```

- [ ] **Step 7: Run** — `report_cards_test`, `bulletin_template_test`, `bulletin_print_controller_test`, `bulletin_settings_test`, `official_header_test` → PASS (fix any test that enumerates `BulletinElement.values()` positions).

- [ ] **Step 8: Commit** — `feat: student photo on bulletins, frozen in snapshot v4`.

---

### Task 7: School ID cards (print)

**Files:**
- Create: `lib/teacher_assistant_web/controllers/card_print_controller.ex`, `card_print_html.ex`, `card_print_html/show.html.heex`, `test/teacher_assistant_web/controllers/card_print_controller_test.exs`
- Modify: `router.ex`

**Interfaces:**
- Consumes: `Enrollment.can_manage_register?/1`, `Enrollment.fetch_owned_class_group/2`, `Enrollment.list_roster/2`, `Enrollment.list_guardian_links/2` (main contact first), `Organization.class_year/2` (`.name`), `Accounts.fetch_school_profile/1` (`logo_path`, `signature_path`, `stamp_path`, `bulletin_language`), `BulletinPrintHTML.tr/2`, `student_photo_url/1`.
- Produces: `GET /school/classes/:id/cards/print[?student=<id>]`.

- [ ] **Step 1: Failing tests**

```elixir
defmodule TeacherAssistantWeb.CardPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f, matricule: "M1"})
    {:ok, ben} = Enrollment.add_student(scope, cg, %{full_name: "Ben Ateba", sex: :m})
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
    {:ok, awa} = StudentPhotos.store(scope, awa, tmp)
    {:ok, _g} = Enrollment.add_guardian(scope, awa, %{full_name: "Marie Ngono", phone: "677001122", relationship: :mother})
    %{scope: scope, cg: cg, awa: awa, ben: ben}
  end

  test "prints one card per student with photo, identity and contact", %{conn: conn, cg: cg, awa: awa} do
    html = conn |> get(~p"/school/classes/#{cg.id}/cards/print") |> html_response(200)
    assert html =~ "Awa Ngono" and html =~ "Ben Ateba" and html =~ "M1"
    assert html =~ ~s(src="/school/students/#{awa.id}/photo)
    assert html =~ "Marie Ngono" and html =~ "677001122"
    assert html =~ "1 élève sans photo"
    assert length(Regex.scan(~r/class="card"/, html)) == 2
  end

  test "?student= prints that student only", %{conn: conn, cg: cg, awa: awa} do
    html = conn |> get(~p"/school/classes/#{cg.id}/cards/print?student=#{awa.id}") |> html_response(200)
    assert html =~ "Awa Ngono"
    refute html =~ "Ben Ateba"
  end

  test "a student of another class is refused", %{conn: conn, scope: scope, cg: cg, year: year} do
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})
    {:ok, zoe} = Enrollment.add_student(scope, other, %{full_name: "Zoe", sex: :f})
    assert redirected_to(get(conn, ~p"/school/classes/#{cg.id}/cards/print?student=#{zoe.id}")) == ~p"/school/classes/#{cg.id}/photos"
  end

  test "a teacher is sent to /school", %{scope: scope, workspace: ws, cg: cg} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    conn = build_conn() |> log_in_user(teacher.current_user) |> Plug.Conn.put_session(:workspace_id, ws.id)
    assert redirected_to(get(conn, ~p"/school/classes/#{cg.id}/cards/print")) == ~p"/school"
  end
end
```

(Check `Enrollment.add_guardian/3`'s attrs and `GuardianRelationship` values; the first guardian added becomes main contact — verify, else call the "make primary" action.)

- [ ] **Step 2: Run** — expect route error.

- [ ] **Step 3: Controller**

```elixir
defmodule TeacherAssistantWeb.CardPrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.{Accounts, Enrollment, Organization}

  @doc "Spec 2026-10-12 §9: printable school ID cards, 10 per A4 page."
  def show(conn, %{"id" => id} = params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Enrollment.can_manage_register?(scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         {:ok, rows} <- pick(Enrollment.list_roster(scope, cg), params["student"]) do
      {:ok, profile} = Accounts.fetch_school_profile(scope)
      year = Organization.class_year(scope, cg)
      students = rows |> Enum.map(& &1.student) |> Enum.sort_by(&String.downcase(&1.full_name))

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        school: scope.current_workspace.name,
        year: year && year.name,
        cg: cg,
        cards: Enum.map(students, &%{student: &1, contact: contact(scope, &1)}),
        missing: Enum.count(students, &is_nil(&1.photo_path)),
        lang: profile.bulletin_language,
        logo?: is_binary(profile.logo_path),
        signature?: is_binary(profile.signature_path),
        stamp?: is_binary(profile.stamp_path)
      )
    else
      {:error, :not_in_class} -> redirect(conn, to: ~p"/school/classes/#{id}/photos")
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp pick(rows, nil), do: {:ok, rows}

  defp pick(rows, student_id) do
    case Enum.filter(rows, &(&1.student.id == student_id)) do
      [] -> {:error, :not_in_class}
      one -> {:ok, one}
    end
  end

  # Main contact first (list_guardian_links orders it so), else the first linked guardian.
  defp contact(scope, student) do
    case Enrollment.list_guardian_links(scope, student) do
      [%{guardian: g} | _] -> g
      _ -> nil
    end
  end
end
```

(`list_guardian_links/2` is called once per student — acceptable for ≤ 80 cards; if a batch helper is wanted, `Enrollment.primary_guardians/2` returns only main contacts: use it first and fall back per student only when absent.)

`card_print_html.ex`:

```elixir
defmodule TeacherAssistantWeb.CardPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_photo_url: 1]
  import TeacherAssistantWeb.BulletinPrintHTML, only: [tr: 2]

  embed_templates "card_print_html/*"

  def sex_label(:f), do: "F"
  def sex_label(:m), do: "M"
  def sex_label(_), do: "—"

  def date(nil), do: nil
  def date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
end
```

(If `BulletinPrintHTML.tr/2` is not public, it is — the controller calls `BulletinPrintHTML.tr(lang, fn -> ... end)`.)

- [ ] **Step 4: Template** — `card_print_html/show.html.heex`

```heex
<!DOCTYPE html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <title>{gettext("Cartes scolaires")} — {@cg.label}</title>
    <style>
      @page { size: A4 portrait; margin: 10mm 14mm; }
      * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      body { margin: 0; font-family: "IBM Plex Sans", system-ui, sans-serif; color: #111; }
      .toolbar { display: flex; gap: 12px; align-items: center; padding: 12px 16px; background: #f4f1ea; }
      .sheet { display: grid; grid-template-columns: repeat(2, 85.6mm); grid-auto-rows: 54mm; gap: 0; justify-content: center; padding: 6mm 0; }
      .card { position: relative; width: 85.6mm; height: 54mm; padding: 2.5mm; outline: 0.2mm dashed #999; overflow: hidden; break-inside: avoid; display: grid; grid-template-rows: 10mm 1fr 6mm; gap: 1mm; }
      .card:nth-child(10n) { break-after: page; }
      .band { display: flex; align-items: center; gap: 2mm; background: #1f3a2e; color: #fff; border-radius: 1.5mm; padding: 1mm 2mm; }
      .band img { height: 7mm; width: 7mm; object-fit: contain; background: #fff; border-radius: 1mm; }
      .band .school { font-weight: 700; font-size: 7.5pt; line-height: 1.1; }
      .band .year { margin-left: auto; font-size: 7pt; }
      .body { display: grid; grid-template-columns: 22mm 1fr; gap: 2.5mm; }
      .photo { width: 22mm; height: 29mm; object-fit: cover; border: 0.3mm solid #333; }
      .photo-empty { width: 22mm; height: 29mm; border: 0.3mm dashed #666; display: grid; place-items: center; font-size: 7pt; color: #666; }
      .name { font-weight: 700; font-size: 9pt; line-height: 1.15; }
      .fields { font-size: 7pt; line-height: 1.35; margin-top: 1mm; }
      .fields b { font-weight: 600; }
      .foot { display: flex; align-items: flex-end; justify-content: space-between; font-size: 6.5pt; }
      .sign { display: flex; gap: 1mm; align-items: flex-end; }
      .sign img { height: 6mm; }
      @media print { .toolbar { display: none; } .sheet { padding: 0; } }
    </style>
  </head>
  <body>
    <div class="toolbar">
      <button type="button" onclick="window.print()">{gettext("Imprimer")}</button>
      <span :if={@missing > 0}>
        {ngettext("1 élève sans photo", "%{count} élèves sans photo", @missing)} —
        <a href={~p"/school/classes/#{@cg.id}/photos"}>{gettext("Compléter les photos")}</a>
      </span>
    </div>

    <main class="sheet">
      <article :for={c <- @cards} class="card">
        <div class="band">
          <img :if={@logo?} src={~p"/school/logo"} alt="" />
          <span class="school">{@school}</span>
          <span class="year">{@year}</span>
        </div>
        <div class="body">
          <img :if={c.student.photo_path} class="photo" src={student_photo_url(c.student)} alt="" />
          <div :if={!c.student.photo_path} class="photo-empty">{tr(@lang, fn -> gettext("Photo") end)}</div>
          <div>
            <div class="name">{c.student.full_name}</div>
            <div class="fields">
              <div><b>{tr(@lang, fn -> gettext("Classe") end)} :</b> {@cg.label}</div>
              <div :if={c.student.matricule}><b>{tr(@lang, fn -> gettext("Matricule") end)} :</b> {c.student.matricule}</div>
              <div><b>{tr(@lang, fn -> gettext("Sexe") end)} :</b> {sex_label(c.student.sex)}</div>
              <div :if={c.student.birth_date || c.student.birth_place}>
                <b>{tr(@lang, fn -> gettext("Né(e) le") end)} :</b>
                {date(c.student.birth_date)} {c.student.birth_place && "— #{c.student.birth_place}"}
              </div>
            </div>
          </div>
        </div>
        <div class="foot">
          <span :if={c.contact}>{tr(@lang, fn -> gettext("Contact") end)} : {c.contact.full_name} – {c.contact.phone}</span>
          <span class="sign">
            <img :if={@stamp?} src={~p"/school/logo?kind=stamp"} alt="" />
            <img :if={@signature?} src={~p"/school/logo?kind=signature"} alt="" />
          </span>
        </div>
      </article>
    </main>
  </body>
</html>
```

`onclick="window.print()"` is an attribute, not an inline `<script>` tag; the bulletin print page uses the same idiom — check `bulletin_print_html/show.html.heex` and copy its print button exactly.

Router: `get "/school/classes/:id/cards/print", CardPrintController, :show` next to the bulletin print routes.

- [ ] **Step 5: Run** — card tests → PASS.

- [ ] **Step 6: Manual print check** — Chrome print preview A4: 10 cards per page, nothing cut at page edges, colours printed, empty photo box visible.

- [ ] **Step 7: Commit** — `feat: printable school ID cards (10 per A4)`.

---

### Task 8: Translations, full suite, visual pass

- [ ] **Step 1:** `mix gettext.extract --merge`; in `priv/gettext/en/LC_MESSAGES/default.po` fill every new msgstr (e.g. « Lancer la séance » → "Start photo session", « Sans photo » → "No photo", « Cartes scolaires » → "School ID cards", « Photo de l'élève » → "Student photo", plural « élèves sans photo » → "student without photo"/"students without photo"), set FR msgstr where the FR file needs it, and remove every `#, fuzzy` on new entries.
- [ ] **Step 2:** `MIX_TEST_PARTITION=7 mix compile --warnings-as-errors && MIX_TEST_PARTITION=7 mix precommit` → all green; commit any formatter rewrites.
- [ ] **Step 3:** Visual pass in Chrome on the demo school (see memory `reference-demo-school-seed`): as SG at 390px — class register tab → Photos → séance on 5 students, crop from gallery, delete; as head — publish a trimester bulletin with photos, replace one photo, reprint: old photo still on the published one; cards print preview. Fix what you find, re-run the suite.
- [ ] **Step 4:** Commit `chore: student photos translations and visual fixes`; then use superpowers:finishing-a-development-branch.
