defmodule TeacherAssistantWeb.School.ClassesLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.SchoolTemplates
  alias TeacherAssistant.Academics.Subsystem
  alias TeacherAssistant.Accounts

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace == nil do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      profile = Accounts.fetch_school_profile(scope)

      class_streams =
        case profile do
          {:ok, p} -> SchoolTemplates.streams_for(p.school_type, p.subsystem)
          _ -> %{kind: :serie, values: [], levels: []}
        end

      {max_class_size, class_suffix} =
        case profile do
          {:ok, p} -> {p.max_class_size, p.class_suffix}
          _ -> {nil, :letters}
        end

      {:ok,
       socket
       |> assign(max_class_size: max_class_size, class_suffix: class_suffix, suggested_label: nil)
       |> assign(:can_manage_classes?, Enrollment.can_manage_classes?(scope))
       |> assign(:class_streams, class_streams)
       |> assign(
         :class_form,
         class_form(scope, scope.current_academic_year)
       )
       |> load_classes()}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-classes" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Classes")} />

        <%= if @year == nil do %>
          <.setup_gate
            icon="hero-rectangle-group"
            eyebrow={gettext("Get started")}
            title={gettext("No active academic year")}
            message={
              if @can_manage_classes?,
                do: gettext("Set up an academic year before creating classes."),
                else: gettext("L'année scolaire n'a pas encore été créée.")
            }
          >
            <:action>
              <.link
                :if={@can_manage_classes?}
                navigate={~p"/school/settings"}
                class="btn btn-primary"
              >
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
                  <th :if={@can_manage_classes?}>
                    <span class="sr-only">{gettext("Actions")}</span>
                  </th>
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
                  <td
                    id={"class-size-#{row.cg.id}"}
                    class={[
                      @max_class_size && row.effectif > @max_class_size &&
                        "text-warning font-semibold"
                    ]}
                  >
                    {if @max_class_size,
                      do: "#{row.effectif} / #{@max_class_size}",
                      else: row.effectif}
                  </td>
                  <td :if={@can_manage_classes?}>
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

          <div :if={@can_manage_classes?} class="ta-leaf space-y-3">
            <h2 class="text-sm font-semibold">{gettext("Create a class")}</h2>
            <.form
              for={@class_form}
              id="class-form"
              phx-change="validate_class"
              phx-submit="create_class"
              class="space-y-2"
            >
              <div class="grid gap-2 sm:grid-cols-4">
                <.input field={@class_form[:label]} label={gettext("Label")} />
                <.input field={@class_form[:level]} label={gettext("Level")} />
                <.input
                  field={@class_form[:serie]}
                  label={SchoolTemplates.stream_label(@class_streams.kind)}
                  list="serie-options"
                />
                <datalist id="serie-options">
                  <option :for={s <- @class_streams.values} value={s}>{s}</option>
                </datalist>
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

  def handle_event("validate_class", %{"class_group" => params}, socket) do
    {params, suggested} = suggest_label(socket, params)

    {:noreply,
     socket
     # Only a label we generated may be replaced later; a typed one is kept.
     |> assign(:suggested_label, suggested || socket.assigns.suggested_label)
     |> assign(:class_form, AshPhoenix.Form.validate(socket.assigns.class_form, params))}
  end

  def handle_event("create_class", %{"class_group" => params}, socket) do
    %{current_scope: scope} = socket.assigns

    case scope.current_academic_year do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Create an academic year first."))}

      year ->
        submit_params = drop_blank_serie(params)

        case AshPhoenix.Form.submit(socket.assigns.class_form, params: submit_params) do
          {:ok, _class_group} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Class created."))
             |> assign(:class_form, class_form(scope, year))
             |> load_classes()}

          {:error, form} ->
            if Authz.forbidden_form?(form),
              do: {:noreply, Authz.put_not_allowed(socket)},
              else: {:noreply, assign(socket, :class_form, form)}
        end
    end
  end

  def handle_event("delete_class", %{"id" => id}, socket) do
    %{current_scope: scope} = socket.assigns

    with %{cg: cg} <- Enum.find(socket.assigns.classes, &(&1.cg.id == id)),
         :ok <- Enrollment.delete_class_group(scope, cg) do
      {:noreply, socket |> put_flash(:info, gettext("Class deleted.")) |> load_classes()}
    else
      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

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
        scope
        |> Enrollment.list_class_groups(year, load: [:enrollment_count])
        |> Enum.map(&%{cg: &1, effectif: &1.enrollment_count})
      else
        []
      end

    assign(socket, classes: classes, year: year)
  end

  # Spec KLM5: a blank (or still-suggested) label follows the level and the school's rule.
  defp suggest_label(socket, %{"level" => level} = params) when level not in [nil, ""] do
    if params["label"] in [nil, "", socket.assigns[:suggested_label]] do
      base = Enum.join(Enum.reject([level, params["serie"]], &(&1 in [nil, ""])), " ")
      labels = Enum.map(socket.assigns.classes, & &1.cg.label)
      label = SchoolTemplates.next_class_label(base, labels, socket.assigns.class_suffix)
      {Map.put(params, "label", label), label}
    else
      {params, nil}
    end
  end

  defp suggest_label(_socket, params), do: {params, nil}

  # `workspace_id` and `academic_year_id` are server-controlled (never user
  # input), so they're set on the changeset at build time via `prepare_source`
  # — not merged into the submitted params at submit time. `academic_year_id`
  # is a *live* value (the active year can be created after this form is
  # first built), so callers must rebuild the form — via this helper — on
  # mount and again after any change to `year` (currently: after a
  # successful class creation).
  defp class_form(scope, year) do
    ClassGroup
    |> AshPhoenix.Form.for_create(:create,
      as: "class_group",
      scope: scope,
      prepare_source: fn changeset ->
        Ash.Changeset.change_attribute(changeset, :academic_year_id, year && year.id)
      end
    )
    |> to_form()
  end

  # `ClassGroup.serie` is a nullable string; an empty selection stays `nil`
  # (mirrors the previous `presence/1` helper) rather than being stored as "".
  defp drop_blank_serie(%{"serie" => serie} = params) when serie in ["", nil],
    do: Map.delete(params, "serie")

  defp drop_blank_serie(params), do: params
end
