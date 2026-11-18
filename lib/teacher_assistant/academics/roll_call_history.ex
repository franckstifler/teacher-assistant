defmodule TeacherAssistant.Academics.RollCallHistory do
  @moduledoc "Saved roll calls for the signed-in teacher's course."

  require Ash.Query

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, Scope}
  alias TeacherAssistant.Academics.{AttendanceEntry, Reference}

  def load(
        %Scope{current_workspace: %{}, current_academic_year: %{} = year, current_user: %{}} =
          scope,
        id,
        params
      ) do
    with true <- Scope.module?(scope, :appel),
         assignments = Curriculum.list_assignments_for_user(scope, year, scope.current_user),
         %{} = context <- Enum.find(assignments, &(&1.id == id)) do
      contexts = course_contexts(assignments, context)
      sequences = Organization.list_sequences(scope, year)
      query = entries_query(contexts, scope)
      sequence = select_sequence(sequences, query, params["seq"], scope)
      date = selected_date(params["date"], year)
      entries = read_entries(query, sequence, date, scope)

      rosters =
        Map.new(contexts, &{&1.id, Enrollment.list_roster(scope, &1.class_group, on: :all)})

      sessions = sessions(entries, rosters)

      {:ok,
       %{
         context: context,
         classes: Map.new(contexts, &{&1.id, &1.class_group.label}),
         sequences: sequences,
         sequence: sequence,
         date: date,
         sessions: sessions,
         students: students(sessions, rosters, sequence),
         assessments: assessments(scope, contexts, sequence)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def load(_scope, _id, _params), do: {:error, :not_found}

  defp course_contexts(_assignments, %{combined_course_id: nil} = context), do: [context]

  defp course_contexts(assignments, context),
    do: Enum.filter(assignments, &(&1.combined_course_id == context.combined_course_id))

  defp entries_query(contexts, scope) do
    ids = Enum.map(contexts, & &1.id)

    AttendanceEntry
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.Query.filter(teaching_context_id in ^ids)
  end

  defp select_sequence([], _query, _id, _scope), do: nil

  defp select_sequence(sequences, query, id, scope) do
    today = Reference.today()

    Enum.find(sequences, &(&1.id == id)) ||
      Enum.find(sequences, &within?(today, &1)) ||
      latest_recorded_sequence(sequences, query, scope) ||
      Enum.find(sequences, &(Date.compare(&1.start_date, today) == :gt)) ||
      List.last(sequences)
  end

  defp latest_recorded_sequence(sequences, query, scope) do
    sequences
    |> Enum.sort_by(& &1.end_date, {:desc, Date})
    |> Enum.find(fn sequence ->
      query
      |> Ash.Query.filter(date >= ^sequence.start_date and date <= ^sequence.end_date)
      |> Ash.exists?(scope: scope)
    end)
  end

  defp selected_date(value, year) when is_binary(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         true <- within?(date, year),
         do: date,
         else: (_ -> nil)
  end

  defp selected_date(_value, _year), do: nil

  defp within?(date, range),
    do: Date.compare(date, range.start_date) != :lt and Date.compare(date, range.end_date) != :gt

  defp read_entries(query, _sequence, %Date{} = date, scope),
    do: query |> Ash.Query.filter(date == ^date) |> load_entries(scope)

  defp read_entries(_query, nil, nil, _scope), do: []

  defp read_entries(query, sequence, nil, scope) do
    query
    |> Ash.Query.filter(date >= ^sequence.start_date and date <= ^sequence.end_date)
    |> load_entries(scope)
  end

  defp load_entries(query, scope),
    do: query |> Ash.Query.load([:period, enrollment: :student]) |> Ash.read!(scope: scope)

  defp sessions(entries, rosters) do
    entries
    |> Enum.group_by(&{&1.date, &1.period_id})
    |> Enum.map(fn {{date, _}, [first | _] = marks} ->
      marked_ids = MapSet.new(marks, & &1.enrollment_id)

      groups =
        marks
        |> Enum.group_by(& &1.teaching_context_id)
        |> Map.new(fn {id, group} ->
          {id, session_group(group, rosters[id], date, marked_ids)}
        end)

      %{date: date, period: first.period, groups: groups}
    end)
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.period.position}, :desc)
  end

  defp session_group(marks, roster, date, marked_ids) do
    saved =
      Map.new(marks, fn mark ->
        {mark.enrollment_id, student_mark(mark.enrollment, mark.status, mark.justified)}
      end)

    roster
    |> Enum.filter(fn %{enrollment: enrollment} ->
      enrolled_on?(enrollment, date) and not MapSet.member?(marked_ids, enrollment.id)
    end)
    |> Enum.reduce(saved, fn %{enrollment: enrollment}, rows ->
      Map.put_new(rows, enrollment.id, student_mark(enrollment, nil, false))
    end)
    |> Map.values()
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  # Enrollment has no separate start date. Saved marks take precedence over its creation timestamp.
  defp enrolled_on?(enrollment, date) do
    Date.compare(DateTime.to_date(enrollment.inserted_at), date) != :gt and
      (is_nil(enrollment.left_on) or Date.compare(date, enrollment.left_on) == :lt)
  end

  defp student_mark(enrollment, status, justified),
    do: %{
      id: enrollment.id,
      name: enrollment.student.full_name,
      status: status,
      justified: justified
    }

  defp students(sessions, rosters, sequence) do
    marks =
      for session <- sessions, {context_id, group} <- session.groups, student <- group do
        {student.id,
         Map.merge(student, %{date: session.date, period: session.period, context_id: context_id})}
      end
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    roster_students =
      for {context_id, roster} <- rosters,
          %{enrollment: enrollment} <- roster,
          sequence &&
            Date.compare(DateTime.to_date(enrollment.inserted_at), sequence.end_date) != :gt,
          is_nil(enrollment.left_on) or
            Date.compare(enrollment.left_on, sequence.start_date) == :gt,
          into: %{} do
        {enrollment.id, Map.put(student_mark(enrollment, nil, false), :context_id, context_id)}
      end

    marks
    |> Map.new(fn {id, [first | _]} -> {id, first} end)
    |> Map.merge(roster_students)
    |> Enum.map(fn {id, student} ->
      history = Map.get(marks, id, [])
      counts = Enum.frequencies_by(history, & &1.status)
      late = Map.get(counts, :late, 0)
      present = Map.get(counts, :present, 0) + late
      absent = Map.get(counts, :absent, 0)

      %{
        id: id,
        context_id: student.context_id,
        name: student.name,
        history: history,
        present: present,
        total: present + absent,
        late: late,
        absent: absent,
        justified: Enum.count(history, &(&1.status == :absent and &1.justified)),
        unmarked: Map.get(counts, nil, 0),
        sent_home: Map.get(counts, :sent_home, 0)
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.name), &1.context_id})
  end

  defp assessments(_scope, _contexts, nil), do: []

  defp assessments(scope, contexts, sequence) do
    if Scope.module?(scope, :notes) do
      contexts
      |> Enum.flat_map(&Assessment.list_assessments(scope, &1, sequence))
      |> Enum.filter(& &1.given_on)
      |> Enum.uniq_by(&{&1.label, &1.given_on})
      |> Enum.sort_by(& &1.given_on, {:desc, Date})
    else
      []
    end
  end
end
