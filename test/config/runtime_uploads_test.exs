defmodule TeacherAssistant.RuntimeUploadsConfigTest do
  @moduledoc "Production uploads live on a mounted volume, or the server doesn't start."
  # Changes process-wide environment variables.
  use ExUnit.Case, async: false

  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @env %{
    "DATABASE_URL" => "ecto://u:p@localhost/db",
    "SECRET_KEY_BASE" => String.duplicate("s", 64),
    "TOKEN_SIGNING_SECRET" => "t",
    "BREVO_API_KEY" => "k",
    "PHX_SERVER" => "true",
    "UPLOADS_DIR" => nil
  }

  setup do
    saved = Map.new(@env, fn {k, _} -> {k, System.get_env(k)} end)
    on_exit(fn -> Enum.each(saved, fn {k, v} -> put_env(k, v) end) end)
    Enum.each(@env, fn {k, v} -> put_env(k, v) end)

    dir = Path.join(System.tmp_dir!(), "ta_runtime_uploads_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  defp prod_config, do: Config.Reader.read!(@runtime, env: :prod, target: :host)

  defp put_env(k, nil), do: System.delete_env(k)
  defp put_env(k, v), do: System.put_env(k, v)

  test "refuses to start without UPLOADS_DIR" do
    assert_raise RuntimeError, ~r/UPLOADS_DIR is missing/, fn -> prod_config() end
  end

  test "refuses to start when the directory doesn't exist (volume not mounted), and doesn't create it",
       %{dir: dir} do
    put_env("UPLOADS_DIR", dir)
    assert_raise RuntimeError, ~r/not mounted/, fn -> prod_config() end
    refute File.exists?(dir)
  end

  test "refuses to start when the directory isn't writable", %{dir: dir} do
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o500)
    on_exit(fn -> File.chmod(dir, 0o700) end)
    put_env("UPLOADS_DIR", dir)

    assert_raise RuntimeError, ~r/not writable/, fn -> prod_config() end
  end

  test "uses a mounted, writable directory and leaves nothing in it", %{dir: dir} do
    File.mkdir_p!(dir)
    put_env("UPLOADS_DIR", dir)

    assert prod_config()[:teacher_assistant][:uploads_dir] == dir
    assert File.ls!(dir) == []
  end

  test "migrations (no PHX_SERVER) need the variable, not the volume", %{dir: dir} do
    put_env("PHX_SERVER", nil)
    put_env("UPLOADS_DIR", dir)

    assert prod_config()[:teacher_assistant][:uploads_dir] == dir
  end
end
