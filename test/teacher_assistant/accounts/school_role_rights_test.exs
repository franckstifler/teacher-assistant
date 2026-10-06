defmodule TeacherAssistant.Accounts.SchoolRoleRightsTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Accounts.SchoolRole

  @axes [:member, :admin, :head, :conduct, :fees]

  test "every right's axis authorizes its named action in the real policies" do
    for right <- SchoolRole.rights() do
      assert right.axis in @axes, "#{right.key}: unknown axis #{right.axis}"
      action = Ash.Resource.Info.action(right.resource, right.action)
      assert action, "#{right.key}: #{inspect(right.resource)} has no action #{right.action}"

      axes =
        for policy <- Ash.Policy.Info.policies(right.resource),
            applies?(policy, action),
            check <- policy.policies,
            check.type in [:authorize_if, :forbid_unless],
            check.check_module == Checks.SchoolRole,
            do: check.check_opts[:any_of]

      assert right.axis in axes,
             "#{right.key}: #{right.action} is not authorized by #{right.axis} (found #{inspect(axes)})"
    end
  end

  # Whether a policy's condition can apply to `action` (action type or action name).
  defp applies?(policy, action) do
    Enum.all?(List.wrap(policy.condition), fn
      {Ash.Policy.Check.ActionType, opts} -> action.type in List.wrap(opts[:type])
      {Ash.Policy.Check.Action, opts} -> action.name in List.wrap(opts[:action])
      _other -> true
    end)
  end

  test "cells follow the axis, with notes for row rules" do
    discipline = Enum.find(SchoolRole.rights(), &(&1.key == :discipline))
    assert SchoolRole.cell(discipline, :discipline_master) == :yes
    assert SchoolRole.cell(discipline, :bursar) == :no

    assert {:note, _} =
             SchoolRole.cell(Enum.find(SchoolRole.rights(), &(&1.key == :marks)), :teacher)
  end

  test "notes cover the row rules the policies apply" do
    rights = Map.new(SchoolRole.rights(), &{&1.key, &1})
    assert {:note, _} = SchoolRole.cell(rights.corrections, :hod)
    assert {:note, _} = SchoolRole.cell(rights.fees, :teacher)
    assert {:note, _} = SchoolRole.cell(rights.settings, :vice_principal)
    assert SchoolRole.teaching_footnote() =~ "quel que soit le rôle"
  end
end
