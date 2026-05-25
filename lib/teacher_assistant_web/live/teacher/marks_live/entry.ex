defmodule TeacherAssistantWeb.Teacher.MarksLive.Entry do
  use TeacherAssistantWeb, :live_view

  require Ash.Query
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <.icon name="hero-clipboard-document-list" class="w-8 h-8 inline" />
        {gettext("Marks Entry")}
        <:subtitle>
          {gettext("Enter and manage student marks for your classes")}
        </:subtitle>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mt-6">
        <%!-- Filters Card --%>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-funnel" class="w-5 h-5" />
              {gettext("Filters")}
            </h2>

            <.form for={@filter_form} id="filter-form" phx-change="filter_changed">
              <div class="form-control w-full">
                <label class="label">
                  <span class="label-text font-semibold">{gettext("Academic Year")}</span>
                </label>
                <select
                  name="academic_year_id"
                  class="select select-bordered w-full"
                  phx-change="academic_year_changed"
                >
                  <option value="">{gettext("Select year...")}</option>
                  <%= for year <- @academic_years do %>
                    <option value={year.id} selected={year.id == @selected_academic_year_id}>
                      {year.name}
                    </option>
                  <% end %>
                </select>
              </div>

              <%= if @selected_academic_year_id do %>
                <div class="form-control w-full mt-4">
                  <label class="label">
                    <span class="label-text font-semibold">{gettext("Term")}</span>
                  </label>
                  <select
                    name="term_id"
                    class="select select-bordered w-full"
                    phx-change="term_changed"
                  >
                    <option value="">{gettext("Select term...")}</option>
                    <%= for term <- @terms do %>
                      <option value={term.id} selected={term.id == @selected_term_id}>
                        {term.name}
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <%= if @selected_term_id do %>
                <div class="form-control w-full mt-4">
                  <label class="label">
                    <span class="label-text font-semibold">{gettext("Sequence")}</span>
                  </label>
                  <select
                    name="sequence_id"
                    class="select select-bordered w-full"
                    phx-change="sequence_changed"
                  >
                    <option value="">{gettext("Select sequence...")}</option>
                    <%= for sequence <- @sequences do %>
                      <option value={sequence.id} selected={sequence.id == @selected_sequence_id}>
                        {sequence.name}
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <%= if @selected_sequence_id do %>
                <div class="form-control w-full mt-4">
                  <label class="label">
                    <span class="label-text font-semibold">{gettext("Subject")}</span>
                  </label>
                  <select
                    name="subject_id"
                    class="select select-bordered w-full"
                    phx-change="subject_changed"
                  >
                    <option value="">{gettext("Select subject...")}</option>
                    <%= for subject <- @subjects do %>
                      <option value={subject.id} selected={subject.id == @selected_subject_id}>
                        {subject.subject.name}
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <%= if @selected_subject_id do %>
                <div class="form-control w-full mt-4">
                  <label class="label">
                    <span class="label-text font-semibold">{gettext("Class")}</span>
                  </label>
                  <select
                    name="classroom_id"
                    class="select select-bordered w-full"
                    phx-change="classroom_changed"
                  >
                    <option value="">{gettext("Select class...")}</option>
                    <%= for classroom <- @classrooms do %>
                      <option value={classroom.id} selected={classroom.id == @selected_classroom_id}>
                        {classroom.level_option.full_name}
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>
            </.form>

            <%= if @selected_sequence_id do %>
              <div class="alert alert-info mt-4">
                <.icon name="hero-information-circle" />
                <div>
                  <div class="font-semibold">{gettext("Sequence Objective")}</div>
                  <%!-- <div class="text-sm">{@sequence_objective || gettext("No objective set")}</div> --%>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Marks Entry Table --%>
        <div class="lg:col-span-2">
          <%= if @selected_subject_id && @selected_classroom_id do %>
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <div class="flex justify-between items-center mb-4">
                  <h2 class="card-title">
                    <.icon name="hero-pencil-square" class="w-5 h-5" />
                    {gettext("Student Marks")}
                  </h2>
                  <button phx-click="save_all" class="btn btn-primary">
                    <.icon name="hero-check" class="w-5 h-5" />
                    {gettext("Save All")}
                  </button>
                </div>

                <div class="overflow-x-auto">
                  <table class="table table-zebra">
                    <thead>
                      <tr>
                        <th class="w-1/12">{gettext("#")}</th>
                        <th class="w-5/12">{gettext("Student Name")}</th>
                        <th class="w-2/12 text-center">{gettext("Mark (/20)")}</th>
                        <th class="w-4/12">{gettext("Comment")}</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {student, index} <- Enum.with_index(@students, 1) do %>
                        <% mark = find_mark(@marks, student.id) %>
                        <tr class="hover">
                          <td class="font-semibold">{index}</td>
                          <td>
                            <div class="flex items-center gap-2">
                              <.icon name="hero-user-circle" class="w-5 h-5 text-primary" />
                              <span class="font-medium">{student.full_name}</span>
                            </div>
                          </td>
                          <td>
                            <input
                              type="number"
                              step="0.25"
                              min="0"
                              max="20"
                              value={mark && mark.score}
                              phx-blur="update_mark"
                              phx-value-student-id={student.id}
                              phx-value-mark-id={mark && mark.id}
                              name="score"
                              class="input input-bordered w-full text-center"
                              placeholder="0.00"
                            />
                          </td>
                          <td>
                            <input
                              type="text"
                              value={mark && mark.comment}
                              phx-blur="update_comment"
                              phx-value-student-id={student.id}
                              phx-value-mark-id={mark && mark.id}
                              name="comment"
                              class="input input-bordered w-full"
                              placeholder={gettext("Optional comment...")}
                            />
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>

                <%= if Enum.empty?(@students) do %>
                  <div class="alert alert-warning">
                    <.icon name="hero-exclamation-triangle" />
                    <span>{gettext("No students enrolled in this class")}</span>
                  </div>
                <% end %>

                <div class="stats shadow mt-4">
                  <div class="stat">
                    <div class="stat-title">{gettext("Total Students")}</div>
                    <div class="stat-value text-primary">{length(@students)}</div>
                  </div>
                  <div class="stat">
                    <div class="stat-title">{gettext("Marks Entered")}</div>
                    <div class="stat-value text-success">{length(@marks)}</div>
                  </div>
                  <div class="stat">
                    <div class="stat-title">{gettext("Remaining")}</div>
                    <div class="stat-value text-warning">{length(@students) - length(@marks)}</div>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body items-center text-center">
                <.icon name="hero-arrow-left" class="w-16 h-16 text-base-content/20" />
                <h3 class="text-xl font-semibold text-base-content/50">
                  {gettext("Select filters to begin")}
                </h3>
                <p class="text-base-content/40">
                  {gettext("Choose academic year, term, sequence, class, and subject to enter marks")}
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    academic_years =
      Ash.read!(TeacherAssistant.Academics.AcademicYear,
        scope: socket.assigns.scope
        # sort: [start_date: :desc]
      )

    {:ok,
     socket
     |> assign(:academic_years, academic_years)
     |> assign(:terms, [])
     |> assign(:sequences, [])
     |> assign(:classrooms, [])
     |> assign(:subjects, [])
     |> assign(:students, [])
     |> assign(:marks, [])
     |> assign(:selected_academic_year_id, nil)
     |> assign(:selected_term_id, nil)
     |> assign(:selected_sequence_id, nil)
     |> assign(:selected_classroom_id, nil)
     |> assign(:selected_subject_id, nil)
     |> assign(:sequence_objective, nil)
     |> assign(:filter_form, to_form(%{}))}
  end

  @impl true
  def handle_event("academic_year_changed", %{"academic_year_id" => year_id}, socket) do
    terms =
      if year_id != "" do
        TeacherAssistant.Academics.Term
        |> Ash.Query.filter(academic_year_id: year_id)
        |> Ash.Query.sort(position: :asc)
        |> Ash.read!(scope: socket.assigns.scope)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_academic_year_id, if(year_id == "", do: nil, else: year_id))
     |> assign(:terms, terms)
     |> assign(:sequences, [])
     |> assign(:classrooms, [])
     |> assign(:subjects, [])
     |> assign(:students, [])
     |> assign(:marks, [])
     |> assign(:selected_term_id, nil)
     |> assign(:selected_sequence_id, nil)
     |> assign(:selected_classroom_id, nil)
     |> assign(:selected_subject_id, nil)}
  end

  def handle_event("term_changed", %{"term_id" => term_id}, socket) do
    sequences =
      if term_id != "" do
        TeacherAssistant.Academics.Sequence
        |> Ash.Query.filter(term_id: term_id)
        |> Ash.Query.sort(position: :asc)
        |> Ash.read!(scope: socket.assigns.scope)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_term_id, if(term_id == "", do: nil, else: term_id))
     |> assign(:sequences, sequences)
     |> assign(:classrooms, [])
     |> assign(:subjects, [])
     |> assign(:students, [])
     |> assign(:marks, [])
     |> assign(:selected_sequence_id, nil)
     |> assign(:selected_classroom_id, nil)
     |> assign(:selected_subject_id, nil)}
  end

  def handle_event("sequence_changed", %{"sequence_id" => sequence_id}, socket) do
    subjects =
      if sequence_id != "" do
        assignments =
          TeacherAssistant.Academics.TeachingAssignment
          |> Ash.Query.filter(
            teacher_id == ^socket.assigns.current_user.id and
              classroom.academic_year_id == ^socket.assigns.selected_academic_year_id
          )
          |> Ash.read!(
            load: [level_option_subject: [:subject]],
            scope: socket.assigns.scope
          )

        assignments
        |> Enum.map(& &1.level_option_subject)
        |> Enum.uniq_by(& &1.id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:subjects, subjects)
     |> assign(:classrooms, [])
     |> assign(:students, [])
     |> assign(:marks, [])
     |> assign(:selected_sequence_id, if(sequence_id == "", do: nil, else: sequence_id))
     |> assign(:selected_subject_id, nil)
     |> assign(:selected_classroom_id, nil)}
  end

  def handle_event("classroom_changed", %{"classroom_id" => classroom_id}, socket) do
    {students, marks} =
      if classroom_id != "" && socket.assigns.selected_subject_id &&
           socket.assigns.selected_sequence_id do
        load_students_and_marks(
          classroom_id,
          socket.assigns.selected_subject_id,
          socket.assigns.selected_sequence_id,
          socket
        )
      else
        {[], []}
      end

    {:noreply,
     socket
     |> assign(:selected_classroom_id, if(classroom_id == "", do: nil, else: classroom_id))
     |> assign(:students, students)
     |> assign(:marks, marks)}
  end

  def handle_event("subject_changed", %{"subject_id" => subject_id}, socket) do
    classrooms =
      if subject_id != "" do
        classrooms_for_subject(subject_id, socket)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_subject_id, if(subject_id == "", do: nil, else: subject_id))
     |> assign(:classrooms, classrooms)
     |> assign(:selected_classroom_id, nil)
     |> assign(:students, [])
     |> assign(:marks, [])}
  end

  def handle_event(
        "update_mark",
        %{"student-id" => student_id, "value" => score},
        socket
      ) do
    score_decimal =
      case Decimal.parse(score) do
        {decimal, _} -> decimal
        :error -> Decimal.new("0")
      end

    params = %{
      student_id: student_id,
      classroom_id: socket.assigns.selected_classroom_id,
      sequence_id: socket.assigns.selected_sequence_id,
      level_option_subject_id: socket.assigns.selected_subject_id,
      score: score_decimal
    }

    case TeacherAssistant.Academics.save_mark(params, scope: socket.assigns.scope) do
      {:ok, _mark} ->
        {:noreply, assign(socket, :marks, read_marks(socket))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save mark"))}
    end
  end

  def handle_event(
        "update_comment",
        %{"student-id" => student_id, "mark-id" => mark_id, "value" => comment},
        socket
      ) do
    result =
      if mark_id != "" do
        mark = Enum.find(socket.assigns.marks, &(&1.id == mark_id))

        Ash.update(mark, :update,
          params: %{comment: comment},
          scope: socket.assigns.scope
        )
      else
        Ash.create(TeacherAssistant.Academics.Mark, :create,
          params: %{
            student_id: student_id,
            classroom_id: socket.assigns.selected_classroom_id,
            sequence_id: socket.assigns.selected_sequence_id,
            level_option_subject_id: socket.assigns.selected_subject_id,
            score: Decimal.new("0"),
            comment: comment
          },
          scope: socket.assigns.scope
        )
      end

    case result do
      {:ok, _mark} ->
        {:noreply, assign(socket, :marks, read_marks(socket))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save comment"))}
    end
  end

  def handle_event("save_all", _params, socket) do
    {:noreply, put_flash(socket, :info, gettext("All marks saved successfully"))}
  end

  defp classrooms_for_subject(level_option_subject_id, socket) do
    TeacherAssistant.Academics.TeachingAssignment
    |> Ash.Query.filter(
      teacher_id == ^socket.assigns.current_user.id and
        level_option_subject_id == ^level_option_subject_id and
        classroom.academic_year_id == ^socket.assigns.selected_academic_year_id
    )
    |> Ash.read!(
      load: [classroom: [level_option: [:full_name]]],
      scope: socket.assigns.scope
    )
    |> Enum.map(& &1.classroom)
    |> Enum.uniq_by(& &1.id)
  end

  defp load_students_and_marks(classroom_id, level_option_subject_id, sequence_id, socket) do
    students =
      TeacherAssistant.Academics.list_students_by_classroom(classroom_id,
        load: [:full_name],
        scope: socket.assigns.scope
      )

    marks = read_marks(socket, classroom_id, level_option_subject_id, sequence_id)

    {students, marks}
  end

  defp read_marks(socket) do
    read_marks(
      socket,
      socket.assigns.selected_classroom_id,
      socket.assigns.selected_subject_id,
      socket.assigns.selected_sequence_id
    )
  end

  defp read_marks(socket, classroom_id, level_option_subject_id, sequence_id) do
    TeacherAssistant.Academics.Mark
    |> Ash.Query.filter(
      sequence_id == ^sequence_id and
        classroom_id == ^classroom_id and
        level_option_subject_id == ^level_option_subject_id
    )
    |> Ash.read!(scope: socket.assigns.scope)
  end

  defp find_mark(marks, student_id) do
    Enum.find(marks, &(&1.student_id == student_id))
  end
end
