defmodule TeacherAssistantWeb.CardPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})

    {:ok, awa} =
      Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f, matricule: "M1"})

    {:ok, ben} = Enrollment.add_student(scope, cg, %{full_name: "Ben Ateba", sex: :m})
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
    {:ok, awa} = StudentPhotos.store(scope, awa, tmp)

    {:ok, _g} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Marie Ngono",
        phone: "677001122",
        relationship: :mere
      })

    %{scope: scope, cg: cg, awa: awa, ben: ben}
  end

  test "prints one card per student with photo, identity and contact", %{
    conn: conn,
    cg: cg,
    awa: awa
  } do
    html = conn |> get(~p"/school/classes/#{cg.id}/cards/print") |> html_response(200)
    assert html =~ "Awa Ngono" and html =~ "Ben Ateba" and html =~ "M1"
    assert html =~ ~s(src="/school/students/#{awa.id}/photo)
    assert html =~ "Urgence" and html =~ "677001122"
    assert html =~ "1 élève sans photo"
    assert length(Regex.scan(~r/class="card"/, html)) == 2
  end

  test "each sheet has its caption, hairline grid and crop marks", %{conn: conn, cg: cg} do
    html = conn |> get(~p"/school/classes/#{cg.id}/cards/print") |> html_response(200)
    assert html =~ "6e P · planche 1 / 1 · 2 cartes · A4, échelle 100 %"
    assert html =~ "@page { size: A4 portrait; margin: 0; }"
    assert length(Regex.scan(~r/class="mark mark-v"/, html)) == 6
    assert length(Regex.scan(~r/class="mark mark-h"/, html)) == 12
    refute html =~ "dashed"
  end

  test "the main contact is the one printed", %{conn: conn, scope: scope, cg: cg, awa: awa} do
    {:ok, _} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Paul Ngono",
        phone: "699887766",
        relationship: :pere
      })

    paul =
      Enum.find(
        Enrollment.list_guardian_links(scope, awa),
        &(&1.guardian.full_name == "Paul Ngono")
      )

    {:ok, _} = Enrollment.make_primary_guardian(scope, paul)

    html =
      conn
      |> get(~p"/school/classes/#{cg.id}/cards/print?student=#{awa.id}")
      |> html_response(200)

    assert html =~ "699887766"
    refute html =~ "677001122"
  end

  test "a student without photo gets the empty Photo box", %{conn: conn, cg: cg, ben: ben} do
    html =
      conn
      |> get(~p"/school/classes/#{cg.id}/cards/print?student=#{ben.id}")
      |> html_response(200)

    assert html =~ ~s(class="photo-empty")
    refute html =~ ~s(class="photo")
  end

  test "?student= prints that student only", %{conn: conn, cg: cg, awa: awa} do
    html =
      conn
      |> get(~p"/school/classes/#{cg.id}/cards/print?student=#{awa.id}")
      |> html_response(200)

    assert html =~ "Awa Ngono"
    refute html =~ "Ben Ateba"
  end

  test "a student of another class is refused", %{conn: conn, scope: scope, cg: cg, year: year} do
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})
    {:ok, zoe} = Enrollment.add_student(scope, other, %{full_name: "Zoe", sex: :f})

    assert redirected_to(get(conn, ~p"/school/classes/#{cg.id}/cards/print?student=#{zoe.id}")) ==
             ~p"/school/classes/#{cg.id}/photos"
  end

  test "a teacher is sent to /school", %{scope: scope, workspace: ws, cg: cg} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      build_conn()
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert redirected_to(get(conn, ~p"/school/classes/#{cg.id}/cards/print")) == ~p"/school"
  end

  describe "v2 card (option A)" do
    defp set_profile(scope, attrs) do
      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
      {:ok, _} = profile |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
    end

    defp cards(conn, cg),
      do: conn |> get(~p"/school/classes/#{cg.id}/cards/print") |> html_response(200)

    test "card has the split title, the one-line Republic and the school code", %{
      conn: conn,
      scope: scope,
      cg: cg
    } do
      set_profile(scope, %{school_code: "5MN1TEF110431106"})
      html = cards(conn, cg)
      assert html =~ "<span>CARTE SCOLAIRE</span><span>STUDENT ID CARD</span>"
      assert html =~ "République du Cameroun · Republic of Cameroon"
      assert html =~ "Code 5MN1TEF110431106"
      assert html =~ ~s(class="flag")
      assert html =~ "Scanner pour vérifier"
      refute html =~ "Paix – Travail – Patrie"
    end

    test "a bilingual school's card gives both labels", %{conn: conn, scope: scope, cg: cg} do
      set_profile(scope, %{bulletin_language: :bilingual})
      html = cards(conn, cg)
      assert html =~ "Classe · Class"
      assert html =~ "Urgence · Emergency"
      assert html =~ "Scan to verify"
      assert html =~ ~s(class="lang-bilingual")
    end

    test "card shows the national ID when set", %{conn: conn, scope: scope, cg: cg, awa: awa} do
      {:ok, _} = Enrollment.update_student(awa, %{national_id: "241592812"}, scope: scope)
      html = cards(conn, cg)
      assert html =~ "Identifiant unique"
      assert html =~ "241592812"
    end

    test "card shows head title and name", %{conn: conn, scope: scope, cg: cg} do
      set_profile(scope, %{school_type: :lycee, head_name: "Mme Ngo Tonye"})
      html = cards(conn, cg)
      assert html =~ "Le Proviseur · The Principal"
      assert html =~ "Mme Ngo Tonye"

      set_profile(scope, %{school_type: :ghs})
      html = cards(conn, cg)
      assert html =~ "The Principal"
      refute html =~ "Le Proviseur"
    end
  end
end
