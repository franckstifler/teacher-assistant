defmodule TeacherAssistantWeb.School.SettingsLogoTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "École du Logo"
      })

    TeacherAssistant.TeacherFixtures.complete_school_setup!(school_scope(user, school))
    conn = post(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, school: school, scope: school_scope(user, school)}
  end

  test "uploading a logo stores a file and sets logo_path", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/profile")

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

    {:ok, p} = Accounts.fetch_school_profile(scope)
    assert p.logo_path

    assert File.exists?(
             Path.join(Application.fetch_env!(:teacher_assistant, :uploads_dir), p.logo_path)
           )
  end

  test "the served logo route returns the stored file", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/profile")

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

    {:ok, _p} = Accounts.fetch_school_profile(scope)

    conn = get(conn, ~p"/school/logo")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() |> String.starts_with?("image/png")
  end

  test "a page sent as a PNG is refused and nothing is stored", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/profile")

    logo =
      file_input(view, "#school-logo-form", :logo, [
        %{name: "x.html", content: "<script>alert(1)</script>", type: "image/png"}
      ])

    render_upload(logo, "x.html")
    view |> element("#school-logo-form") |> render_submit()

    {:ok, p} = Accounts.fetch_school_profile(scope)
    assert p.logo_path == nil
    assert render(view) =~ "pas une image PNG ou JPEG"
  end

  test "the stored extension comes from the file's bytes, not its name", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/school/settings/profile")

    logo =
      file_input(view, "#school-logo-form", :logo, [
        %{
          name: "logo.html",
          content: File.read!("test/support/fixtures/files/1x1.png"),
          type: "image/png"
        }
      ])

    render_upload(logo, "logo.html")
    view |> element("#school-logo-form") |> render_submit()

    {:ok, p} = Accounts.fetch_school_profile(scope)
    assert Path.extname(p.logo_path) == ".png"
  end

  test "a stored file that isn't PNG or JPEG is never served", %{conn: conn, scope: scope} do
    relative = Path.join(["school_logos", scope.current_workspace.id, "old.html"])
    dest = Path.join(TeacherAssistant.Uploads.dir(), relative)
    dest |> Path.dirname() |> File.mkdir_p!()
    File.write!(dest, "<script>alert(1)</script>")

    {:ok, p} = Accounts.fetch_school_profile(scope)
    {:ok, _} = Accounts.set_school_logo(p, relative, scope: scope)

    assert conn |> get(~p"/school/logo") |> response(404)
  end

  test "the profile form can't set the logo path", %{scope: scope} do
    {:ok, p} = Accounts.fetch_school_profile(scope)

    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.update_school_profile(p, %{logo_path: "school_logos/other/x.png"},
               scope: scope
             )
  end
end
