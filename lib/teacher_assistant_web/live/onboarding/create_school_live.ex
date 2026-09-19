defmodule TeacherAssistantWeb.Onboarding.CreateSchoolLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: build_form(socket))}
  end

  def handle_event("validate", %{"school" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("create", %{"school" => p}, socket) do
    # `owner_user_id` is a static server-controlled argument — it's set on the
    # changeset at build time via `prepare_source` (see `build_form/1`). The
    # `:profile` argument is assembled from the operator's own inputs, so it
    # can't be a build-time value; it's supplied as a submit param.
    params = Map.put(p, "profile", build_profile(p))

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, school} ->
        {:noreply, redirect(socket, to: ~p"/workspaces/select/#{school.id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, to_form(form))
         |> put_flash(
           :error,
           gettext("Impossible de créer l'établissement — vérifiez les champs.")
         )}
    end
  end

  defp build_form(socket) do
    user = socket.assigns.current_scope.current_user

    Workspace
    |> AshPhoenix.Form.for_create(:create_school,
      as: "school",
      prepare_source: fn changeset ->
        Ash.Changeset.set_argument(changeset, :owner_user_id, user.id)
      end
    )
    |> to_form()
  end

  defp build_profile(p) do
    %{
      school_type: to_atom(p["school_type"]),
      subsystem: to_atom(p["subsystem"]),
      sector: to_atom(p["sector"]),
      region: to_atom(p["region"]),
      town: p["town"]
    }
  end

  defp to_atom(nil), do: nil
  defp to_atom(""), do: nil
  defp to_atom(s), do: String.to_existing_atom(s)

  # --- summary card (aside) --------------------------------------------------

  defp build_summary(form) do
    [
      {gettext("Name"), text_value(form, :name)},
      {gettext("Type"), enum_value(form, :school_type, SchoolType)},
      {gettext("Subsystem"), enum_value(form, :subsystem, SchoolSubsystem)},
      {gettext("Sector"), enum_value(form, :sector, SchoolSector)},
      {gettext("Region"), enum_value(form, :region, CameroonRegion)},
      {gettext("Town"), text_value(form, :town)}
    ]
  end

  defp text_value(form, key) do
    case form[key].value do
      v when is_binary(v) and v != "" -> v
      _ -> "—"
    end
  end

  defp enum_value(form, key, mod) do
    case form[key].value do
      v when is_binary(v) and v != "" -> mod.label(String.to_existing_atom(v))
      _ -> "—"
    end
  end

  def render(assigns) do
    assigns = assign(assigns, :summary, build_summary(assigns.form))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="create-school" class="mx-auto max-w-4xl space-y-6">
        <.page_header
          eyebrow={gettext("Get started")}
          title={gettext("Your school's identity")}
        />

        <p class="max-w-2xl text-sm leading-relaxed text-base-content/70 text-balance">
          {gettext("These details appear on report cards and are used by our team for verification.")}
        </p>

        <.form
          for={@form}
          id="create-school-form"
          phx-change="validate"
          phx-submit="create"
          class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_18rem] lg:items-start"
        >
          <div class="ta-board space-y-5 p-5 sm:p-6">
            <fieldset class="space-y-4">
              <legend class="ta-eyebrow px-1">{gettext("School identity")}</legend>

              <.input
                field={@form[:name]}
                label={gettext("School name")}
                placeholder={gettext("Lycée bilingue de Nkolbisson")}
                class="ta-field"
                error_class="ta-field-error"
              />

              <div class="grid gap-4 sm:grid-cols-2">
                <.input
                  type="select"
                  field={@form[:school_type]}
                  label={gettext("School type")}
                  options={for t <- SchoolType.values(), do: {SchoolType.label(t), t}}
                  prompt={gettext("Select a school type")}
                />
                <.input
                  type="select"
                  field={@form[:subsystem]}
                  label={gettext("Subsystem")}
                  options={for s <- SchoolSubsystem.values(), do: {SchoolSubsystem.label(s), s}}
                  prompt={gettext("Select a subsystem")}
                />
              </div>

              <div class="grid gap-4 sm:grid-cols-2">
                <.input
                  type="select"
                  field={@form[:sector]}
                  label={gettext("Sector")}
                  options={for s <- SchoolSector.values(), do: {SchoolSector.label(s), s}}
                  prompt={gettext("Select a sector")}
                />
                <.input
                  type="select"
                  field={@form[:region]}
                  label={gettext("Region")}
                  options={for r <- CameroonRegion.values(), do: {CameroonRegion.label(r), r}}
                  prompt={gettext("Select a region")}
                />
              </div>

              <.input
                field={@form[:town]}
                label={gettext("Town / borough")}
                placeholder={gettext("Yaoundé — Nkolbisson")}
                class="ta-field"
                error_class="ta-field-error"
              />
            </fieldset>

            <div class="flex flex-wrap items-center gap-3 border-t border-base-300 pt-4">
              <.button id="create-school-submit" type="submit" class="btn btn-primary gap-2">
                {gettext("Create school")}
                <.icon name="hero-arrow-right" class="size-4" />
              </.button>
            </div>
          </div>

          <aside class="space-y-4">
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Summary")}</p>
              <dl class="mt-3 space-y-2 text-sm">
                <div :for={{label, value} <- @summary} class="flex items-center justify-between gap-3">
                  <dt class="text-base-content/70">{label}</dt>
                  <dd class="ta-num truncate font-semibold">{value}</dd>
                </div>
              </dl>
            </div>

            <div class="ta-leaf border-dashed">
              <p class="ta-eyebrow text-warning">{gettext("Good to know")}</p>
              <p class="mt-2 text-sm leading-relaxed text-base-content/70 text-balance">
                {gettext(
                  "You can set up the academic year, classes and staff invitations afterwards, from settings."
                )}
              </p>
            </div>
          </aside>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
