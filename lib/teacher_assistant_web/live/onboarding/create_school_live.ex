defmodule TeacherAssistantWeb.Onboarding.CreateSchoolLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: build_form())}
  end

  def handle_event("validate", %{"school" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("create", %{"school" => p}, socket) do
    user = socket.assigns.current_scope.current_user

    # The `:create_school` action takes the flat identity fields as a nested
    # `:profile` map argument (atom keys, matching the action's `Map.take/2`)
    # and the creator as the `:owner_user_id` argument. The flat params are
    # merged back in so the form re-renders the entered values on error.
    profile = %{
      school_type: to_atom(p["school_type"]),
      subsystem: to_atom(p["subsystem"]),
      sector: to_atom(p["sector"]),
      region: to_atom(p["region"]),
      town: p["town"]
    }

    params = Map.merge(p, %{"owner_user_id" => user.id, "profile" => profile})

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, school} ->
        {:noreply, redirect(socket, to: ~p"/workspaces/select/#{school.id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(
           :error,
           gettext("Impossible de créer l'établissement — vérifiez les champs.")
         )}
    end
  end

  defp build_form do
    Workspace
    |> AshPhoenix.Form.for_create(:create_school, as: "school")
    |> to_form()
  end

  defp to_atom(nil), do: nil
  defp to_atom(""), do: nil
  defp to_atom(s), do: String.to_existing_atom(s)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="create-school" class="mx-auto max-w-md space-y-5">
        <.page_header
          eyebrow={gettext("Get started")}
          title={gettext("Create your school")}
        />

        <.form
          for={@form}
          id="create-school-form"
          phx-change="validate"
          phx-submit="create"
          class="space-y-5"
        >
          <fieldset class="ta-leaf space-y-2">
            <legend class="ta-eyebrow px-1">{gettext("School identity")}</legend>
            <.input field={@form[:name]} label={gettext("School name")} />
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
            <.input field={@form[:town]} label={gettext("Town")} />
          </fieldset>

          <.button id="create-school-submit" type="submit" class="btn btn-primary w-full gap-2">
            {gettext("Create school")}
            <.icon name="hero-arrow-right" class="size-4" />
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
