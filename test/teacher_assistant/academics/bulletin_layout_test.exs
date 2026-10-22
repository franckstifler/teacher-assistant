defmodule TeacherAssistant.Academics.BulletinLayoutTest do
  @moduledoc "Spec bulletin v2 §5.6: the density tier that keeps a card on one page."
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.BulletinLayout

  defp template(elements), do: %{elements: elements}
  defp groups(n), do: [%{group: :all, rows: List.duplicate(%{}, n)}]

  defp tier(n, elements, kind \\ :trimester) do
    t = template(elements)
    lines = BulletinLayout.subject_lines(t, kind, groups(n), 2, false)
    BulletinLayout.density(lines, BulletinLayout.identity_rows(t))
  end

  test "15 subjects without APC fit the normal tier" do
    assert tier(15, [:guardians]) == :normal
  end

  test "15 subjects with APC on a trimester card are compact" do
    assert BulletinLayout.subject_lines(template([:apc]), :trimester, groups(15), 2, false) == 31
    assert tier(15, [:apc, :guardians]) == :compact
  end

  test "18 subjects with APC are dense" do
    assert tier(18, [:apc, :guardians]) == :dense
  end

  test "30 subjects with APC overflow" do
    assert tier(30, [:apc, :guardians]) == :overflow
  end

  test "an annual card with APC counts one line per subject" do
    assert BulletinLayout.subject_lines(template([:apc]), :annual, groups(15), 2, false) == 16
  end

  test "every group prints a header row; subtotals add a total per group" do
    two = [%{group: :one, rows: [%{}, %{}]}, %{group: :two, rows: [%{}]}]
    assert BulletinLayout.subject_lines(template([]), :trimester, two, 2, false) == 5
    assert BulletinLayout.subject_lines(template([]), :trimester, two, 2, true) == 7
  end

  test "identity rows grow with the guardians" do
    assert BulletinLayout.identity_rows(template([])) == 4
    assert BulletinLayout.identity_rows(template([:guardians])) == 5
  end
end
