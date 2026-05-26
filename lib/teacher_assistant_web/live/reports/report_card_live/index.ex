defmodule TeacherAssistantWeb.Reports.ReportCardLive.Index do
  use TeacherAssistantWeb, :live_view

  require Ash.Query

  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Classroom
  alias TeacherAssistant.Academics.ClassroomStudent
  alias TeacherAssistant.Academics.LevelOptionSubject
  alias TeacherAssistant.Academics.Mark
  alias TeacherAssistant.Academics.ReportCards
  alias TeacherAssistant.Academics.Term

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Report cards"))
     |> assign(:selected_academic_year_id, nil)
     |> assign(:selected_term_id, nil)
     |> assign(:selected_classroom_id, nil)
     |> assign(:terms, [])
     |> assign(:classrooms, [])
     |> assign(:reports, [])
     |> load_academic_years()
     |> assign_filter_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>
          {gettext("Report cards")}
          <:subtitle>
            {gettext("Preview deterministic term report-card averages, rankings, and attendance.")}
          </:subtitle>
        </.header>

        <section class="rounded-md border border-base-300 bg-base-100 p-5 shadow-sm">
          <.form
            for={@filter_form}
            id="report-card-filter"
            phx-change="filter"
            class="grid gap-3 md:grid-cols-3"
          >
            <.input
              field={@filter_form[:academic_year_id]}
              type="select"
              label={gettext("Academic year")}
              options={academic_year_options(@academic_years)}
            />
            <.input
              field={@filter_form[:term_id]}
              type="select"
              label={gettext("Term")}
              options={term_options(@terms)}
            />
            <.input
              field={@filter_form[:classroom_id]}
              type="select"
              label={gettext("Classroom")}
              options={classroom_options(@classrooms)}
            />
          </.form>
        </section>

        <section
          id="report-cards-table"
          class="overflow-x-auto rounded-md border border-base-300 bg-base-100"
        >
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Rank")}</th>
                <th>{gettext("Student")}</th>
                <th>{gettext("Average")}</th>
                <th>{gettext("Total coef.")}</th>
                <th>{gettext("Missing")}</th>
                <th>{gettext("Absences")}</th>
                <th>{gettext("Appreciation")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@selected_classroom_id == nil || @selected_term_id == nil}>
                <td colspan="7" class="py-8 text-center text-sm text-base-content/60">
                  {gettext("Select an academic year, term, and classroom to preview report cards.")}
                </td>
              </tr>
              <tr :if={@selected_classroom_id && @selected_term_id && @reports == []}>
                <td colspan="7" class="py-8 text-center text-sm text-base-content/60">
                  {gettext("No enrolled students found for this classroom.")}
                </td>
              </tr>
              <tr :for={report <- @reports} id={"report-card-row-#{report.student_id}"}>
                <td id={"report-rank-#{report.student_id}"} class="font-semibold">
                  {report.rank}
                </td>
                <td class="font-medium">{report.student_name}</td>
                <td id={"report-average-#{report.student_id}"}>
                  {Decimal.to_string(report.average)}
                </td>
                <td>{report.total_coefficient}</td>
                <td>{report.missing_marks}</td>
                <td id={"report-absences-#{report.student_id}"}>
                  {report.absences}
                </td>
                <td>
                  <span class="badge badge-outline badge-sm">
                    {report.appreciation || gettext("Not configured")}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    socket =
      socket
      |> assign(:selected_academic_year_id, blank_to_nil(params["academic_year_id"]))
      |> assign(:selected_term_id, blank_to_nil(params["term_id"]))
      |> assign(:selected_classroom_id, blank_to_nil(params["classroom_id"]))
      |> load_terms()
      |> load_classrooms()
      |> load_reports()
      |> assign_filter_form()

    {:noreply, socket}
  end

  defp load_academic_years(socket) do
    years =
      AcademicYear
      |> Ash.Query.sort(start_date: :desc)
      |> Ash.read!(scope: socket.assigns.scope)

    assign(socket, :academic_years, years)
  end

  defp load_terms(%{assigns: %{selected_academic_year_id: nil}} = socket) do
    assign(socket, :terms, [])
  end

  defp load_terms(socket) do
    terms =
      Term
      |> Ash.Query.filter(academic_year_id == ^socket.assigns.selected_academic_year_id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(scope: socket.assigns.scope)

    assign(socket, :terms, terms)
  end

  defp load_classrooms(%{assigns: %{selected_academic_year_id: nil}} = socket) do
    assign(socket, :classrooms, [])
  end

  defp load_classrooms(socket) do
    classrooms =
      Classroom
      |> Ash.Query.filter(academic_year_id == ^socket.assigns.selected_academic_year_id)
      |> Ash.Query.load(level_option: [:level, :option])
      |> Ash.read!(scope: socket.assigns.scope)
      |> Enum.sort_by(&classroom_label/1)

    assign(socket, :classrooms, classrooms)
  end

  defp load_reports(%{assigns: %{selected_term_id: nil}} = socket),
    do: assign(socket, :reports, [])

  defp load_reports(%{assigns: %{selected_classroom_id: nil}} = socket),
    do: assign(socket, :reports, [])

  defp load_reports(socket) do
    classroom =
      Ash.get!(Classroom, socket.assigns.selected_classroom_id, scope: socket.assigns.scope)

    term = Ash.get!(Term, socket.assigns.selected_term_id, scope: socket.assigns.scope)
    students = classroom_students(socket)
    subjects = classroom_subjects(socket, classroom)
    marks = term_marks(socket)
    attendances = term_attendances(socket, term)
    intervals = grade_intervals(socket)

    reports =
      students
      |> Enum.map(fn student -> report_for(student, subjects, marks, attendances, intervals) end)
      |> ReportCards.rank_students()

    assign(socket, :reports, reports)
  end

  defp classroom_students(socket) do
    ClassroomStudent
    |> Ash.Query.filter(classroom_id == ^socket.assigns.selected_classroom_id)
    |> Ash.Query.load(:student)
    |> Ash.read!(scope: socket.assigns.scope)
    |> Enum.map(& &1.student)
    |> Enum.sort_by(&student_name/1)
  end

  defp classroom_subjects(socket, classroom) do
    LevelOptionSubject
    |> Ash.Query.filter(level_option_id == ^classroom.level_option_id)
    |> Ash.Query.load(:subject)
    |> Ash.read!(scope: socket.assigns.scope, authorize?: false)
    |> Enum.sort_by(& &1.subject.name)
  end

  defp term_marks(socket) do
    Mark
    |> Ash.Query.filter(
      classroom_id == ^socket.assigns.selected_classroom_id and
        sequence.term_id == ^socket.assigns.selected_term_id
    )
    |> Ash.read!(scope: socket.assigns.scope)
  end

  defp term_attendances(socket, term) do
    Attendance
    |> Ash.Query.filter(
      classroom_id == ^socket.assigns.selected_classroom_id and
        date >= ^term.start_date and
        date <= ^term.end_date
    )
    |> Ash.read!(scope: socket.assigns.scope)
  end

  defp grade_intervals(socket) do
    TeacherAssistant.Academics.GradeInterval
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(scope: socket.assigns.scope)
  end

  defp report_for(student, subjects, marks, attendances, intervals) do
    subject_rows =
      Enum.map(subjects, fn subject ->
        %{
          subject: subject.subject.name,
          coefficient: subject.coefficient,
          score: subject_average(student, subject, marks)
        }
      end)

    summary = ReportCards.summarize_student(subject_rows)

    %{
      student_id: student.id,
      student_name: student_name(student),
      average: summary.average,
      total_coefficient: summary.total_coefficient,
      weighted_total: summary.weighted_total,
      missing_marks: summary.missing_marks,
      absences: attendance_count(attendances, student.id, :absent),
      appreciation: ReportCards.appreciation_for(summary.average, intervals)
    }
  end

  defp subject_average(student, subject, marks) do
    scores =
      marks
      |> Enum.filter(&(&1.student_id == student.id && &1.level_option_subject_id == subject.id))
      |> Enum.map(& &1.score)

    case scores do
      [] ->
        nil

      scores ->
        scores
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
        |> Decimal.div(Decimal.new(length(scores)))
        |> Decimal.round(2)
    end
  end

  defp attendance_count(attendances, student_id, status) do
    Enum.count(attendances, &(&1.student_id == student_id && &1.status == status))
  end

  defp assign_filter_form(socket) do
    assign(
      socket,
      :filter_form,
      to_form(
        %{
          "academic_year_id" => socket.assigns.selected_academic_year_id || "",
          "term_id" => socket.assigns.selected_term_id || "",
          "classroom_id" => socket.assigns.selected_classroom_id || ""
        },
        as: :filters
      )
    )
  end

  defp academic_year_options(years),
    do: [{gettext("Select year"), ""} | Enum.map(years, &{&1.name, &1.id})]

  defp term_options(terms),
    do: [{gettext("Select term"), ""} | Enum.map(terms, &{&1.name, &1.id})]

  defp classroom_options(classrooms),
    do: [{gettext("Select classroom"), ""} | Enum.map(classrooms, &{classroom_label(&1), &1.id})]

  defp classroom_label(%{level_option: %{level: level, option: option}}),
    do: "#{level.name} #{option.name}"

  defp classroom_label(_classroom), do: gettext("Classroom")

  defp student_name(student), do: "#{student.first_name} #{student.last_name}"

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
