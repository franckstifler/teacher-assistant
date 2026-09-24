defmodule TeacherAssistant.TenancyIsolationTest do
  @moduledoc """
  For every multitenant resource: a row created under school A is invisible
  under school B, and a create without a tenant raises. Later tasks add
  `row_for/2` clauses as they flip domains.
  """
  use TeacherAssistant.DataCase, async: true
  require Ash.Query
  alias TeacherAssistant.Academics, as: A
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: a, year: year_a} = TeacherFixtures.setup_complete_school_fixture()
    %{workspace: b} = TeacherFixtures.setup_complete_school_fixture()
    %{a: a, b: b, year_a: year_a}
  end

  # One clause per resource; returns a row created under `school`.
  defp row_for(A.AcademicYear, school, _ctx), do: Organization.current_academic_year(school)

  defp row_for(A.Term, school, _ctx),
    do:
      school |> Organization.current_academic_year() |> Organization.list_terms() |> List.first()

  defp row_for(A.Sequence, school, _ctx),
    do:
      school
      |> Organization.current_academic_year()
      |> Organization.list_sequences()
      |> List.first()

  @flipped [A.AcademicYear, A.Term, A.Sequence]

  test "a row of school A is not readable under school B", ctx do
    for resource <- @flipped do
      row = row_for(resource, ctx.a, ctx)
      assert row, "#{inspect(resource)}: no row created"
      assert {:ok, _} = Ash.get(resource, row.id, tenant: ctx.a.id)
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(resource, row.id, tenant: ctx.b.id)
    end
  end

  test "reading a flipped resource without a tenant raises", ctx do
    for resource <- @flipped do
      assert_raise Ash.Error.Invalid, fn ->
        resource |> Ash.Query.filter(id == ^row_for(resource, ctx.a, ctx).id) |> Ash.read!()
      end
    end
  end

  test "creating a flipped resource without a tenant raises", %{a: a} do
    year = Organization.current_academic_year(a)

    assert_raise Ash.Error.Invalid, ~r/tenant/, fn ->
      A.Term
      |> Ash.Changeset.for_create(:create, %{position: 9, academic_year_id: year.id})
      |> Ash.create!()
    end
  end

  test "the scope exposes the workspace as tenant", %{a: a} do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(a)
    {:ok, head} = TeacherAssistant.Accounts.get_user(profile.owner_user_id)
    {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(head, a.id)
    assert Ash.Scope.ToOpts.get_tenant(scope) == {:ok, a.id}
  end
end
