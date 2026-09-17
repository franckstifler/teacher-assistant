defmodule TeacherAssistantWeb.School.SettingsLogoTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "École du Logo"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, school: school}
  end

  test "uploading a logo stores a file and sets logo_path", %{conn: conn, school: school} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    logo =
      file_input(view, "#school-logo-form", :logo, [
        %{
          name: "logo.png",
          content: File.read!("test/support/fixtures/files/1x1.png"),
          type: "image/png"
        }
      ])

    render_upload(logo, "logo.png")
    view |> element("#school-logo-form") |> render_submit()

    {:ok, p} = Schools.fetch_school_profile(school)
    assert p.logo_path

    assert File.exists?(
             Path.join(Application.fetch_env!(:teacher_assistant, :uploads_dir), p.logo_path)
           )
  end

  test "the served logo route returns the stored file", %{conn: conn, school: school} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    logo =
      file_input(view, "#school-logo-form", :logo, [
        %{
          name: "logo.png",
          content: File.read!("test/support/fixtures/files/1x1.png"),
          type: "image/png"
        }
      ])

    render_upload(logo, "logo.png")
    view |> element("#school-logo-form") |> render_submit()

    {:ok, _p} = Schools.fetch_school_profile(school)

    conn = get(conn, ~p"/school/logo")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() |> String.starts_with?("image/png")
  end
end
