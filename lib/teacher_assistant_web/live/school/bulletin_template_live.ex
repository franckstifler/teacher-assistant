defmodule TeacherAssistantWeb.School.BulletinTemplateLive do
  @moduledoc """
  Settings → Modèle de bulletin (spec I5, mockup `Paramètres école`): the printed
  card's language mode, the optional elements, the anglophone grade scale, and a
  preview of the official header built from the school profile.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}

  alias TeacherAssistant.Academics.{
    BulletinElement,
    BulletinLanguage,
    BulletinTemplate,
    ClassGroup
  }

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      header =
        BulletinTemplate.resolve(profile, scope.current_workspace.name, %ClassGroup{}).header

      {:ok,
       socket
       |> assign(header: header, settings_error: nil, scale_error: nil)
       |> load(scope)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket, scope) do
    settings = Assessment.bulletin_settings(scope)
    assign(socket, settings: settings, rows: Enum.map(settings.grade_scale, &row/1))
  end

  # Saving the language and elements keeps grade rows the user has not saved yet.
  defp reload(socket, scope, :settings_error),
    do: assign(socket, settings: Assessment.bulletin_settings(scope))

  defp reload(socket, scope, :scale_error), do: load(socket, scope)

  defp row(band), do: %{from: shown(band.from), letter: band.letter, remark: band.remark}

  defp shown(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)

  def handle_event("save_settings", %{"bulletin" => params}, socket) do
    params = Map.put_new(params, "elements", [])

    socket.assigns.current_scope
    |> Assessment.update_bulletin_settings(params)
    |> respond(socket, :settings_error)
  end

  def handle_event("add_grade", _params, socket),
    do: {:noreply, update(socket, :rows, &(&1 ++ [%{from: "", letter: "", remark: ""}]))}

  def handle_event("remove_grade", %{"index" => i}, socket),
    do: {:noreply, update(socket, :rows, &List.delete_at(&1, String.to_integer(i)))}

  def handle_event("save_grades", %{"grades" => grades}, socket) do
    rows =
      grades
      |> Enum.sort_by(fn {i, _} -> String.to_integer(i) end)
      |> Enum.map(fn {_, r} ->
        %{from: r["from"] || "", letter: r["letter"], remark: r["remark"]}
      end)

    socket = assign(socket, rows: rows)

    socket.assigns.current_scope
    |> Assessment.update_grade_scale(rows)
    |> respond(socket, :scale_error)
  end

  def handle_event("reset_grades", _params, socket) do
    socket.assigns.current_scope
    |> Assessment.reset_grade_scale()
    |> respond(socket, :scale_error)
  end

  defp respond(result, socket, error_key) do
    scope = socket.assigns.current_scope

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload(scope, error_key)
         |> assign(settings_error: nil, scale_error: nil)
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_number} ->
        {:noreply,
         assign(socket, [{error_key, gettext("Utilisez des nombres, par exemple 9,5.")}])}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        message = Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
        {:noreply, assign(socket, [{error_key, message}])}

      {:error, _} ->
        {:noreply, assign(socket, [{error_key, gettext("Réglage non enregistré.")}])}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="bulletin-template" class="space-y-6">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Modèle de bulletin")}
          subtitle={gettext("Ce qui apparaît sur le bulletin imprimé.")}
        />

        <.form
          for={%{}}
          as={:bulletin}
          id="settings-form"
          phx-submit="save_settings"
          class="space-y-4 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <fieldset class="space-y-2">
            <legend class="ta-eyebrow">{gettext("Langue du bulletin")}</legend>
            <label :for={lang <- BulletinLanguage.values()} class="flex items-center gap-2 text-sm">
              <input
                type="radio"
                name="bulletin[language]"
                value={lang}
                checked={@settings.language == lang}
                class="radio radio-sm"
              />
              {BulletinLanguage.label(lang)}
            </label>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Classes francophones : appréciation par matière. Classes anglophones : grade et remarque."
              )}
            </p>
          </fieldset>

          <fieldset class="space-y-2">
            <legend class="ta-eyebrow">{gettext("Éléments affichés")}</legend>
            <input type="hidden" name="bulletin[elements][]" value="" />
            <div class="grid gap-2 sm:grid-cols-2">
              <label :for={el <- BulletinElement.values()} class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  name="bulletin[elements][]"
                  value={el}
                  checked={el in @settings.elements}
                  class="checkbox checkbox-sm"
                />
                {BulletinElement.label(el)}
              </label>
            </div>
          </fieldset>
          <p :if={@settings_error} id="settings-error" class="text-sm text-error">
            {@settings_error}
          </p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>

        <.form
          for={%{}}
          as={:grades}
          id="grade-scale-form"
          phx-submit="save_grades"
          class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <h2 class="ta-eyebrow">{gettext("Grades anglophones (sur 20)")}</h2>
          <div class="grid grid-cols-[90px_70px_minmax(0,1fr)_34px] gap-2 text-xs font-semibold text-base-content/70">
            <span>{gettext("À partir de")}</span><span>{gettext("Grade")}</span>
            <span>{gettext("Remarque")}</span><span></span>
          </div>
          <div
            :for={{row, i} <- Enum.with_index(@rows)}
            class="grid grid-cols-[90px_70px_minmax(0,1fr)_34px] items-center gap-2"
          >
            <input
              name={"grades[#{i}][from]"}
              value={row.from}
              inputmode="decimal"
              class="input input-sm ta-num text-right"
            />
            <input name={"grades[#{i}][letter]"} value={row.letter} class="input input-sm" />
            <input name={"grades[#{i}][remark]"} value={row.remark} class="input input-sm w-full" />
            <button
              :if={length(@rows) > 1}
              id={"remove-grade-#{i}"}
              type="button"
              phx-click="remove_grade"
              phx-value-index={i}
              class="btn btn-ghost btn-sm btn-square"
              aria-label={gettext("Retirer")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <p :if={@scale_error} id="scale-error" class="text-sm text-error">{@scale_error}</p>
          <div class="flex flex-wrap gap-2">
            <button id="add-grade" type="button" phx-click="add_grade" class="btn btn-ghost btn-sm">
              {gettext("Ajouter une tranche")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
            <button
              :if={@settings.custom_scale?}
              id="reset-grades"
              type="button"
              phx-click="reset_grades"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Revenir au barème par défaut")}
            </button>
          </div>
        </.form>

        <div
          id="header-preview"
          class="rounded-box border border-base-300 bg-base-100 p-4 text-center text-sm"
        >
          <h2 class="ta-eyebrow mb-2">{gettext("En-tête officiel")}</h2>
          <div :for={line <- BulletinTemplate.official_lines(@header)}>{line}</div>
          <div class="mt-2 font-semibold">
            <div :for={line <- BulletinTemplate.school_lines(@header)}>{line}</div>
          </div>
          <div
            :if={Map.get(@header, :signature?) or Map.get(@header, :stamp?)}
            id="signature-preview"
            class="mt-2 flex justify-center gap-4"
          >
            <img
              :if={Map.get(@header, :stamp?)}
              src={~p"/school/logo?kind=stamp"}
              alt={gettext("Cachet")}
              class="inline-block h-10"
            />
            <img
              :if={Map.get(@header, :signature?)}
              src={~p"/school/logo?kind=signature"}
              alt={gettext("Signature du chef d'établissement")}
              class="inline-block h-10"
            />
          </div>
          <p class="mt-2 text-xs text-base-content/60">
            <.link navigate={~p"/school/settings/header"} class="link">
              {gettext("Modifiable dans « En-tête et signature ».")}
            </.link>
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
