defmodule TeacherAssistantWeb.Teacher.ImportLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  @max_pdf_bytes 10_000_000

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace
    year = scope.current_academic_year
    contexts = if ws && year, do: Academics.list_teaching_contexts(ws, year), else: []

    socket =
      socket
      |> assign(:year, year)
      |> assign(:contexts, contexts)
      |> assign(:stage, :upload)
      |> assign(:title, "")
      |> assign(:context_id, contexts |> List.first() |> then(&(&1 && &1.id)))
      |> allow_upload(:fiche, accept: ~w(.pdf), max_entries: 1, max_file_size: @max_pdf_bytes)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="fiche-import" class="mx-auto max-w-2xl space-y-6">
        <header>
          <p class="ta-eyebrow">{gettext("Import a fiche")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">
            {gettext("Import a fiche de progression")}
          </h1>
        </header>

        <div :if={@contexts == []} id="import-context-gate" class="ta-leaf space-y-3 text-sm">
          <p class="text-base-content/70">
            {gettext("Add a subject and class first, then you can import a fiche for it.")}
          </p>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary btn-sm">
            {gettext("Go to setup")}
          </.link>
        </div>

        <.form
          :if={@contexts != []}
          for={%{}}
          id="import-upload-form"
          phx-change="validate"
          phx-submit="extract"
          class="ta-leaf space-y-3"
        >
          <label class="block">
            <span class="label mb-1">{gettext("Subject & class")}</span>
            <select id="import-context-select" name="context_id" class="w-full select">
              <option :for={c <- @contexts} value={c.id} selected={c.id == @context_id}>
                {c.subject} · {c.level}
              </option>
            </select>
          </label>

          <label class="block">
            <span class="label mb-1">{gettext("Plan title")}</span>
            <input
              id="import-title"
              type="text"
              name="title"
              value={@title}
              placeholder={gettext("e.g. Maths 6ème 2025-2026")}
              class="w-full input"
            />
          </label>

          <label class="block">
            <span class="label mb-1">{gettext("Fiche PDF")}</span>
            <.live_file_input upload={@uploads.fiche} class="w-full file-input" />
          </label>

          <p :for={err <- upload_errors(@uploads.fiche)} class="text-sm text-error">
            {upload_error_to_string(err)}
          </p>

          <.button id="import-extract" type="submit" class="btn btn-primary w-full gap-2">
            <.icon name="hero-arrow-up-tray" class="size-4" />
            {gettext("Extract rows")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:title, params["title"] || socket.assigns.title)
     |> assign(:context_id, params["context_id"] || socket.assigns.context_id)}
  end

  # "extract" is implemented in Task 6.
  def handle_event("extract", _params, socket), do: {:noreply, socket}

  defp upload_error_to_string(:too_large), do: gettext("That file is too large (max 10 MB).")
  defp upload_error_to_string(:not_accepted), do: gettext("Please choose a PDF file.")
  defp upload_error_to_string(:too_many_files), do: gettext("Upload one file at a time.")
  defp upload_error_to_string(_), do: gettext("That file could not be uploaded.")
end
