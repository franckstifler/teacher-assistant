defmodule TeacherAssistant.CouncilsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Councils, Curriculum, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    [term | _] = Organization.list_terms(scope, year)
    [seq | _] = term.sequences
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e C", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(1)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [awa, bob] = Enrollment.list_roster(scope, cg)

    :ok =
      Assessment.upsert_marks(scope, a, [
        %{student_id: awa.student.id, score: Decimal.new(17)},
        %{student_id: bob.student.id, score: Decimal.new(7)}
      ])

    %{
      scope: scope,
      year: year,
      term: term,
      cg: cg,
      a: a,
      awa: awa.student,
      bob: bob.student
    }
  end

  defp results(ctx),
    do: Assessment.class_results_for_period(ctx.scope, ctx.cg, {:trimester, ctx.term})

  test "an unsaved council has the term's defaults", ctx do
    council = Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert council.id == nil
    assert council.status == :open
    assert council.held_on == ctx.term.class_council_date
    assert council.decisions == []
  end

  test "the header is created by the first save, then updated", ctx do
    assert {:ok, _} =
             Councils.save_header(ctx.scope, ctx.cg, {:trimester, ctx.term}, %{
               "chair" => "M. Fotso",
               "attendees" => "Censeur, PP, délégués",
               "observations" => "Classe sérieuse",
               "held_on" => "2026-01-15"
             })

    assert {:ok, _} =
             Councils.save_header(ctx.scope, ctx.cg, {:trimester, ctx.term}, %{
               "chair" => "Mme Ngo"
             })

    council = Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert council.chair == "Mme Ngo"
    assert council.observations == "Classe sérieuse"
    assert council.held_on == ~D[2026-01-15]
    assert map_size(Councils.for_period(ctx.scope, {:trimester, ctx.term})) == 1
  end

  test "a decision is one row per student, last write wins", ctx do
    set = &Councils.set_decision(ctx.scope, ctx.cg, {:trimester, ctx.term}, ctx.awa.id, &1)
    assert {:ok, _} = set.(%{"distinction_choice" => "encouragements"})
    assert {:ok, _} = set.(%{"distinction_choice" => "none"})

    assert {:ok, _} =
             set.(%{
               "distinction_choice" => "",
               "conduct_warning" => "blame_conduite",
               "appreciation" => " Bon trimestre "
             })

    assert [decision] = Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).decisions
    assert decision.distinction_choice == nil
    assert decision.conduct_warning == :blame_conduite
    assert decision.appreciation == "Bon trimestre"

    assert {:error, :invalid_choice} = set.(%{"distinction_choice" => "bogus"})
    assert {:error, %Ash.Error.Invalid{}} = set.(%{"appreciation" => String.duplicate("a", 301)})
  end

  test "outcomes: the council's choice, else the I1 proposal", ctx do
    council = Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term})
    outcomes = Councils.outcomes(council, results(ctx))
    assert outcomes[ctx.awa.id].distinction == :felicitations
    assert outcomes[ctx.bob.id].distinction == :avertissement_travail
    assert outcomes[ctx.bob.id].appreciation == nil

    {:ok, _} =
      Councils.set_decision(ctx.scope, ctx.cg, {:trimester, ctx.term}, ctx.awa.id, %{
        "distinction_choice" => "encouragements"
      })

    {:ok, _} =
      Councils.set_decision(ctx.scope, ctx.cg, {:trimester, ctx.term}, ctx.bob.id, %{
        "distinction_choice" => "none",
        "appreciation" => "Doit travailler"
      })

    outcomes =
      Councils.outcomes(Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}), results(ctx))

    assert outcomes[ctx.awa.id].distinction == :encouragements
    assert outcomes[ctx.bob.id].distinction == nil
    assert outcomes[ctx.bob.id].appreciation == "Doit travailler"
    assert map_size(outcomes) == 2
    assert Councils.outcomes(council, nil) == %{}
  end

  test "hold and reopen", ctx do
    refute Councils.held?(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert {:ok, held} = Councils.hold(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert held.status == :held
    assert held.held_by_user_id == ctx.scope.current_user.id
    assert Councils.held?(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert {:ok, %{status: :held}} = Councils.hold(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert {:ok, %{status: :open}} = Councils.reopen(ctx.scope, ctx.cg, {:trimester, ctx.term})
    refute Councils.held?(ctx.scope, ctx.cg, {:trimester, ctx.term})
  end

  test "a published trimester locks its council until withdrawn", ctx do
    {:ok, _} = Councils.hold(ctx.scope, ctx.cg, {:trimester, ctx.term})
    {:ok, pub} = ReportCards.publish(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert Councils.locked?(ctx.scope, ctx.cg, {:trimester, ctx.term})

    assert {:error, :locked} =
             Councils.save_header(ctx.scope, ctx.cg, {:trimester, ctx.term}, %{"chair" => "X"})

    assert {:error, :locked} =
             Councils.set_decision(ctx.scope, ctx.cg, {:trimester, ctx.term}, ctx.awa.id, %{
               "appreciation" => "X"
             })

    assert {:error, :locked} = Councils.reopen(ctx.scope, ctx.cg, {:trimester, ctx.term})

    {:ok, _} = ReportCards.withdraw(ctx.scope, pub, "Correction")
    assert {:ok, %{status: :open}} = Councils.reopen(ctx.scope, ctx.cg, {:trimester, ctx.term})
  end

  test "only the admin axis writes", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope)

    assert {:error, %Ash.Error.Forbidden{}} =
             Councils.save_header(teacher, ctx.cg, {:trimester, ctx.term}, %{"chair" => "X"})

    assert {:error, %Ash.Error.Forbidden{}} =
             Councils.hold(teacher, ctx.cg, {:trimester, ctx.term})

    {:ok, _} = Councils.save_header(ctx.scope, ctx.cg, {:trimester, ctx.term}, %{"chair" => "Y"})

    assert {:error, %Ash.Error.Forbidden{}} =
             Councils.set_decision(teacher, ctx.cg, {:trimester, ctx.term}, ctx.awa.id, %{
               "appreciation" => "X"
             })
  end

  test "default_term picks the trimester covering the date", ctx do
    terms = Organization.list_terms(ctx.scope, ctx.scope.current_academic_year)
    [first, second | _] = terms
    inside = hd(second.sequences).start_date
    assert Councils.default_term(terms, inside).id == second.id
    assert Councils.default_term(terms, ~D[1999-01-01]).id == first.id
    assert Councils.default_term([], inside) == nil
  end

  describe "annual council (I4)" do
    defp annual_outcomes(ctx) do
      {:draft, view} = ReportCards.class_view(ctx.scope, ctx.cg, {:annual, ctx.year})
      view.council.outcomes
    end

    test "is separate from the trimester councils", ctx do
      {:ok, _} = Councils.hold(ctx.scope, ctx.cg, {:annual, ctx.year})
      assert Councils.held?(ctx.scope, ctx.cg, {:annual, ctx.year})
      refute Councils.held?(ctx.scope, ctx.cg, {:trimester, ctx.term})
      assert map_size(Councils.for_period(ctx.scope, {:annual, ctx.year})) == 1
      assert Councils.for_period(ctx.scope, {:trimester, ctx.term}) == %{}
    end

    test "proposes a passage decision the council can override", ctx do
      outcomes = annual_outcomes(ctx)
      assert outcomes[ctx.awa.id].passage == :admis
      assert outcomes[ctx.bob.id].passage == :redouble
      assert outcomes[ctx.bob.id].passage_reason == nil

      {:ok, _} =
        Councils.set_decision(ctx.scope, ctx.cg, {:annual, ctx.year}, ctx.bob.id, %{
          "passage_decision" => "admis_rachat"
        })

      assert annual_outcomes(ctx)[ctx.bob.id].passage == :admis_rachat
      assert annual_outcomes(ctx)[ctx.bob.id].proposal == :redouble

      assert {:error, :invalid_choice} =
               Councils.set_decision(ctx.scope, ctx.cg, {:annual, ctx.year}, ctx.bob.id, %{
                 "passage_decision" => "promu"
               })
    end

    test "exclusion and repeat reasons", ctx do
      {:ok, _} =
        Enrollment.add_student(ctx.scope, ctx.cg, %{full_name: "Zoé", sex: :f, repeater: true})

      zoe =
        Enum.find(Enrollment.list_roster(ctx.scope, ctx.cg), &(&1.student.full_name == "Zoé")).student

      :ok =
        Assessment.upsert_marks(ctx.scope, ctx.a, [
          %{student_id: zoe.id, score: Decimal.new(8)},
          %{student_id: ctx.bob.id, score: Decimal.new(6)}
        ])

      outcomes = annual_outcomes(ctx)

      assert {outcomes[zoe.id].passage, outcomes[zoe.id].passage_reason} ==
               {:exclu, "Déjà redoublant"}

      assert {outcomes[ctx.bob.id].passage, outcomes[ctx.bob.id].passage_reason} ==
               {:exclu, "Moyenne < 7"}
    end

    test "trimester outcomes carry no passage", ctx do
      {:draft, view} = ReportCards.class_view(ctx.scope, ctx.cg, {:trimester, ctx.term})
      refute Map.has_key?(view.council.outcomes[ctx.awa.id], :passage)
    end
  end
end
