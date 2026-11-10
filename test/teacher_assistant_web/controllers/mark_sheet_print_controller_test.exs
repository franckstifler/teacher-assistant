defmodule TeacherAssistantWeb.MarkSheetPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Modules, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Relevé"
      })

    scope = school_scope(head, school)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [seq1, seq2 | _] = Organization.list_sequences(scope, year)
    [term1 | _] = Organization.list_terms(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob Eyong", sex: :m})

    {:ok, maths} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _svt} = Curriculum.assign_teacher(scope, cg, head, %{subject: "SVT"})

    # Two evaluations in Maths: the sheet prints the séquence mark, (12 + 2 × 15) / 3 = 14
    {:ok, d1} = Assessment.create_assessment(scope, maths, seq1, %{label: "Interro"})

    {:ok, d2} =
      Assessment.create_assessment(scope, maths, seq1, %{label: "Devoir", weight: Decimal.new(2)})

    :ok =
      Assessment.upsert_marks(scope, d1, [
        %{student_id: awa.id, score: Decimal.new(12)},
        %{student_id: bob.id, status: :absent}
      ])

    :ok =
      Assessment.upsert_marks(scope, d2, [
        %{student_id: awa.id, score: Decimal.new(15)},
        %{student_id: bob.id, status: :absent}
      ])

    {:ok, cg5} = Enrollment.create_class_group(scope, year, %{label: "5e B", level: "5ème"})
    {:ok, _} = Enrollment.add_student(scope, cg5, %{full_name: "Chantal Mbia", sex: :f})
    {:ok, _} = Enrollment.create_class_group(scope, year, %{label: "4e Vide", level: "4ème"})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      scope: scope,
      school: school,
      cg: cg,
      seq1: seq1,
      seq2: seq2,
      term1: term1
    }
  end

  defp cells(body, name) do
    [row] =
      Regex.run(~r/<tr[^>]*>\s*<td[^>]*>\d+<\/td>\s*<td[^>]*>#{name}<\/td>(.*?)<\/tr>/s, body,
        capture: :all_but_first
      )

    ~r/<td[^>]*>(.*?)<\/td>/s
    |> Regex.scan(row, capture: :all_but_first)
    |> Enum.map(fn [cell] -> String.trim(cell) end)
  end

  # The column headers in print order (the bulletin's subject order).
  defp subjects(body),
    do: ~r/<th[^>]*title="([^"]+)"/ |> Regex.scan(body, capture: :all_but_first) |> List.flatten()

  # A student's cells keyed by subject: one cell per subject and séquence.
  defp cells_by_subject(body, name) do
    subjects = subjects(body)
    per = div(length(cells(body, name)), length(subjects))
    subjects |> Enum.zip(Enum.chunk_every(cells(body, name), per)) |> Map.new()
  end

  describe "one class, one séquence" do
    test "a row per student with the séquence mark of each subject", %{
      conn: conn,
      cg: cg,
      seq1: seq1
    } do
      body =
        conn
        |> get(~p"/school/classes/#{cg.id}/mark-sheet/print?period=seq:#{seq1.id}")
        |> html_response(200)

      assert body =~ "Lycée Relevé"
      assert body =~ "Relevé des notes"
      assert body =~ "Séquence 1"
      assert body =~ "6e A"
      # one séquence mark per subject, not one per evaluation
      assert Enum.sort(subjects(body)) == ["Maths", "SVT"]
      assert cells_by_subject(body, "Awa Ngo") == %{"Maths" => ["14"], "SVT" => ["—"]}
      assert cells_by_subject(body, "Bob Eyong") == %{"Maths" => ["Abs"], "SVT" => ["—"]}
      refute body =~ "Interro"
      # marks only: no average, no rank
      refute body =~ "Moyenne"
      refute body =~ "Rang"
      assert body =~ "size: A4 landscape"
    end

    test "without a period, the current séquence is printed", %{conn: conn, cg: cg} do
      body = conn |> get(~p"/school/classes/#{cg.id}/mark-sheet/print") |> html_response(200)
      assert body =~ "Relevé des notes"
      assert body =~ "Awa Ngo"
    end

    test "the screen offers every séquence and trimester; paper does not show the choice", %{
      conn: conn,
      cg: cg,
      seq1: seq1,
      term1: term1
    } do
      body =
        conn
        |> get(~p"/school/classes/#{cg.id}/mark-sheet/print?period=seq:#{seq1.id}")
        |> html_response(200)

      assert body =~ ~s(value="seq:#{seq1.id}" selected)
      assert body =~ ~s(value="trim:#{term1.id}")
      assert body =~ ~s(class="print-actions")
    end
  end

  describe "a trimester" do
    test "each subject has its two séquences side by side", %{
      conn: conn,
      cg: cg,
      term1: term1
    } do
      body =
        conn
        |> get(~p"/school/classes/#{cg.id}/mark-sheet/print?period=trim:#{term1.id}")
        |> html_response(200)

      assert body =~ "Trimestre 1"
      assert body =~ "S1"
      assert body =~ "S2"
      # S1 then S2 under each subject
      assert cells_by_subject(body, "Awa Ngo") == %{"Maths" => ["14", "—"], "SVT" => ["—", "—"]}

      assert cells_by_subject(body, "Bob Eyong") == %{
               "Maths" => ["Abs", "—"],
               "SVT" => ["—", "—"]
             }
    end
  end

  describe "the whole school" do
    test "every class with students, one after the other, in class order", %{
      conn: conn,
      seq1: seq1
    } do
      body =
        conn
        |> get(~p"/school/mark-sheets/print?period=seq:#{seq1.id}")
        |> html_response(200)

      assert length(Regex.scan(~r/<section class="sheet/, body)) == 2
      {sixth, _} = :binary.match(body, "Awa Ngo")
      {fifth, _} = :binary.match(body, "Chantal Mbia")
      assert sixth < fifth
      refute body =~ "4e Vide"
      assert body =~ "break-before: page"
    end
  end

  describe "who may print it" do
    test "a teacher is sent away", %{scope: scope, school: school, cg: cg} do
      teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]}).current_user

      for path <- [~p"/school/mark-sheets/print", ~p"/school/classes/#{cg.id}/mark-sheet/print"] do
        conn =
          build_conn()
          |> log_in_user(teacher)
          |> Plug.Conn.put_session(:workspace_id, school.id)
          |> get(path)

        assert redirected_to(conn) == ~p"/school"
      end
    end

    test "the censeur may print it", %{scope: scope, school: school, seq1: seq1} do
      censeur =
        TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal]}).current_user

      body =
        build_conn()
        |> log_in_user(censeur)
        |> Plug.Conn.put_session(:workspace_id, school.id)
        |> get(~p"/school/mark-sheets/print?period=seq:#{seq1.id}")
        |> html_response(200)

      assert body =~ "Awa Ngo"
    end

    test "the sheets belong to the marks module" do
      for action <- [:class, :all] do
        assert Modules.module_for_controller(TeacherAssistantWeb.MarkSheetPrintController, action) ==
                 :notes
      end
    end
  end
end
