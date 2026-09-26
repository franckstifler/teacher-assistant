defmodule TeacherAssistantWeb.AuthzTest do
  use TeacherAssistant.DataCase, async: true

  # A refused form submit logs AshPhoenix's "unhandled error" warning.
  @moduletag :capture_log

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistantWeb.Authz

  setup do
    %{scope: head} = setup_complete_school_fixture()
    %{head: head, teacher: member_scope_fixture(head, %{roles: [:teacher]})}
  end

  defp submit_year(scope, params) do
    AcademicYear
    |> AshPhoenix.Form.for_create(:create_for_workspace, as: "year", scope: scope)
    |> AshPhoenix.Form.submit(params: params)
  end

  @year %{"name" => "2031", "start_date" => "2031-09-01", "end_date" => "2032-07-01"}

  test "a form refused by a policy is forbidden", ctx do
    assert {:error, form} = submit_year(ctx.teacher, @year)
    assert Authz.forbidden_form?(form)
  end

  test "a form with validation errors is not forbidden", ctx do
    assert {:error, form} = submit_year(ctx.head, Map.delete(@year, "name"))
    refute Authz.forbidden_form?(form)
  end
end
