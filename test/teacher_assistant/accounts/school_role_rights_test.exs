defmodule TeacherAssistant.Accounts.SchoolRoleRightsTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Accounts.SchoolRole

  @axes [:member, :admin, :head, :conduct, :fees]

  test "every right names a real axis and a resource whose policies use it" do
    for right <- SchoolRole.rights() do
      assert right.axis in @axes, "#{right.key}: unknown axis #{right.axis}"

      checks =
        for policy <- Ash.Policy.Info.policies(right.resource),
            check <- policy.policies,
            do: check

      assert Enum.any?(checks, &(&1.check_module == Checks.SchoolRole and &1.check_opts[:any_of] == right.axis)),
             "#{right.key}: #{inspect(right.resource)} has no #{right.axis} check"
    end
  end

  test "cells follow the axis, with notes for row rules" do
    discipline = Enum.find(SchoolRole.rights(), &(&1.key == :discipline))
    assert SchoolRole.cell(discipline, :discipline_master) == :yes
    assert SchoolRole.cell(discipline, :bursar) == :no
    assert {:note, _} = SchoolRole.cell(Enum.find(SchoolRole.rights(), &(&1.key == :marks)), :teacher)
  end
end
