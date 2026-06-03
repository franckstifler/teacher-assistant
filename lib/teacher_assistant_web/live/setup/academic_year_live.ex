defmodule TeacherAssistantWeb.Setup.AcademicYearLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.AcademicYear

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="academic-year-setup" class="mx-auto max-w-3xl space-y-6">
        <div class="space-y-2">
          <p class="ta-section-label">{gettext("Required setup")}</p>
          <h1 class="text-2xl font-semibold tracking-normal">
            {gettext("Create the current academic year")}
          </h1>
          <p class="text-sm text-base-content/65">
            {gettext(
              "Marks, attendance, progression logs, and coverage reports need a school-year calendar before they can be used."
            )}
          </p>
        </div>

        <.form
          for={@form}
          id="academic-year-setup-form"
          phx-change="validate"
          phx-submit="save"
          class="ta-panel space-y-4 p-5"
        >
          <.input field={@form[:name]} label={gettext("Academic year")} />
          <div class="grid gap-4 sm:grid-cols-2">
            <.input field={@form[:start_date]} type="date" label={gettext("Start date")} />
            <.input field={@form[:end_date]} type="date" label={gettext("End date")} />
          </div>

          <div class="grid gap-4 sm:grid-cols-3">
            <.input field={@form[:term_1_name]} label={gettext("Term 1")} />
            <.input field={@form[:term_2_name]} label={gettext("Term 2")} />
            <.input field={@form[:term_3_name]} label={gettext("Term 3")} />
          </div>

          <div class="flex justify-end">
            <.button id="save-academic-year-setup" class="btn btn-primary">
              <.icon name="hero-check" class="size-4" />
              {gettext("Create academic year")}
            </.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, to_form(default_params(), as: :setup))}
  end

  def handle_event("validate", %{"setup" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :setup))}
  end

  def handle_event("save", %{"setup" => params}, socket) do
    case create_academic_year(socket, params) do
      {:ok, _year} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Academic year created"))
         |> push_navigate(to: ~p"/teacher/progression")}

      {:error, message} ->
        {:noreply,
         socket
         |> put_flash(:error, message)
         |> assign(:form, to_form(params, as: :setup))}
    end
  end

  defp create_academic_year(socket, params) do
    with :ok <- authorize_setup(socket.assigns.scope),
         {:ok, start_date} <- parse_date(params["start_date"]),
         {:ok, end_date} <- parse_date(params["end_date"]),
         :ok <- validate_dates(start_date, end_date) do
      term_names = [
        params["term_1_name"] || "Term 1",
        params["term_2_name"] || "Term 2",
        params["term_3_name"] || "Term 3"
      ]

      terms =
        term_names
        |> Enum.with_index(1)
        |> Enum.map(fn {name, position} ->
          %{
            name: String.trim(name),
            start_date: start_date,
            end_date: end_date,
            position: position
          }
        end)

      AcademicYear
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: String.trim(params["name"] || ""),
          start_date: start_date,
          end_date: end_date,
          active: true,
          terms: terms
        },
        scope: socket.assigns.scope
      )
      |> Ash.create(authorize?: authorize_academic_year_create?(socket.assigns.scope))
      |> case do
        {:ok, year} -> {:ok, year}
        {:error, _error} -> {:error, gettext("Academic year could not be created")}
      end
    else
      {:error, :not_allowed} ->
        {:error, gettext("A school administrator must create the academic year")}

      {:error, :invalid_date} ->
        {:error, gettext("Enter valid start and end dates")}

      {:error, :date_order} ->
        {:error, gettext("End date must be after start date")}
    end
  end

  defp authorize_setup(%{current_workspace_type: :personal_teacher}), do: :ok

  defp authorize_setup(%{current_role: role}) when role in [:admin, :principal, :vice_principal],
    do: :ok

  defp authorize_setup(_scope), do: {:error, :not_allowed}

  defp authorize_academic_year_create?(%{current_workspace_type: :personal_teacher}), do: false
  defp authorize_academic_year_create?(_scope), do: true

  defp default_params do
    today = Date.utc_today()
    year = today.year

    %{
      "name" => "#{year}-#{year + 1}",
      "start_date" => Date.to_iso8601(today),
      "end_date" => Date.to_iso8601(Date.add(today, 300)),
      "term_1_name" => "Term 1",
      "term_2_name" => "Term 2",
      "term_3_name" => "Term 3"
    }
  end

  defp parse_date(value) do
    case Date.from_iso8601(value || "") do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end

  defp validate_dates(start_date, end_date) do
    if Date.compare(end_date, start_date) == :gt do
      :ok
    else
      {:error, :date_order}
    end
  end
end
