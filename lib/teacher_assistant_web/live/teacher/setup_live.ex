defmodule TeacherAssistantWeb.Teacher.SetupLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.PersonalWorkspace

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Personal setup"))
     |> assign(:form, to_form(default_params(), as: :setup))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="personal-setup" class="mx-auto max-w-4xl space-y-6">
        <.header>
          {gettext("Personal workspace setup")}
          <:subtitle>
            {gettext(
              "Create the private class, subject, calendar, and starter roster used by your teacher tools."
            )}
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="personal-setup-form"
          phx-change="validate"
          phx-submit="save"
          class="ta-panel space-y-5 p-5"
        >
          <div class="grid gap-4 md:grid-cols-3">
            <.input field={@form[:academic_year_name]} label={gettext("Academic year")} />
            <.input field={@form[:start_date]} type="date" label={gettext("Start date")} />
            <.input field={@form[:end_date]} type="date" label={gettext("End date")} />
          </div>

          <div class="grid gap-4 md:grid-cols-4">
            <.input field={@form[:class_name]} label={gettext("Class or group")} />
            <.input field={@form[:option_name]} label={gettext("Option")} />
            <.input field={@form[:subject_name]} label={gettext("Subject")} />
            <.input field={@form[:coefficient]} type="number" min="1" label={gettext("Coefficient")} />
          </div>

          <.input
            field={@form[:students_csv]}
            type="textarea"
            label={gettext("Starter students CSV")}
            placeholder="first_name,last_name,gender\nAda,Nanga,female"
          />

          <div class="flex justify-end">
            <.button
              id="save-personal-setup"
              class="btn btn-primary"
              phx-disable-with={gettext("Saving...")}
            >
              <.icon name="hero-check" class="size-4" />
              {gettext("Create personal workspace")}
            </.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"setup" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :setup))}
  end

  def handle_event("save", %{"setup" => params}, socket) do
    students_csv = params["students_csv"] || ""
    setup_params = Map.delete(params, "students_csv")

    case PersonalWorkspace.create_setup(socket.assigns.scope, setup_params) do
      {:ok, setup} ->
        import_starter_students(socket.assigns.scope, setup.classroom.id, students_csv)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Personal workspace setup created"))
         |> push_navigate(to: ~p"/teacher/students")}

      {:error, :academic_year_already_exists} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Academic year already exists in this personal workspace"))
         |> assign(:form, to_form(params, as: :setup))}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Personal workspace setup could not be created"))
         |> assign(:form, to_form(params, as: :setup))}
    end
  end

  defp import_starter_students(_scope, _classroom_id, csv) when csv in [nil, ""], do: :ok

  defp import_starter_students(scope, classroom_id, csv) do
    if String.trim(csv) == "" do
      :ok
    else
      PersonalWorkspace.import_students(scope, classroom_id, csv)
    end
  end

  defp default_params do
    today = Date.utc_today()

    %{
      "academic_year_name" => "#{today.year}-#{today.year + 1}",
      "start_date" => Date.to_iso8601(today),
      "end_date" => today |> Date.add(300) |> Date.to_iso8601(),
      "class_name" => "Form 1",
      "option_name" => "General",
      "subject_name" => "Mathematics",
      "coefficient" => "1",
      "students_csv" => ""
    }
  end
end
