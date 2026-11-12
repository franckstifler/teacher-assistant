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

  test "a covered slot stays covered unless its own roll call or a not-held marking wins" do
    assert PaperRollCall.state(:covered, true, false, ~D[2025-09-15], ~D[2025-09-22]) == :covered
    assert PaperRollCall.state(:covered, false, false, ~D[2025-09-15], ~D[2025-09-15]) == :covered
    assert PaperRollCall.state(:covered, true, true, ~D[2025-09-15], ~D[2025-09-16]) == :not_held
    assert PaperRollCall.state(:done, true, true, ~D[2025-09-15], ~D[2025-09-16]) == :done
  end

  test "upcoming and in-progress lessons keep their state" do
    assert PaperRollCall.state(:upcoming, true, false, ~D[2025-09-15], ~D[2025-09-15]) ==
             :upcoming

    assert PaperRollCall.state(:in_progress, true, false, ~D[2025-09-15], ~D[2025-09-15]) ==
             :in_progress
  end

  test "the entry screen opens on the current week, weekend included" do
    assert PaperRollCall.entry_week(~D[2025-09-17]) == ~D[2025-09-15]
    assert PaperRollCall.entry_week(~D[2025-09-20]) == ~D[2025-09-15]
    assert PaperRollCall.entry_week(~D[2025-09-21]) == ~D[2025-09-15]
  end

  test "a week is kept inside the school year" do
    year = %{start_date: ~D[2025-09-08], end_date: ~D[2026-07-31]}
    assert PaperRollCall.within_year(~D[2024-01-01], year) == ~D[2025-09-08]
    assert PaperRollCall.within_year(~D[2025-10-06], year) == ~D[2025-10-06]
    assert PaperRollCall.within_year(~D[2026-09-07], year) == ~D[2026-07-27]
    assert PaperRollCall.within_year(~D[2026-09-07], nil) == ~D[2026-09-07]
  end
end
