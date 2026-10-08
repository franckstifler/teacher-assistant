defmodule TeacherAssistant.Academics.AssignmentGrid do
  @moduledoc """
  The school's assignments overview (spec J2, T04), pure: which class × subject cells
  are assigned, still to assign (the coefficient grid says the subject is taught there)
  or not taught, and each teacher's weekly load against their statutory service. A
  combined course counts once in its teacher's load.
  """
  alias TeacherAssistant.Academics.CoefficientRules

  def build(%{classes: classes, subjects: subjects, contexts: contexts, cells: cells} = input) do
    by_cell = Map.new(contexts, &{{&1.class_group_id, &1.subject_id}, &1})
    loads = loads(contexts, input)

    all =
      for c <- classes, s <- subjects, into: %{} do
        {{c.id, s.id}, cell(Map.get(by_cell, {c.id, s.id}), c, s, cells, loads)}
      end

    kept =
      Enum.filter(subjects, fn s ->
        Enum.any?(classes, &(all[{&1.id, s.id}].kind != :not_taught))
      end)

    kept_ids = MapSet.new(kept, & &1.id)

    %{
      classes: classes,
      subjects: kept,
      cells: Map.filter(all, fn {{_c, s}, _} -> MapSet.member?(kept_ids, s) end),
      loads: loads,
      school_hours: input.school_hours,
      services: input.services,
      to_assign: Enum.count(all, fn {_, cell} -> cell.kind == :to_assign end),
      without_pp: Enum.count(classes, &is_nil(&1.form_master_user_id))
    }
  end

  defp cell(%{} = tc, _c, _s, _cells, loads) do
    %{
      kind: :assigned,
      tc: tc,
      teacher_id: tc.teacher_user_id,
      over?: get_in(loads, [tc.teacher_user_id, :over?]) || false,
      combined?: not is_nil(tc.combined_course_id)
    }
  end

  defp cell(nil, c, s, cells, _loads),
    do: if(expected?(cells, c, s), do: %{kind: :to_assign}, else: %{kind: :not_taught})

  @doc """
  Whether the coefficient grid says `subject` is taught in `class` (its série's
  cell, else its level's blank-série cell). An inactive subject never is.
  """
  def expected?(_cells, _class, %{active?: false}), do: false

  def expected?(cells, class, subject) do
    key = %{
      subject_id: subject.id,
      subsystem: class.subsystem,
      level: class.level,
      serie: class.serie
    }

    CoefficientRules.resolve(cells, key) != nil
  end

  defp loads(contexts, input) do
    contexts
    |> Enum.group_by(& &1.teacher_user_id)
    |> Map.new(fn {teacher, tcs} ->
      load =
        tcs
        |> Enum.uniq_by(&(&1.combined_course_id || {:solo, &1.id}))
        |> Enum.map(&(&1.weekly_hours || 0))
        |> Enum.sum()

      service = service(input, teacher)
      {teacher, %{load: load, service: service, over?: load > service}}
    end)
  end

  @doc "A teacher's own service: their override, else the school's."
  def service(%{services: services, school_hours: school}, teacher_id),
    do: Map.get(services, teacher_id) || school

  @doc """
  The teacher's load if they took a cell of `hours`, currently held by `current_id`
  at `old_hours`: the holder's old hours are replaced, anyone else's are added.
  """
  def load_after(grid, teacher_id, hours, current_id, old_hours \\ 0) do
    current = get_in(grid.loads, [teacher_id, :load]) || 0

    if teacher_id == current_id,
      do: current - (old_hours || 0) + (hours || 0),
      else: current + (hours || 0)
  end
end
