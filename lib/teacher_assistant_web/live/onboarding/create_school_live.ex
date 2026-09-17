defmodule TeacherAssistantWeb.Onboarding.CreateSchoolLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.Accounts.{SchoolTypes, SchoolSubsystems, SchoolSectors, CameroonRegions}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: :school))}
  end

  def handle_event("create", %{"school" => p}, socket) do
    attrs = %{
      name: p["name"],
      school_type: to_atom(p["school_type"]),
      subsystem: to_atom(p["subsystem"]),
      sector: to_atom(p["sector"]),
      region: to_atom(p["region"]),
      town: p["town"]
    }

    case Schools.create_school(socket.assigns.current_scope.current_user, attrs) do
      {:ok, school} ->
        {:noreply, redirect(socket, to: ~p"/workspaces/select/#{school.id}")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:form, to_form(p, as: :school))
         |> put_flash(
           :error,
           gettext("Impossible de créer l'établissement — vérifiez les champs.")
         )}
    end
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

        <.form for={@form} id="create-school-form" phx-submit="create" class="space-y-5">
          <fieldset class="ta-leaf space-y-2">
            <legend class="ta-eyebrow px-1">{gettext("School identity")}</legend>
            <.input field={@form[:name]} label={gettext("School name")} />
            <.input
              type="select"
              field={@form[:school_type]}
              label={gettext("School type")}
              options={for t <- SchoolTypes.all(), do: {SchoolTypes.label(t), t}}
              prompt={gettext("Select a school type")}
            />
            <.input
              type="select"
              field={@form[:subsystem]}
              label={gettext("Subsystem")}
              options={for s <- SchoolSubsystems.all(), do: {SchoolSubsystems.label(s), s}}
              prompt={gettext("Select a subsystem")}
            />
            <.input
              type="select"
              field={@form[:sector]}
              label={gettext("Sector")}
              options={for s <- SchoolSectors.all(), do: {SchoolSectors.label(s), s}}
              prompt={gettext("Select a sector")}
            />
            <.input
              type="select"
              field={@form[:region]}
              label={gettext("Region")}
              options={for r <- CameroonRegions.all(), do: {CameroonRegions.label(r), r}}
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
