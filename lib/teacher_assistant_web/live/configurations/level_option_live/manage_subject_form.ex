defmodule TeacherAssistantWeb.Configurations.LevelOptionLive.ManageSubjectForm do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="level_option-form" phx-change="validate" phx-submit="save">
        <h3 class="text-xl font-semibold my-4">{gettext("Classes")}</h3>
        <table class="table table-sm">
          <tr>
            <th class="w-auto">{gettext("Active")}</th>
            <th>{gettext("Subject")}</th>
            <th>{gettext("Coefficient")}</th>
          </tr>
          <.inputs_for :let={subject_form} field={@form[:subjects]}>
            <input
              type="hidden"
              name={subject_form[:subject_id].name}
              value={subject_form[:subject_id].value}
            />
            <tr>
              <td>
                <input
                  class="checkbox"
                  name={"#{@form.name}[selected_subjects][]"}
                  value={subject_form[:subject_id].value}
                  type="checkbox"
                  checked={
                    is_checked?(
                      AshPhoenix.Form.value(@form, :selected_subjects),
                      subject_form[:subject_id].value
                    )
                  }
                />
              </td>
              <td>
                {@subjects[subject_form[:subject_id].value].name}
              </td>

              <td>
                <.input type="number" field={subject_form[:coefficient]} />
              </td>
            </tr>
          </.inputs_for>
        </table>

        <footer class="mt-6">
          <.button variant="primary" phx-disable-with="Saving...">
            {gettext("Save Level Option Subjects")}
          </.button>
          <.button navigate={return_path("show", @level_option)}>{gettext("Cancel")}</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    level_option =
      Ash.get!(TeacherAssistant.Academics.LevelOption, id,
        load: [:subjects],
        scope: socket.assigns.scope
      )

    subjects =
      Ash.read!(TeacherAssistant.Academics.Subject, scope: socket.assigns.scope)
      |> Enum.into(%{}, fn subject -> {subject.id, subject} end)

    form =
      AshPhoenix.Form.for_update(level_option, :manage_subjects,
        domain: TeacherAssistant.Academics,
        as: "level_option",
        scope: socket.assigns.scope,
        forms: [auto?: true],
        prepare_source: fn changeset ->
          subjects = Enum.map(level_option.subjects, & &1.subject_id)
          Ash.Changeset.set_argument(changeset, :selected_subjects, subjects)
        end,
        transform_params: fn _form, params, :validate ->
          selected_subjects = Map.get(params, "selected_subjects", [])
          subjects = Map.get(params, "subjects", %{})

          filtered_subjects =
            Enum.filter(subjects, fn
              {_key, %{"subject_id" => subject_id}} ->
                subject_id in selected_subjects

              %{"subject_id" => subject_id} ->
                subject_id in selected_subjects

              _ ->
                true
            end)

          if is_map(subjects) do
            Map.put(params, "subjects", Enum.into(filtered_subjects, %{}))
          else
            Map.put(params, "subjects", filtered_subjects)
          end
        end
      )

    existing_subjects_ids = Enum.map(level_option.subjects, & &1.subject_id)

    form =
      subjects
      |> Enum.filter(fn {id, _subject} ->
        id not in existing_subjects_ids
      end)
      |> Enum.reduce(form, fn {_id, subject}, acc ->
        AshPhoenix.Form.add_form(acc, :subjects,
          params: %{
            "subject_id" => subject.id,
            "coefficient" => subject.default_coefficient || 2
          }
        )
      end)

    {:ok,
     socket
     |> assign(:page_title, gettext("Edit Level Options Subjects"))
     |> assign(:subjects, subjects)
     |> assign(:level_option, level_option)
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("validate", %{"level_option" => level_option_params}, socket) do
    {:noreply,
     assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, level_option_params))}
  end

  def handle_event("save", %{"level_option" => level_option_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: level_option_params) do
      {:ok, level_option} ->
        socket =
          socket
          |> put_flash(:info, gettext("Subjects updated successfully"))
          |> push_navigate(to: return_path("show", level_option))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def is_checked?(option_ids, option_id) do
    # IO.inspect("CHECKING FOR.... #{option_id}")
    # IO.inspect(option_ids)

    Enum.any?(option_ids, &(&1 == option_id))
  end

  defp return_path("show", level_option), do: ~p"/configurations/levels_options/#{level_option}"
end
