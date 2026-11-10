defmodule TeacherAssistant.Academics.YearOpenCoverageTest do
  @moduledoc "Spec KLM9 rule 5: every write on a year's data checks the year."
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.{
    AcademicYear,
    LessonStep,
    Mark,
    MarkCorrection,
    MarkEvent,
    Payment,
    Student,
    TimetableSlot,
    YearOpen
  }

  # Rule 4: payments stay open (arrears); the journal and a read receipt are not year data;
  # a new year is created open.
  @exempt %{
    Payment => :all,
    MarkEvent => :all,
    MarkCorrection => [:mark_seen],
    AcademicYear => [:create, :create_for_workspace]
  }

  test "every create, update and destroy of a year-bound resource checks the year" do
    missing =
      for resource <- year_bound(),
          action <- Ash.Resource.Info.actions(resource),
          action.type in [:create, :update, :destroy],
          not exempt?(resource, action.name),
          not checks_year?(resource, action),
          do: "#{inspect(resource)}.#{action.name}"

    assert missing == []
  end

  test "the discovery finds the year's data and only it" do
    found = year_bound()

    for resource <- [AcademicYear, Mark, LessonStep, TimetableSlot, Payment],
        do: assert(resource in found, "#{inspect(resource)} not found")

    refute Student in found
  end

  # A resource is year-bound when it carries `academic_year_id` or belongs to a
  # year-bound resource (fixed point over `belongs_to`).
  defp year_bound do
    all =
      :teacher_assistant
      |> Application.fetch_env!(:ash_domains)
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)

    seed =
      MapSet.new([
        AcademicYear | Enum.filter(all, &Ash.Resource.Info.attribute(&1, :academic_year_id))
      ])

    all |> grow(seed) |> MapSet.to_list()
  end

  defp grow(all, set) do
    next =
      Enum.reduce(all, set, fn resource, acc ->
        if Enum.any?(
             Ash.Resource.Info.relationships(resource),
             &(&1.type == :belongs_to and MapSet.member?(set, &1.destination))
           ),
           do: MapSet.put(acc, resource),
           else: acc
      end)

    if MapSet.equal?(next, set), do: set, else: grow(all, next)
  end

  defp exempt?(resource, name) do
    case Map.get(@exempt, resource) do
      :all -> true
      names when is_list(names) -> name in names
      nil -> false
    end
  end

  defp checks_year?(resource, action) do
    Enum.any?(
      Ash.Resource.Info.changes(resource),
      &(year_open?(&1) and action.type in &1.on)
    ) or Enum.any?(action.changes, &year_open?/1)
  end

  defp year_open?(%Ash.Resource.Change{change: {YearOpen, _opts}}), do: true
  defp year_open?(_other), do: false
end
