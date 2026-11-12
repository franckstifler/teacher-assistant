defmodule TeacherAssistantWeb.StaticFilesTest do
  use TeacherAssistantWeb.ConnCase, async: true

  # `phx.digest` renames root files in production and ~p links the digested name
  # (/site-<hash>.webmanifest). Plain copies stand in for the digested files here.
  test "serves the digested copy of every root static file", %{conn: conn} do
    static = Application.app_dir(:teacher_assistant, "priv/static")
    hash = "-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    for file <- TeacherAssistantWeb.static_paths(), Path.extname(file) != "" do
      digested = Path.rootname(file) <> hash <> Path.extname(file)
      copy = Path.join(static, digested)
      File.cp!(Path.join(static, file), copy)
      on_exit(fn -> File.rm(copy) end)

      assert conn |> get("/" <> digested) |> response(200),
             "#{digested} is not served"
    end
  end

  # The home-screen icon opens the member's space, not the public landing; signed
  # out, that page sends to the sign-in.
  test "the installed app starts on the member's space", %{conn: conn} do
    manifest =
      Application.app_dir(:teacher_assistant, "priv/static/site.webmanifest")
      |> File.read!()
      |> Jason.decode!()

    assert manifest["start_url"] == "/school"
    assert conn |> get(manifest["start_url"]) |> redirected_to() == ~p"/sign-in"
  end
end
