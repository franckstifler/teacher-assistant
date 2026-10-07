defmodule TeacherAssistantWeb.School.OfficialHeaderLive do
  @moduledoc """
  Settings → Établissement → En-tête et signature (spec KLM6, S04): the
  bulletin's official header lines (editable, resettable), the head's
  signature and the school stamp (PNG or JPEG, 1 MB). Head only.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Academics.BulletinTemplate
  alias TeacherAssistantWeb.Authz

  @kinds [signature: :signature_path, stamp: :stamp_path]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Accounts.can_edit_official_header?(scope) do
      {:ok,
       socket
       |> allow_upload(:signature,
         accept: ~w(.png .jpg .jpeg),
         max_entries: 1,
         max_file_size: 1_000_000
       )
       |> allow_upload(:stamp,
         accept: ~w(.png .jpg .jpeg),
         max_entries: 1,
         max_file_size: 1_000_000
       )
       |> load()}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket) do
    {:ok, profile} = Accounts.fetch_school_profile(socket.assigns.current_scope)
    header = %{region: profile.region, department: profile.department}

    assign(socket,
      profile: profile,
      lines: profile.official_header_lines || BulletinTemplate.generated_official_lines(header),
      custom?: profile.official_header_lines != nil,
      error: nil
    )
  end

  def handle_event("save_lines", %{"lines" => text}, socket) do
    lines =
      text |> String.split(["\r\n", "\n"]) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    save(
      socket,
      %{official_header_lines: if(lines == [], do: nil, else: lines)},
      gettext("En-tête enregistré.")
    )
  end

  def handle_event("reset_lines", _params, socket),
    do: save(socket, %{official_header_lines: nil}, gettext("En-tête rétabli."))

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("upload", %{"kind" => kind}, socket) do
    with {kind, field} <- Enum.find(@kinds, fn {k, _} -> Atom.to_string(k) == kind end),
         [relative] <- store(socket, kind) do
      save(socket, %{field => relative}, gettext("Image enregistrée."))
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Aucune image valide à téléverser."))}
    end
  end

  def handle_event("remove", %{"kind" => kind}, socket) do
    case Enum.find(@kinds, fn {k, _} -> Atom.to_string(k) == kind end) do
      {_kind, field} -> save(socket, %{field => nil}, gettext("Image retirée."))
      nil -> {:noreply, socket}
    end
  end

  defp store(socket, kind) do
    uploads_dir = Application.fetch_env!(:teacher_assistant, :uploads_dir)
    ws = socket.assigns.current_scope.current_workspace.id

    consume_uploaded_entries(socket, kind, fn %{path: tmp}, entry ->
      relative =
        Path.join([
          "school_signatures",
          ws,
          Ash.UUIDv7.generate() <> Path.extname(entry.client_name)
        ])

      dest = Path.join(uploads_dir, relative)
      dest |> Path.dirname() |> File.mkdir_p!()
      File.cp!(tmp, dest)
      {:ok, relative}
    end)
  end

  defp upload_error(:too_large), do: gettext("Fichier trop volumineux (1 Mo au plus).")
  defp upload_error(:not_accepted), do: gettext("Format accepté : PNG ou JPEG.")
  defp upload_error(:too_many_files), do: gettext("Une seule image à la fois.")
  defp upload_error(_), do: gettext("Image refusée.")

  defp save(socket, attrs, message) do
    case Accounts.update_official_header(socket.assigns.current_scope, attrs) do
      {:ok, _} ->
        {:noreply, socket |> load() |> put_flash(:info, message)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, assign(socket, error: gettext("Au plus 6 lignes de 120 caractères."))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="official-header" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("En-tête et signature")} />

        <.form for={%{}} id="header-lines-form" phx-submit="save_lines" class="ta-panel space-y-3">
          <h2 class="ta-eyebrow">{gettext("En-tête officiel")}</h2>
          <p class="text-xs text-base-content/60">
            {gettext("Une ligne par ligne d'en-tête, 6 au plus.")}
          </p>
          <textarea name="lines" rows="6" class="textarea textarea-bordered w-full">{Enum.join(@lines, "\n")}</textarea>
          <p :if={@error} id="header-error" class="text-sm text-error">{@error}</p>
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
            <button
              :if={@custom?}
              type="button"
              id="reset-header"
              phx-click="reset_lines"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Rétablir l'en-tête par défaut")}
            </button>
          </div>
        </.form>

        <div class="grid gap-4 sm:grid-cols-2">
          <.form
            :for={
              {kind, title} <- [
                signature: gettext("Signature du chef d'établissement"),
                stamp: gettext("Cachet")
              ]
            }
            for={%{}}
            id={"#{kind}-form"}
            phx-submit="upload"
            phx-change="validate"
            class="ta-panel space-y-3"
          >
            <input type="hidden" name="kind" value={kind} />
            <h2 class="ta-eyebrow">{title}</h2>
            <img
              :if={
                Map.fetch!(
                  @profile,
                  Keyword.fetch!([signature: :signature_path, stamp: :stamp_path], kind)
                )
              }
              src={~p"/school/logo?kind=#{kind}"}
              alt={title}
              class="h-20 object-contain"
            />
            <.file_picker upload={@uploads[kind]} />
            <p
              :for={
                err <-
                  upload_errors(@uploads[kind]) ++
                    Enum.flat_map(@uploads[kind].entries, &upload_errors(@uploads[kind], &1))
              }
              class="text-sm text-error"
            >
              {upload_error(err)}
            </p>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-secondary btn-sm">{gettext("Téléverser")}</button>
              <button
                :if={
                  Map.fetch!(
                    @profile,
                    Keyword.fetch!([signature: :signature_path, stamp: :stamp_path], kind)
                  )
                }
                type="button"
                id={"remove-#{kind}"}
                phx-click="remove"
                phx-value-kind={kind}
                class="btn btn-ghost btn-sm text-error"
              >
                {gettext("Retirer")}
              </button>
            </div>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
