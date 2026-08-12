defmodule TeacherAssistantWeb.Teacher.SetupLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Reference

  def mount(_params, _session, socket) do
    if socket.assigns.current_scope.current_workspace_type == :school do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      {:ok,
       socket
       |> assign(:subsystem, :francophone)
       |> assign(
         :form,
         to_form(
           %{
             "name" => "2025-2026",
             "start_date" => "2025-09-08",
             "end_date" => "2026-07-31",
             "weekly_hours" => "4"
           },
           as: :setup
         )
       )}
    end
  end

  def handle_event("subsystem-changed", %{"setup" => %{"subsystem" => sub} = p}, socket) do
    {:noreply,
     socket
     |> assign(:subsystem, String.to_existing_atom(sub))
     |> assign(:form, to_form(p, as: :setup))}
  end

  def handle_event("save", %{"setup" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {wh, ""} <- Integer.parse(p["weekly_hours"] || ""),
         {:ok, year} <-
           Academics.create_academic_year(ws, %{
             name: p["name"],
             start_date: p["start_date"],
             end_date: p["end_date"],
             active: true
           }),
         :ok <- Academics.build_default_calendar(year),
         {:ok, _ctx} <-
           Academics.create_teaching_context(ws, year, %{
             subject: p["subject"],
             level: p["level"],
             subsystem: String.to_existing_atom(p["subsystem"]),
             weekly_hours: wh,
             annual_hours: parse_decimal(p["annual_hours"]),
             target_module_count: parse_int(p["target_module_count"]),
             target_lesson_count: parse_int(p["target_lesson_count"])
           }) do
      {:noreply,
       socket |> put_flash(:info, gettext("Setup complete")) |> push_navigate(to: ~p"/teacher")}
    else
      error ->
        {:noreply,
         socket
         |> assign(:form, to_form(p, as: :setup))
         |> put_flash(:error, setup_error(error))}
    end
  end

  defp setup_error(:error),
    do: gettext("Weekly hours must be a whole number, e.g. 4")

  defp setup_error({_n, rest}) when is_binary(rest),
    do: gettext("Weekly hours must be a whole number, e.g. 4")

  defp setup_error({:error, %{errors: [first | _]}}) do
    detail =
      case first do
        %{field: field, message: message} when not is_nil(field) and is_binary(message) ->
          "#{field}: #{message}"

        %{message: message} when is_binary(message) ->
          message

        other ->
          Exception.message(other)
      end

    gettext("Could not complete setup") <> " — " <> detail
  end

  defp setup_error(_), do: gettext("Could not complete setup")

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(s) when is_binary(s) do
    case Decimal.parse(String.trim(s)) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-setup" class="mx-auto max-w-md space-y-5">
        <.page_header eyebrow={gettext("First, the basics")} title={gettext("Set up your year")} />

        <ul id="setup-stepper" class="steps w-full text-xs">
          <li class="step step-primary">{gettext("Année")}</li>
          <li class="step step-primary">{gettext("Classe")}</li>
        </ul>

        <.form
          for={@form}
          id="setup-form"
          phx-change="subsystem-changed"
          phx-submit="save"
          class="space-y-5"
        >
          <fieldset class="ta-leaf space-y-2">
            <legend class="ta-eyebrow px-1">{gettext("Academic year")}</legend>
            <.input field={@form[:name]} label={gettext("Academic year")} />
            <div class="grid gap-2 sm:grid-cols-2">
              <.input type="date" field={@form[:start_date]} label={gettext("Start date")} />
              <.input type="date" field={@form[:end_date]} label={gettext("End date")} />
            </div>
          </fieldset>

          <fieldset class="ta-leaf space-y-2">
            <legend class="ta-eyebrow px-1">{gettext("What you teach")}</legend>
            <.input
              type="select"
              field={@form[:subsystem]}
              label={gettext("Subsystem")}
              options={for s <- Reference.subsystems(), do: {s.fr, s.key}}
            />
            <p id="setup-help-subsystem" class="text-xs text-base-content/55">
              {gettext("Francophone or Anglophone track — this sets the class levels you can pick.")}
            </p>
            <div class="grid gap-2 sm:grid-cols-2">
              <.input
                type="select"
                field={@form[:subject]}
                label={gettext("Subject")}
                options={for s <- Reference.subjects(), do: {s.fr, s.fr}}
              />
              <.input
                type="select"
                field={@form[:level]}
                label={gettext("Class")}
                options={for l <- Reference.levels(@subsystem), do: {l, l}}
              />
            </div>
            <.input type="number" field={@form[:weekly_hours]} label={gettext("Weekly hours")} />
            <p id="setup-help-hours" class="text-xs text-base-content/55">
              {gettext("Hours per week on your timetable for this subject and class.")}
            </p>
            <.input
              type="number"
              field={@form[:annual_hours]}
              label={gettext("Horaire annuel")}
              step="0.5"
            />
            <.input
              type="number"
              field={@form[:target_module_count]}
              label={gettext("Cible modules")}
            />
            <.input
              type="number"
              field={@form[:target_lesson_count]}
              label={gettext("Cible leçons")}
            />
          </fieldset>

          <.button id="setup-submit" type="submit" class="btn btn-primary w-full gap-2">
            {gettext("Finish")}
            <.icon name="hero-arrow-right" class="size-4" />
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
