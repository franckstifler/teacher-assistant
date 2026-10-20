defmodule TeacherAssistant.Academics.FeesConcurrencyTest do
  # Shared sandbox mode: the two payments run in two processes on one connection.
  use TeacherAssistant.DataCase, async: false

  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.Fees

  test "two concurrent payments get two consecutive numbers" do
    Ecto.Adapters.SQL.Sandbox.mode(TeacherAssistant.Repo, {:shared, self()})
    ctx = fees_school_fixture()

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.async(fn -> Fees.record_payment(ctx.scope, ctx.e, cash(1_000)) end)
      end)
      |> Enum.map(&Task.await(&1, 15_000))

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert results |> Enum.map(fn {:ok, p} -> p.seq end) |> Enum.sort() == [1, 2]
  end
end
