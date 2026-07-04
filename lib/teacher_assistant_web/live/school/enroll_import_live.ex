defmodule TeacherAssistantWeb.School.EnrollImportLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Permissions

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin?(scope) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         stage: :paste,
         raw: "",
         preview: [],
         result: nil
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes/#{id}")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="enroll-import" class="mx-auto max-w-2xl space-y-6">
        <.page_header
          eyebrow={gettext("École")}
          title={gettext("Import students — %{class}", class: @cg.label)}
        />

        <ul id="import-stepper" class="steps w-full text-xs">
          <li class="step step-primary">{gettext("Paste")}</li>
          <li class={["step", @stage in [:preview, :done] && "step-primary"]}>
            {gettext("Preview")}
          </li>
          <li class={["step", @stage == :done && "step-primary"]}>{gettext("Done")}</li>
        </ul>

        <div :if={@stage == :paste} class="ta-leaf space-y-3">
          <p class="text-sm text-base-content/70">
            {gettext("Paste one student per line: name;sex (m/f);matricule (optional).")}
          </p>
          <.form for={%{}} id="import-form" phx-submit="parse" class="space-y-3">
            <textarea
              name="import[raw]"
              rows="10"
              class="w-full textarea textarea-bordered ta-num"
              placeholder="Awa;f;M-1&#10;Bi;m;"
            >{@raw}</textarea>
            <.button id="import-parse" type="submit" class="btn btn-primary w-full gap-2">
              <.icon name="hero-arrow-right" class="size-4" />
              {gettext("Preview")}
            </.button>
          </.form>
        </div>

        <div :if={@stage == :preview} class="space-y-4">
          <ul id="import-preview-rows" class="space-y-2">
            <li
              :for={{row, action} <- @preview}
              class="ta-leaf flex items-center justify-between gap-3"
            >
              <span class="text-sm">
                {row.full_name}
                <span :if={row.matricule} class="text-base-content/60">— {row.matricule}</span>
              </span>
              <span class={["badge", badge_class(action)]}>{action_label(action)}</span>
            </li>
          </ul>

          <div class="flex gap-2">
            <button type="button" id="import-back" phx-click="back" class="btn btn-ghost btn-sm">
              {gettext("Back")}
            </button>
            <button
              type="button"
              id="import-confirm"
              phx-click="confirm"
              class="btn btn-primary btn-sm flex-1"
            >
              {gettext("Confirm import")}
            </button>
          </div>
        </div>

        <div :if={@stage == :done} class="ta-leaf space-y-3">
          <p class="text-sm">
            {gettext("%{created} created, %{reenrolled} réinscription(s).",
              created: @result.created,
              reenrolled: @result.reenrolled
            )}
          </p>

          <div :if={@result.conflicts != []} id="import-conflicts" class="space-y-2">
            <p class="font-semibold text-warning">{gettext("Conflicts (skipped)")}</p>
            <ul class="space-y-1">
              <li :for={c <- @result.conflicts} class="text-sm">
                {c.full_name} — {gettext("conflict")}: {conflict_reason_label(c.reason)}
              </li>
            </ul>
          </div>

          <.link navigate={~p"/school/classes/#{@cg.id}"} class="btn btn-primary w-full">
            {gettext("Back to class")}
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("parse", %{"import" => %{"raw" => raw}}, socket) do
    rows = parse_rows(raw)
    preview = Enrollments.preview_rows(socket.assigns.cg, rows)

    {:noreply,
     socket
     |> assign(:raw, raw)
     |> assign(:preview, preview)
     |> assign(:stage, :preview)}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :stage, :paste)}
  end

  def handle_event("confirm", _params, socket) do
    rows = parse_rows(socket.assigns.raw)
    result = Enrollments.import_rows(socket.assigns.cg, rows)

    {:noreply,
     socket
     |> assign(:result, result)
     |> assign(:stage, :done)}
  end

  defp parse_rows(raw) do
    raw
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.map(&String.split(&1, ";"))
    |> Enum.map(fn fields ->
      fields = fields ++ List.duplicate("", 3 - length(fields))
      [full_name, sex, matricule] = Enum.take(fields, 3)

      %{
        full_name: String.trim(full_name),
        sex: parse_sex(sex),
        matricule: blank_to_nil(String.trim(matricule)),
        repeater: false
      }
    end)
    |> Enum.reject(&(&1.full_name == ""))
  end

  defp parse_sex(v) do
    case v |> to_string() |> String.trim() |> String.downcase() do
      "m" -> :m
      _ -> :f
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp badge_class(:create), do: "badge-success"
  defp badge_class({:reenroll, _}), do: "badge-info"
  defp badge_class({:conflict, _}), do: "badge-warning"

  defp action_label(:create), do: gettext("Create")
  defp action_label({:reenroll, _}), do: gettext("Réinscription")
  defp action_label({:conflict, _}), do: gettext("conflict")

  defp conflict_reason_label(:already_enrolled), do: gettext("already enrolled this year")
  defp conflict_reason_label(:duplicate_matricule), do: gettext("duplicate matricule")
  defp conflict_reason_label(_), do: gettext("could not be enrolled")
end
