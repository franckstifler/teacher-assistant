defmodule TeacherAssistantWeb.Teacher.SetupLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Reference

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:subsystem, :francophone)
     |> assign(:form, to_form(%{}, as: :setup))}
  end

  def handle_event("subsystem-changed", %{"setup" => %{"subsystem" => sub}}, socket) do
    {:noreply, assign(socket, :subsystem, String.to_existing_atom(sub))}
  end

  def handle_event("save", %{"setup" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, year} <-
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
             weekly_hours: String.to_integer(p["weekly_hours"])
           }) do
      {:noreply,
       socket |> put_flash(:info, gettext("Setup complete")) |> push_navigate(to: ~p"/teacher")}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not complete setup"))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-setup" class="mx-auto max-w-md space-y-5">
        <header>
          <p class="ta-eyebrow">{gettext("First, the basics")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{gettext("Set up your year")}</h1>
        </header>
        <.form
          for={@form}
          id="setup-form"
          phx-change="subsystem-changed"
          phx-submit="save"
          class="space-y-5"
        >
          <fieldset class="ta-leaf space-y-2">
            <legend class="ta-eyebrow px-1">{gettext("Academic year")}</legend>
            <.input field={@form[:name]} label={gettext("Academic year")} value="2025-2026" />
            <div class="grid gap-2 sm:grid-cols-2">
              <.input
                type="date"
                field={@form[:start_date]}
                label={gettext("Start date")}
                value="2025-09-08"
              />
              <.input
                type="date"
                field={@form[:end_date]}
                label={gettext("End date")}
                value="2026-07-31"
              />
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
            <.input
              type="number"
              field={@form[:weekly_hours]}
              label={gettext("Weekly hours")}
              value="4"
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
