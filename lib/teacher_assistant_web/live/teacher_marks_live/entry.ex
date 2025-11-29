defmodule TeacherAssistantWeb.TeacherMarksLive.Entry do
  use TeacherAssistantWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.scope
    current_user = socket.assigns.scope.current_user

    school =
      Ash.read!(TeacherAssistant.Academics.School)
      |> List.first()

    active_year =
      Ash.read!(TeacherAssistant.Academics.AcademicYear,
        action: :get_active_year,
        scope: scope
      )
      |> List.first()

    academic_year =
      case active_year do
        nil ->
          nil

        year ->
          Ash.get!(TeacherAssistant.Academics.AcademicYear, year.id,
            load: [terms: [:sequences]],
            scope: scope
          )
      end

    assignments =
      if academic_year do
        Ash.read!(TeacherAssistant.Academics.SchoolYearSubjectTeacher,
          # filter: [teacher_id: current_user.id],
          load: [classroom: [], level_option_subject: :subject],
          scope: scope
        )
        |> Enum.filter(fn assignment ->
          assignment.classroom.academic_year_id == academic_year.id
        end)
      else
        []
      end

    filters = %{
      "academic_year_id" => academic_year && academic_year.id,
      "term_id" => nil,
      "sequence_id" => nil,
      "classroom_id" => nil,
      "level_option_subject_id" => nil
    }

    {:ok,
     socket
     |> assign(:page_title, gettext("Enter Marks"))
     |> assign(:scope, scope)
     |> assign(:academic_year, academic_year)
     |> assign(:assignments, assignments)
     |> assign(:filters, filters)
     |> assign(:students, [])
     |> assign(:marks_by_student, %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <div class="space-y-6">
        <div class="card bg-base-100 shadow-md">
          <.form
            for={%{}}
            as={:filters}
            id="filters-form"
            phx-change="filter_changed"
            class="card-body grid gap-4 md:grid-cols-4"
          >
            <div>
              <label class="label text-sm font-medium">{gettext("Academic Year")}</label>
              <select
                class="select select-bordered select-sm w-full"
                name="filters[academic_year_id]"
                disabled
              >
                <option value={@academic_year && @academic_year.id}>
                  {(@academic_year && @academic_year.name) || gettext("No active year")}
                </option>
              </select>
            </div>

            <div>
              <label class="label text-sm font-medium">{gettext("Term")}</label>
              <select
                class="select select-bordered select-sm w-full"
                name="filters[term_id]"
              >
                <option value="">{gettext("Select term")}</option>
                <option
                  :for={term <- (@academic_year && @academic_year.terms) || []}
                  value={term.id}
                  selected={@filters["term_id"] == term.id}
                >
                  {term.name}
                </option>
              </select>
            </div>

            <div>
              <label class="label text-sm font-medium">{gettext("Sequence")}</label>
              <select
                class="select select-bordered select-sm w-full"
                name="filters[sequence_id]"
              >
                <option value="">{gettext("Select sequence")}</option>
                <option
                  :for={sequence <- sequences_for_term(@academic_year, @filters["term_id"])}
                  value={sequence.id}
                  selected={@filters["sequence_id"] == sequence.id}
                >
                  {sequence.name}
                </option>
              </select>
            </div>

            <div>
              <label class="label text-sm font-medium">{gettext("Classroom & Subject")}</label>
              <select
                class="select select-bordered select-sm w-full"
                name="filters[classroom_subject]"
              >
                <option value="">{gettext("Select class & subject")}</option>
                <option
                  :for={assignment <- @assignments}
                  value={"#{assignment.classroom_id}:#{assignment.level_option_subject_id}"}
                  selected={
                    @filters["classroom_id"] == assignment.classroom_id and
                      @filters["level_option_subject_id"] == assignment.level_option_subject_id
                  }
                >
                  {assignment_label(assignment)}
                </option>
              </select>
            </div>
          </.form>
        </div>

        <div class="overflow-x-auto rounded-box border border-base-200 bg-base-100/60">
          <table class="table table-zebra table-sm">
            <thead>
              <tr>
                <th>#</th>
                <th>{gettext("Student")}</th>
                <th class="text-right">{gettext("Mark")}</th>
                <th class="text-right">{gettext("Coefficient")}</th>
              </tr>
            </thead>
            <tbody>
              <%= if @students == [] do %>
                <tr>
                  <td colspan="4" class="text-center text-sm text-base-content/70 py-6">
                    {gettext("Select filters to load students and start entering marks.")}
                  </td>
                </tr>
              <% else %>
                <tr :for={{student, index} <- Enum.with_index(@students, 1)}>
                  <td>{index}</td>
                  <td>{student.name}</td>
                  <td class="text-right">
                    <input
                      type="number"
                      step="0.25"
                      min="0"
                      class="input input-bordered input-sm w-24 text-right"
                      name={"marks[#{student.id}][score]"}
                      value={@marks_by_student[student.id] || ""}
                      phx-change="mark_changed"
                    />
                  </td>
                  <td class="text-right">
                    {assignment_coefficient(
                      @assignments,
                      @filters["classroom_id"],
                      @filters["level_option_subject_id"]
                    )}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div class="text-sm text-base-content/80">
            <%= if @students != [] do %>
              <span class="font-medium">
                {length(@students)} {gettext("students")}
              </span>
              <span class="mx-2">•</span>
              <span>
                {gettext("Average:")} {average_mark(@marks_by_student) || "-"}
              </span>
            <% end %>
          </div>

          <div class="flex justify-end">
            <.button
              variant="primary"
              phx-click="save_marks"
              phx-disable-with={gettext("Saving...")}
            >
              {gettext("Save all marks")}
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter_changed", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(params)
      |> normalize_filters(params)

    {students, marks_by_student} =
      load_students_and_marks(
        socket.assigns.scope,
        filters,
        socket.assigns.assignments
      )

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:students, students)
     |> assign(:marks_by_student, marks_by_student)}
  end

  def handle_event("mark_changed", %{"marks" => params}, socket) do
    marks_by_student =
      params
      |> Enum.reduce(socket.assigns.marks_by_student, fn {student_id, %{"score" => score}}, acc ->
        Map.put(acc, student_id, score)
      end)

    {:noreply, assign(socket, :marks_by_student, marks_by_student)}
  end

  def handle_event("save_marks", _params, socket) do
    %{filters: filters, marks_by_student: marks_by_student, scope: scope} = socket.assigns

    with true <- required_filters?(filters) do
      case persist_marks(scope, filters, marks_by_student) do
        :ok ->
          {:noreply, put_flash(socket, :info, gettext("Marks saved successfully"))}

        {:error, :invalid_score} ->
          {:noreply,
           put_flash(socket, :error, gettext("Please enter valid, non-negative numeric scores."))}
      end
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Please select term, sequence and classroom/subject."))}
    end
  end

  defp sequences_for_term(nil, _term_id), do: []

  defp sequences_for_term(%{terms: terms}, term_id) do
    terms
    |> Enum.find(&(&1.id == term_id))
    |> case do
      nil -> []
      term -> term.sequences
    end
  end

  defp assignment_label(assignment) do
    subject_name = assignment.level_option_subject.subject.name

    classroom_name =
      case Map.fetch(assignment.classroom, :name) do
        {:ok, name} when not is_nil(name) -> name
        _ -> gettext("Classroom")
      end

    "#{classroom_name} – #{subject_name}"
  end

  defp assignment_coefficient(assignments, classroom_id, level_option_subject_id) do
    assignments
    |> Enum.find(fn a ->
      a.classroom_id == classroom_id and a.level_option_subject_id == level_option_subject_id
    end)
    |> case do
      nil -> "-"
      assignment -> assignment.level_option_subject.coefficient
    end
  end

  defp normalize_filters(filters, %{"classroom_subject" => value}) when value != "" do
    case String.split(value, ":") do
      [classroom_id, level_option_subject_id] ->
        filters
        |> Map.put("classroom_id", classroom_id)
        |> Map.put("level_option_subject_id", level_option_subject_id)

      _ ->
        filters
    end
  end

  defp normalize_filters(filters, _params), do: filters

  defp required_filters?(filters) do
    filters["sequence_id"] && filters["classroom_id"] && filters["level_option_subject_id"]
  end

  defp average_mark(marks_by_student) do
    scores =
      marks_by_student
      |> Enum.map(fn {_id, score} -> parse_decimal(score) end)
      |> Enum.filter(& &1)

    case scores do
      [] -> nil
      list ->
        avg = Enum.sum(list) / length(list)
        :erlang.float_to_binary(avg, decimals: 2)
    end
  end

  defp persist_marks(scope, filters, marks_by_student) do
    results =
      Enum.map(marks_by_student, fn {student_id, score} ->
        with {:ok, numeric_score} <- parse_score(score) do
          attrs = %{
            score: numeric_score,
            student_id: student_id,
            classroom_id: filters["classroom_id"],
            sequence_id: filters["sequence_id"],
            level_option_subject_id: filters["level_option_subject_id"]
          }

          _ =
            Ash.create!(TeacherAssistant.Academics.Mark, attrs,
              upsert?: true,
              upsert_identity: :unique_mark,
              scope: scope
            )

          :ok
        else
          _ -> {:error, :invalid_score}
        end
      end)

    if Enum.any?(results, &match?({:error, :invalid_score}, &1)) do
      {:error, :invalid_score}
    else
      :ok
    end
  end

  defp parse_score(""), do: {:error, :invalid}
  defp parse_score(nil), do: {:error, :invalid}

  defp parse_score(score) when is_binary(score) do
    case Float.parse(score) do
      {value, _} when value >= 0 -> {:ok, value}
      _ -> {:error, :invalid}
    end
  end

  defp parse_score(score) when is_number(score) and score >= 0, do: {:ok, score}
  defp parse_score(_), do: {:error, :invalid}

  defp parse_decimal(nil), do: nil

  defp parse_decimal(score) when is_binary(score) do
    case Float.parse(score) do
      {value, _} when value >= 0 -> value
      _ -> nil
    end
  end

  defp parse_decimal(score) when is_number(score) and score >= 0, do: score
  defp parse_decimal(_), do: nil

  defp load_students_and_marks(scope, filters, assignments) do
    if required_filters?(filters) do
      students =
        Ash.read!(TeacherAssistant.Academics.ClassroomStudent,
          filter: [classroom_id: filters["classroom_id"]],
          load: :student,
          scope: scope
        )
        |> Enum.map(& &1.student)
        |> Enum.sort_by(& &1.name)

      marks =
        Ash.read!(TeacherAssistant.Academics.Mark,
          filter: [
            classroom_id: filters["classroom_id"],
            sequence_id: filters["sequence_id"],
            level_option_subject_id: filters["level_option_subject_id"]
          ],
          scope: scope
        )

      marks_by_student =
        marks
        |> Enum.into(%{}, fn mark -> {mark.student_id, to_string(mark.score)} end)

      {students, marks_by_student}
    else
      {[], %{}}
    end
  end
end
