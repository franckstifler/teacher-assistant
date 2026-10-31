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
end
