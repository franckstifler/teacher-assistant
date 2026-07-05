defmodule TeacherAssistantWeb.School.ClassesLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Subsystem
  alias TeacherAssistant.Accounts.Permissions

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type != :school do
      {:ok, push_navigate(socket, to: ~p"/teacher")}
    else
      {:ok,
       socket
       |> assign(:admin?, Permissions.admin?(scope))
       |> assign(
         :class_form,
         to_form(%{"label" => "", "level" => "", "serie" => ""}, as: :class_group)
       )
       |> load_classes()}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-classes" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Classes")} />

        <%= if @year == nil do %>
          <.setup_gate
            icon="hero-rectangle-group"
            eyebrow={gettext("Get started")}
            title={gettext("No active academic year")}
            message={gettext("Set up an academic year before creating classes.")}
          >
            <:action>
              <.link navigate={~p"/school/settings"} class="btn btn-primary">
                {gettext("Go to settings")}
              </.link>
            </:action>
          </.setup_gate>
        <% else %>
          <div class="overflow-x-auto">
            <table id="classes-table" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Label")}</th>
                  <th>{gettext("Level")}</th>
                  <th>{gettext("Série")}</th>
                  <th>{gettext("Subsystem")}</th>
                  <th>{gettext("Effectif")}</th>
                  <th :if={@admin?}><span class="sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @classes} id={"class-row-#{row.cg.id}"}>
                  <td>
                    <.link navigate={~p"/school/classes/#{row.cg.id}"} class="link link-hover">
                      {row.cg.label}
                    </.link>
                  </td>
                  <td>{row.cg.level}</td>
                  <td>{row.cg.serie}</td>
                  <td>{row.cg.subsystem}</td>
                  <td>{row.effectif}</td>
                  <td :if={@admin?}>
                    <button
                      id={"class-delete-#{row.cg.id}"}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="delete_class"
                      phx-value-id={row.cg.id}
                      data-confirm={gettext("Delete this class?")}
                    >
                      {gettext("Delete")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.empty_state
            :if={@classes == []}
            icon="hero-rectangle-group"
            title={gettext("No classes yet")}
          />

          <div :if={@admin?} class="ta-leaf space-y-3">
            <h2 class="text-sm font-semibold">{gettext("Create a class")}</h2>
            <.form for={@class_form} id="class-form" phx-submit="create_class" class="space-y-2">
              <div class="grid gap-2 sm:grid-cols-4">
                <.input field={@class_form[:label]} label={gettext("Label")} />
                <.input field={@class_form[:level]} label={gettext("Level")} />
                <.input field={@class_form[:serie]} label={gettext("Série (optionnel)")} />
                <.input
                  type="select"
                  field={@class_form[:subsystem]}
                  label={gettext("Subsystem")}
                  options={Enum.map(Subsystem.values(), &{to_string(&1), to_string(&1)})}
                />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Create")}</button>
            </.form>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("create_class", %{"class_group" => params}, socket) do
    %{current_scope: scope} = socket.assigns

    with true <- Permissions.admin?(scope),
         year when not is_nil(year) <- scope.current_academic_year,
         {:ok, _} <-
           Academics.create_class_group(scope.current_workspace, year, %{
             label: params["label"],
             level: params["level"],
             serie: presence(params["serie"]),
             subsystem: parse_subsystem(params["subsystem"])
           }) do
      {:noreply, socket |> put_flash(:info, gettext("Class created.")) |> load_classes()}
    else
      false -> {:noreply, socket}
      nil -> {:noreply, put_flash(socket, :error, gettext("Create an academic year first."))}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not create the class."))}
    end
  end

  def handle_event("delete_class", %{"id" => id}, socket) do
    %{current_scope: scope} = socket.assigns

    with true <- Permissions.admin?(scope),
         %{cg: cg} <- Enum.find(socket.assigns.classes, &(&1.cg.id == id)),
         :ok <- Academics.delete_class_group(cg) do
      {:noreply, socket |> put_flash(:info, gettext("Class deleted.")) |> load_classes()}
    else
      {:error, :has_data} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This class has students or teachers — remove them first.")
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_classes(socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    classes =
      if year do
        Academics.list_class_groups(scope.current_workspace, year)
        |> Enum.map(fn cg ->
          %{cg: cg, effectif: length(Academics.list_roster(cg))}
        end)
      else
        []
      end

    assign(socket, classes: classes, year: year)
  end

  defp presence(""), do: nil
  defp presence(nil), do: nil
  defp presence(v), do: v

  defp parse_subsystem(v) when v in ~w(francophone anglophone), do: String.to_existing_atom(v)
  defp parse_subsystem(_), do: :francophone
end
