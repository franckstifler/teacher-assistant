defmodule TeacherAssistantWeb.Teacher.ImportLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  @max_pdf_bytes 10_000_000

  @max_rows 300

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace
    year = scope.current_academic_year
    contexts = if ws && year, do: Academics.list_teaching_contexts(ws, year), else: []

    socket =
      socket
      |> assign(:contexts, contexts)
      |> assign(:stage, :upload)
      |> assign(:title, "")
      |> assign(:context_id, contexts |> List.first() |> then(&(&1 && &1.id)))
      |> assign(:rows, [])
      |> assign(:confidence, :high)
      |> assign(:raw_text, "")
      |> assign(:capped?, false)
      |> assign(:sequences, (year && Academics.list_sequences(year)) || [])
      |> allow_upload(:fiche, accept: ~w(.pdf), max_entries: 1, max_file_size: @max_pdf_bytes)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="fiche-import" class="mx-auto max-w-2xl space-y-6">
        <.page_header
          eyebrow={gettext("Import a fiche")}
          title={gettext("Import a fiche de progression")}
        />

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

        <div :if={@stage == :review} id="import-review" class="space-y-4">
          <div :if={@capped?} id="import-truncation-notice" class="alert alert-warning text-sm">
            {gettext("This plan was truncated to 300 rows — the original fiche had more entries.")}
          </div>

          <div :if={@confidence == :low} class="ta-leaf space-y-2 text-sm">
            <p class="font-semibold text-warning">
              {gettext("We couldn't read this fiche as a table.")}
            </p>
            <p class="text-base-content/70">
              {gettext("Add rows manually below. The extracted text is shown for reference.")}
            </p>
            <pre
              id="import-raw-text"
              class="ta-num max-h-48 overflow-auto whitespace-pre-wrap text-xs text-base-content/60"
            >{@raw_text}</pre>
          </div>

          <p :if={@confidence == :high} class="ta-eyebrow">
            {gettext("Review and fix before saving")}
          </p>

          <.form for={%{}} id="import-review-form" phx-submit="save" class="space-y-3">
            <input type="hidden" name="title" value={@title} />

            <ul id="import-rows" class="space-y-2">
              <li
                :for={{row, i} <- Enum.with_index(@rows)}
                id={"import-row-#{i}"}
                class="ta-leaf space-y-2"
              >
                <div class="grid gap-2 sm:grid-cols-2">
                  <input
                    name={"rows[#{i}][module]"}
                    value={row.module}
                    placeholder={gettext("Module")}
                    class="w-full input input-sm"
                  />
                  <input
                    name={"rows[#{i}][lesson_title]"}
                    value={row.lesson_title}
                    placeholder={gettext("Lesson")}
                    class="w-full input input-sm"
                  />
                </div>
                <div class="grid gap-2 sm:grid-cols-4">
                  <input
                    name={"rows[#{i}][planned_hours]"}
                    value={row.planned_hours}
                    type="number"
                    step="0.5"
                    placeholder={gettext("Hours")}
                    class="w-full input input-sm"
                  />
                  <select name={"rows[#{i}][entry_type]"} class="w-full select select-sm">
                    <option
                      :for={t <- entry_type_options()}
                      value={t.key}
                      selected={to_string(t.key) == to_string(row.entry_type)}
                    >
                      {t.fr}
                    </option>
                  </select>
                  <input
                    name={"rows[#{i}][week_no]"}
                    value={row.week_no}
                    type="number"
                    placeholder={gettext("Week")}
                    class="w-full input input-sm"
                  />
                  <select name={"rows[#{i}][sequence_id]"} class="w-full select select-sm">
                    <option value="">{gettext("Sequence…")}</option>
                    <option
                      :for={s <- @sequences}
                      value={s.id}
                      selected={s.number == row.sequence_no}
                    >
                      {gettext("Seq")} {s.number}
                    </option>
                  </select>
                </div>
                <button
                  type="button"
                  phx-click="delete-row"
                  phx-value-index={i}
                  class="btn btn-ghost btn-xs text-error"
                >
                  <.icon name="hero-trash" class="size-4" />
                  <span class="sr-only">{gettext("Delete row")}</span>
                </button>
              </li>
            </ul>

            <button
              type="button"
              id="import-add-row"
              phx-click="add-row"
              class="btn btn-ghost btn-sm gap-2"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Add row")}
            </button>

            <.button id="import-save" type="submit" class="btn btn-primary w-full gap-2">
              <.icon name="hero-check" class="size-4" /> {gettext("Save as draft plan")}
            </.button>
          </.form>
        </div>
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

  def handle_event("extract", params, socket) do
    title = params["title"] || socket.assigns.title
    context_id = params["context_id"] || socket.assigns.context_id

    result =
      consume_uploaded_entries(socket, :fiche, fn %{path: path}, _entry ->
        {:ok, TeacherAssistant.Academics.FicheExtractor.extract(path)}
      end)

    case result do
      [{:ok, text}] ->
        {:ok, %{rows: rows, confidence: confidence, raw_text: raw}} =
          TeacherAssistant.Academics.FicheParser.parse(text)

        normalized = normalize_rows(rows)
        total = length(normalized)
        kept = Enum.take(normalized, @max_rows)
        capped? = total > @max_rows

        {:noreply,
         socket
         |> assign(:stage, :review)
         |> assign(:title, title)
         |> assign(:context_id, context_id)
         |> assign(:rows, kept)
         |> assign(:confidence, confidence)
         |> assign(:raw_text, raw)
         |> assign(:capped?, capped?)}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Couldn't read that PDF. Try another file, or build the plan manually.")
         )}
    end
  end

  def handle_event("add-row", _params, socket) do
    blank = %{
      module: "",
      lesson_title: "",
      planned_hours: "1",
      entry_type: :lesson,
      week_no: nil,
      sequence_no: nil
    }

    {:noreply, assign(socket, :rows, socket.assigns.rows ++ [blank])}
  end

  def handle_event("delete-row", %{"index" => index}, socket) do
    i = String.to_integer(index)
    {:noreply, assign(socket, :rows, List.delete_at(socket.assigns.rows, i))}
  end

  def handle_event("save", %{"rows" => rows_params} = params, socket) do
    ws = socket.assigns.current_scope.current_workspace
    rows = build_rows(rows_params)

    cond do
      rows == [] ->
        {:noreply,
         put_flash(socket, :error, gettext("Add at least one row with a module and lesson."))}

      true ->
        attrs = %{
          teaching_context_id: socket.assigns.context_id,
          title: title_or_default(params, socket)
        }

        case Academics.import_progression_plan(ws, attrs, rows) do
          {:ok, plan} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Plan imported."))
             |> push_navigate(to: ~p"/teacher/plans/#{plan.id}")}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Could not save the plan. Check the rows and try again.")
             )}
        end
    end
  end

  def handle_event("save", params, socket) do
    handle_event("save", Map.put(params, "rows", %{}), socket)
  end

  defp normalize_rows(rows) do
    Enum.map(rows, fn r ->
      %{
        module: r.module,
        lesson_title: r.lesson_title,
        planned_hours: Decimal.to_string(r.planned_hours),
        entry_type: r.entry_type,
        week_no: r.week_no,
        sequence_no: r.sequence_no
      }
    end)
  end

  defp build_rows(rows_params) do
    rows_params
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_k, r} -> r end)
    |> Enum.filter(fn r ->
      String.trim(r["module"] || "") != "" and String.trim(r["lesson_title"] || "") != ""
    end)
    |> Enum.map(fn r ->
      %{
        module: String.trim(r["module"]),
        lesson_title: String.trim(r["lesson_title"]),
        planned_hours: parse_decimal(r["planned_hours"]),
        entry_type: String.to_existing_atom(r["entry_type"] || "lesson"),
        week_no: parse_optional_int(r["week_no"]),
        sequence_id: blank_to_nil(r["sequence_id"])
      }
    end)
  end

  defp parse_decimal(value) do
    case value |> to_string() |> String.replace(",", ".") |> Decimal.parse() do
      {d, _} -> d
      :error -> Decimal.new("1")
    end
  end

  defp parse_optional_int(value) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp title_or_default(params, socket) do
    case String.trim(params["title"] || socket.assigns.title || "") do
      "" -> default_title(socket)
      title -> title
    end
  end

  defp default_title(socket) do
    case Enum.find(socket.assigns.contexts, &(&1.id == socket.assigns.context_id)) do
      %{subject: subject, level: level} -> "#{subject} · #{level}"
      _ -> gettext("Imported fiche")
    end
  end

  defp entry_type_options, do: TeacherAssistant.Academics.Reference.entry_types()

  defp upload_error_to_string(:too_large), do: gettext("That file is too large (max 10 MB).")
  defp upload_error_to_string(:not_accepted), do: gettext("Please choose a PDF file.")
  defp upload_error_to_string(:too_many_files), do: gettext("Upload one file at a time.")
  defp upload_error_to_string(_), do: gettext("That file could not be uploaded.")
end
