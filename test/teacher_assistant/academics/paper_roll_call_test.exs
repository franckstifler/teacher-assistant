defmodule TeacherAssistant.Academics.PaperRollCallTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.PaperRollCall

  test "a week runs Monday to Saturday" do
    assert PaperRollCall.week(~D[2025-09-17]) == {~D[2025-09-15], ~D[2025-09-20]}
    assert PaperRollCall.week(~D[2025-09-15]) == {~D[2025-09-15], ~D[2025-09-20]}
  end

  test "a paper lesson waits until the Monday after its week" do
    assert PaperRollCall.waiting?(~D[2025-09-15], ~D[2025-09-20])
    assert PaperRollCall.waiting?(~D[2025-09-15], ~D[2025-09-21])
    refute PaperRollCall.waiting?(~D[2025-09-15], ~D[2025-09-22])
  end

  test "the default week is the current one, the next from Saturday on" do
    assert PaperRollCall.default_week(~D[2025-09-17]) == ~D[2025-09-15]
    assert PaperRollCall.default_week(~D[2025-09-20]) == ~D[2025-09-22]
    assert PaperRollCall.default_week(~D[2025-09-21]) == ~D[2025-09-22]
  end

  test "a missed lesson of a paper class is on paper while it waits" do
    assert PaperRollCall.state(:missed, true, false, ~D[2025-09-15], ~D[2025-09-16]) == :on_paper
    assert PaperRollCall.state(:missed, false, false, ~D[2025-09-15], ~D[2025-09-16]) == :missed
    assert PaperRollCall.state(:missed, true, false, ~D[2025-09-15], ~D[2025-09-22]) == :missed
  end

  test "done beats not held, not held beats on paper" do
    assert PaperRollCall.state(:done, true, true, ~D[2025-09-15], ~D[2025-09-16]) == :done
    assert PaperRollCall.state(:missed, true, true, ~D[2025-09-15], ~D[2025-09-16]) == :not_held
    assert PaperRollCall.state(:missed, false, true, ~D[2025-09-15], ~D[2025-09-30]) == :not_held
  end

  test "upcoming and in-progress lessons keep their state" do
    assert PaperRollCall.state(:upcoming, true, false, ~D[2025-09-15], ~D[2025-09-15]) ==
             :upcoming

    assert PaperRollCall.state(:in_progress, true, false, ~D[2025-09-15], ~D[2025-09-15]) ==
             :in_progress
  end
end
