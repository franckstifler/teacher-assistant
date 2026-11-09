defmodule TeacherAssistantWeb.ClassListPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Enrollment, Modules, ReportCards}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})

    {:ok, awa} =
      Enrollment.add_student(scope, cg, %{
        full_name: "Awa Ngono",
        sex: :f,
        matricule: "M1",
        birth_date: ~D[2010-03-12],
        birth_place: "Yaoundé",
        repeater: true
      })

    {:ok, ben} = Enrollment.add_student(scope, cg, %{full_name: "Ben Ateba", sex: :m})
    %{scope: scope, cg: cg, awa: awa, ben: ben}
  end

  defp as_member(conn, scope, workspace, roles) do
    member = TeacherFixtures.member_scope_fixture(scope, %{roles: roles})

    conn
    |> log_in_user(member.current_user)
    |> Plug.Conn.put_session(:workspace_id, workspace.id)
  end

  describe "official roster" do
    test "lists the class in roster order with identity columns and totals", %{
      conn: conn,
      cg: cg
    } do
      body = conn |> get(~p"/school/classes/#{cg.id}/class-list/print") |> html_response(200)

      assert body =~ "LISTE DE CLASSE"
      assert body =~ "6e P"
      assert body =~ "M1"
      assert body =~ "12/03/2010 à Yaoundé"
      {awa_at, _} = :binary.match(body, "Awa Ngono")
      {ben_at, _} = :binary.match(body, "Ben Ateba")
      assert awa_at < ben_at
      assert body =~ "Effectif : 2"
      assert body =~ "Garçons : 1"
      assert body =~ "Filles : 1"
      assert body =~ "Redoublants : 1"
      refute body =~ "nil"
    end

    test "an empty class prints its header and zero totals", %{
      conn: conn,
      scope: scope,
      year: year
    } do
      {:ok, empty} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
      body = conn |> get(~p"/school/classes/#{empty.id}/class-list/print") |> html_response(200)

      assert body =~ "6e Z"
      assert body =~ "Effectif : 0"
    end

    test "the form master is named when set", %{conn: conn, scope: scope, cg: cg} do
      master = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]}).current_user
      {:ok, _} = Enrollment.set_form_master(scope, cg, master.id)

      body = conn |> get(~p"/school/classes/#{cg.id}/class-list/print") |> html_response(200)

      assert body =~ "Professeur principal"
      assert body =~ TeacherAssistant.Accounts.User.display_name(master)
    end

    test "an anglophone class prints in English", %{conn: conn, scope: scope, year: year} do
      {:ok, cg} =
        Enrollment.create_class_group(scope, year, %{
          label: "Form 1",
          level: "6ème",
          subsystem: :anglophone
        })

      assert ReportCards.template(scope, cg).language == :en
      body = conn |> get(~p"/school/classes/#{cg.id}/class-list/print") |> html_response(200)

      assert body =~ "CLASS ROSTER"
      assert body =~ "Class size : 0"
    end

    test "a bilingual school prints the birth details once", %{conn: conn, scope: scope, cg: cg} do
      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

      {:ok, _} =
        TeacherAssistant.Accounts.update_school_profile(profile, %{bulletin_language: :bilingual},
          scope: scope
        )

      body = conn |> get(~p"/school/classes/#{cg.id}/class-list/print") |> html_response(200)

      assert body =~ "12/03/2010 à / in Yaoundé"
      assert length(String.split(body, "12/03/2010")) == 2
    end

    test "a discipline master may print it", %{
      conn: conn,
      scope: scope,
      workspace: workspace,
      cg: cg
    } do
      conn =
        conn
        |> as_member(scope, workspace, [:discipline_master])
        |> get(~p"/school/classes/#{cg.id}/class-list/print")

      assert html_response(conn, 200) =~ "Awa Ngono"
    end

    test "a teacher is sent away", %{conn: conn, scope: scope, workspace: workspace, cg: cg} do
      conn =
        conn
        |> as_member(scope, workspace, [:teacher])
        |> get(~p"/school/classes/#{cg.id}/class-list/print")

      assert redirected_to(conn) == ~p"/school"
    end

    test "the roster is core" do
      assert Modules.module_for_controller(TeacherAssistantWeb.ClassListPrintController, :roster) ==
               :core
    end
  end

  describe "working list" do
    test "has six empty columns per student and a blank subject line", %{conn: conn, cg: cg} do
      body =
        conn |> get(~p"/school/classes/#{cg.id}/class-list/working/print") |> html_response(200)

      assert length(Regex.scan(~r/<td class="blank">/, body)) == 12
      assert body =~ "Matière"
      assert body =~ "Effectif : 2 (G 1 / F 1)"
      refute body =~ "Date et lieu de naissance"
    end

    test "a teacher prints it for their own course, pre-filled", %{
      scope: scope,
      workspace: workspace,
      cg: cg
    } do
      %{teacher: teacher, teaching_context: tc} =
        TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "Maths"})

      body =
        build_conn()
        |> log_in_user(teacher)
        |> Plug.Conn.put_session(:workspace_id, workspace.id)
        |> get(~p"/teacher/contexts/#{tc.id}/class-list/print")
        |> html_response(200)

      assert body =~ "Maths"
      assert body =~ TeacherAssistant.Accounts.User.display_name(teacher)
      assert body =~ "Awa Ngono"
    end

    test "a teacher can't print another teacher's course", %{
      scope: scope,
      workspace: workspace,
      cg: cg
    } do
      %{teaching_context: tc} =
        TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "Maths"})

      %{teacher: other} =
        TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "SVT"})

      conn =
        build_conn()
        |> log_in_user(other)
        |> Plug.Conn.put_session(:workspace_id, workspace.id)
        |> get(~p"/teacher/contexts/#{tc.id}/class-list/print")

      assert redirected_to(conn) == ~p"/school"
    end

    test "a teacher can't open the school-side working list", %{
      conn: conn,
      scope: scope,
      workspace: workspace,
      cg: cg
    } do
      conn =
        conn
        |> as_member(scope, workspace, [:teacher])
        |> get(~p"/school/classes/#{cg.id}/class-list/working/print")

      assert redirected_to(conn) == ~p"/school"
    end

    test "seventy students get the dense layout", %{conn: conn, scope: scope, year: year} do
      {:ok, big} = Enrollment.create_class_group(scope, year, %{label: "6e G", level: "6ème"})

      for i <- 1..70 do
        {:ok, _} = Enrollment.add_student(scope, big, %{full_name: "Élève #{i}", sex: :m})
      end

      body =
        conn |> get(~p"/school/classes/#{big.id}/class-list/working/print") |> html_response(200)

      assert body =~ ~s(<section class="sheet dense">)
    end

    test "the working lists belong to core and notes" do
      assert Modules.module_for_controller(TeacherAssistantWeb.ClassListPrintController, :working) ==
               :core

      assert Modules.module_for_controller(TeacherAssistantWeb.ClassListPrintController, :teacher) ==
               :notes
    end
  end

  describe "all of a teacher's working lists" do
    setup %{scope: scope, year: year, cg: cg, workspace: workspace} do
      {:ok, other_cg} =
        Enrollment.create_class_group(scope, year, %{label: "5e Q", level: "5ème"})

      {:ok, _} = Enrollment.add_student(scope, other_cg, %{full_name: "Chantal Mbia", sex: :f})

      %{teacher: teacher} =
        TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "Maths"})

      TeacherFixtures.school_teacher_fixture(scope, %{
        teacher: teacher,
        class_group: other_cg,
        subject: "SVT"
      })

      # a colleague's course stays out
      TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "Anglais"})

      conn =
        build_conn()
        |> log_in_user(teacher)
        |> Plug.Conn.put_session(:workspace_id, workspace.id)

      %{teacher_conn: conn, teacher: teacher}
    end

    test "one pre-filled page per course, each class's students on its own page", %{
      teacher_conn: conn,
      teacher: teacher
    } do
      body = conn |> get(~p"/teacher/class-lists/print") |> html_response(200)

      assert length(Regex.scan(~r/<section class="sheet/, body)) == 2

      for text <- ["6e P", "5e Q", "Maths", "SVT", "Awa Ngono", "Chantal Mbia"],
          do: assert(body =~ text)

      assert body =~ TeacherAssistant.Accounts.User.display_name(teacher)
      refute body =~ "Anglais"
      # each sheet starts a new A4 page
      assert body =~ "break-before: page"
    end

    test "a member with no course goes back to « Mes cours »", %{
      scope: scope,
      workspace: workspace
    } do
      conn =
        build_conn()
        |> log_in_user(
          TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]}).current_user
        )
        |> Plug.Conn.put_session(:workspace_id, workspace.id)
        |> get(~p"/teacher/class-lists/print")

      assert redirected_to(conn) == ~p"/school/courses"
    end
  end
end
