defmodule TeacherAssistantWeb.Configurations.GradeIntervalLive.Index do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.GradeInterval

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Grade intervals"))
     |> assign(:form, grade_interval_form())
     |> load_grade_intervals()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col gap-6">
        <.header>
          {gettext("Grade intervals")}
          <:subtitle>
            {gettext("Configure school-level appreciations used by marks and report cards.")}
          </:subtitle>
        </.header>

        <section class="grid gap-6 lg:grid-cols-[minmax(0,0.75fr)_minmax(0,1.25fr)]">
          <div class="rounded-md border border-base-300 bg-base-100 p-5 shadow-sm">
            <h2 class="text-base font-semibold">{gettext("New interval")}</h2>

            <.form
              for={@form}
              id="grade-interval-form"
              phx-submit="save"
              class="mt-4 grid gap-4"
            >
              <div class="grid gap-3 sm:grid-cols-2">
                <.input field={@form[:min_score]} type="number" label={gettext("Min")} step="0.01" />
                <.input field={@form[:max_score]} type="number" label={gettext("Max")} step="0.01" />
              </div>
              <.input field={@form[:label]} type="text" label={gettext("Label")} />
              <.input field={@form[:appreciation]} type="text" label={gettext("Appreciation")} />
              <.input field={@form[:position]} type="number" label={gettext("Position")} />

              <div class="flex justify-end">
                <.button variant="primary">
                  <.icon name="hero-plus" class="size-4" />
                  {gettext("Add interval")}
                </.button>
              </div>
            </.form>
          </div>

          <div
            id="grade-intervals"
            class="overflow-x-auto rounded-md border border-base-300 bg-base-100"
          >
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Range")}</th>
                  <th>{gettext("Label")}</th>
                  <th>{gettext("Appreciation")}</th>
                  <th class="text-right">{gettext("Actions")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@grade_intervals == []}>
                  <td colspan="4" class="py-8 text-center text-sm text-base-content/60">
                    {gettext("No grade intervals configured yet.")}
                  </td>
                </tr>
                <tr :for={interval <- @grade_intervals} id={"grade-interval-#{interval.id}"}>
                  <td class="font-medium">
                    {Decimal.to_string(interval.min_score)} - {Decimal.to_string(interval.max_score)}
                  </td>
                  <td>{interval.label}</td>
                  <td>{interval.appreciation}</td>
                  <td class="text-right">
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-error"
                      phx-click="delete"
                      phx-value-id={interval.id}
                      data-confirm={gettext("Delete this interval?")}
                    >
                      <.icon name="hero-trash" class="size-4" />
                      {gettext("Delete")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save", %{"grade_interval" => params}, socket) do
    case Ash.create(GradeInterval, params, scope: socket.assigns.scope) do
      {:ok, _interval} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Grade interval created successfully"))
         |> assign(:form, grade_interval_form())
         |> load_grade_intervals()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    interval = Ash.get!(GradeInterval, id, scope: socket.assigns.scope)
    Ash.destroy!(interval, scope: socket.assigns.scope)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Grade interval deleted successfully"))
     |> load_grade_intervals()}
  end

  defp load_grade_intervals(socket) do
    intervals =
      GradeInterval
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(scope: socket.assigns.scope)

    assign(socket, :grade_intervals, intervals)
  end

  defp grade_interval_form do
    to_form(
      %{
        "min_score" => "",
        "max_score" => "",
        "label" => "",
        "appreciation" => "",
        "position" => "0"
      },
      as: :grade_interval
    )
  end
end
