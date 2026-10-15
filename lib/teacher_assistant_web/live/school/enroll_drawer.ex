defmodule TeacherAssistantWeb.School.EnrollDrawer do
  @moduledoc """
  « Inscrire un élève » (spec 2026-10-08 §4, Élèves redesign §0): a new
  student with their parent, or a former one re-enrolled, into a fixed class
  (the class page) or a class picked first (`/school/students`).

  The parent page shows it with `:if`, closes it on `close_drawer` and is told
  the outcome: `{EnrollDrawer, {:enrolled, class_group, :close | :another}}`,
  `{EnrollDrawer, {:reenrolled, class_group}}` or `{EnrollDrawer, :forbidden}`.
  """
  use TeacherAssistantWeb, :live_component

  import TeacherAssistantWeb.Drawer

  alias Phoenix.LiveView.JS
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.{GuardianRelationship, Sex}

  @doc "The flash after an enrolment, from the class's headcount after it."
  def enrolled_message(cg, capacity) do
    # Spec KLM5: over the maximum is a warning, never a block.
    if capacity.over?,
      do:
        gettext("Élève inscrit. La classe dépasse l'effectif maximum (%{max}).",
          max: capacity.max
        ),
      else:
        gettext("Élève inscrit en %{label} (%{size}).",
          label: cg.label,
          size: capacity_line(capacity)
        )
  end

  @doc "« 52 / 60 », or « 52 élèves » without a maximum."
  def capacity_line(%{count: count, max: nil}),
    do: ngettext("%{count} élève", "%{count} élèves", count)

  def capacity_line(%{count: count, max: max}), do: "#{count} / #{max}"

  # --- Lifecycle ------------------------------------------------------------------

  def mount(socket) do
    {:ok,
     assign(socket,
       mode: :new,
       enroll: %{"sex" => "f", "parent_relationship" => "mere"},
       enroll_error: nil,
       parent_matches: [],
       search_results: [],
       q: "",
       options: nil,
       class_id: nil
     )}
  end

  # `class_group` + `capacity` for a fixed class; neither for the class picker.
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:class_group] == nil and socket.assigns.options == nil,
        do: assign(socket, :options, class_options(socket.assigns.scope)),
        else: socket

    {:ok, socket}
  end

  defp class_options(scope) do
    school_max = Enrollment.school_max_size(scope)

    scope
    |> Enrollment.list_class_groups(scope.current_academic_year, load: [:enrollment_count])
    |> Enum.sort_by(&TeacherAssistant.Academics.SchoolTemplates.class_sort_key/1)
    |> Enum.map(fn cg ->
      %{cg: cg, capacity: Enrollment.capacity_of(cg.enrollment_count, cg.max_size || school_max)}
    end)
  end

  # The class the student goes into and its headcount, or nil before a pick.
  defp target(%{class_group: %{} = cg, capacity: capacity}), do: {cg, capacity}

  defp target(%{options: options, class_id: id}) do
    case Enum.find(options || [], &(&1.cg.id == id)) do
      nil -> nil
      option -> {option.cg, option.capacity}
    end
  end

  def render(assigns) do
    assigns = assign(assigns, :target, target(assigns))

    ~H"""
    <div>
      <.drawer
        id="enroll-drawer"
        eyebrow={eyebrow(@target)}
        title={gettext("Inscrire un élève")}
        on_close={JS.push("close_drawer")}
      >
        <form
          :if={@options}
          id="enroll-class-form"
          phx-change="pick_class"
          phx-target={@myself}
          class="space-y-1"
        >
          <label for="enroll-class" class="ta-eyebrow block">{gettext("Classe")}</label>
          <select id="enroll-class" name="class_id" class="select select-sm w-full">
            <option value="">{gettext("Choisir une classe")}</option>
            <option :for={o <- @options} value={o.cg.id} selected={o.cg.id == @class_id}>
              {o.cg.label} — {capacity_line(o.capacity)}
            </option>
          </select>
          <p
            :if={@target && (elem(@target, 1).near? or elem(@target, 1).over?)}
            id="enroll-class-warning"
            class="text-xs font-semibold text-warning"
          >
            {if elem(@target, 1).over?,
              do: gettext("Cette classe dépasse déjà son effectif maximum."),
              else: gettext("Cette classe est presque pleine.")}
          </p>
        </form>

        <.panel
          myself={@myself}
          enroll_error={@enroll_error}
          enroll_mode={@mode}
          enroll={@enroll}
          can_manage_guardians?={@can_manage_guardians?}
          parent_matches={@parent_matches}
          q={@q}
          search_results={@search_results}
          year_id={@scope.current_academic_year.id}
        />
        <:footer :if={@mode == :new}>
          <span
            :if={@target && elem(@target, 1).max}
            id="enroll-after"
            class={[
              "ta-num mr-auto self-center text-xs",
              if(elem(@target, 1).count + 1 > elem(@target, 1).max,
                do: "font-semibold text-warning",
                else: "text-base-content/70"
              )
            ]}
          >
            {gettext("%{count} / %{max} élèves après cet ajout",
              count: elem(@target, 1).count + 1,
              max: elem(@target, 1).max
            )}
          </span>
          <button
            type="submit"
            form="enroll-form"
            name="then"
            value="another"
            id="enroll-another"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Inscrire et en ajouter un autre")}
          </button>
          <button type="submit" form="enroll-form" id="enroll-submit" class="btn btn-primary btn-sm">
            {gettext("Inscrire")}
          </button>
        </:footer>
      </.drawer>
    </div>
    """
  end

  defp eyebrow(nil), do: nil
  defp eyebrow({cg, capacity}), do: "#{cg.label} · #{capacity_line(capacity)}"

  attr :myself, :any, required: true
  attr :enroll_error, :string
  attr :enroll_mode, :atom, required: true
  attr :enroll, :map, required: true
  attr :can_manage_guardians?, :boolean, required: true
  attr :parent_matches, :list, required: true
  attr :q, :string, required: true
  attr :search_results, :list, required: true
  attr :year_id, :string, required: true

  defp panel(assigns) do
    ~H"""
    <div :if={@enroll_error} id="enroll-error" role="alert" class="alert alert-error alert-soft">
      <.icon name="hero-exclamation-triangle" class="size-5" />
      <span>{@enroll_error}</span>
    </div>

    <div role="group" aria-label={gettext("Type d'inscription")} class="grid grid-cols-2 gap-2">
      <button
        :for={{mode, label} <- [new: gettext("Nouvel élève"), existing: gettext("Ancien élève")]}
        id={"enroll-mode-#{mode}"}
        type="button"
        phx-click="enroll_mode"
        phx-target={@myself}
        phx-value-mode={mode}
        aria-pressed={to_string(@enroll_mode == mode)}
        class={[
          "rounded-[0.5rem] border px-3 py-2 text-sm font-semibold transition-colors",
          if(@enroll_mode == mode,
            do: "border-primary bg-primary/10 text-primary",
            else: "border-base-300 text-base-content/80 hover:border-base-content/40"
          )
        ]}
      >
        {label}
      </button>
    </div>

    <form
      :if={@enroll_mode == :new}
      id="enroll-form"
      phx-change="enroll_change"
      phx-submit="enroll_new"
      phx-target={@myself}
      class="space-y-4"
    >
      <div class="space-y-1">
        <label for="enroll-full-name" class="ta-eyebrow block">{gettext("Nom et prénoms")}</label>
        <.input
          id="enroll-full-name"
          type="text"
          name="enroll[full_name]"
          value={@enroll["full_name"]}
          placeholder={gettext("NOM Prénoms")}
          class="input input-sm w-full"
        />
      </div>
      <fieldset>
        <legend class="ta-eyebrow mb-2">{gettext("Sexe")}</legend>
        <div class="flex gap-2">
          <.chip_radio
            :for={sex <- [:f, :m]}
            id={"enroll-sex-#{sex}"}
            name="enroll[sex]"
            value={to_string(sex)}
            checked={@enroll["sex"] == to_string(sex)}
          >
            {Sex.label(sex)}
          </.chip_radio>
        </div>
      </fieldset>
      <div class="grid gap-3 sm:grid-cols-2">
        <div class="space-y-1">
          <label for="enroll-birth-date" class="ta-eyebrow block">
            {gettext("Date de naissance")}
          </label>
          <.input
            id="enroll-birth-date"
            type="date"
            name="enroll[birth_date]"
            value={@enroll["birth_date"]}
            class="input input-sm w-full"
          />
        </div>
        <div class="space-y-1">
          <label for="enroll-birth-place" class="ta-eyebrow block">
            {gettext("Lieu de naissance")}
          </label>
          <.input
            id="enroll-birth-place"
            type="text"
            name="enroll[birth_place]"
            value={@enroll["birth_place"]}
            class="input input-sm w-full"
          />
        </div>
      </div>
      <div class="space-y-1">
        <label for="enroll-matricule" class="ta-eyebrow block">
          {gettext("Matricule (facultatif)")}
        </label>
        <.input
          id="enroll-matricule"
          type="text"
          name="enroll[matricule]"
          value={@enroll["matricule"]}
          class="input input-sm w-full"
        />
      </div>
      <.input
        id="enroll-repeater"
        type="checkbox"
        name="enroll[repeater]"
        checked={@enroll["repeater"] == "true"}
        label={gettext("Redoublant dans ce niveau")}
      />

      <fieldset
        :if={@can_manage_guardians?}
        id="enroll-parent"
        class="space-y-3 rounded-[0.6rem] border border-base-300 p-3"
      >
        <legend class="ta-eyebrow px-1">{gettext("Parent ou tuteur · recommandé")}</legend>
        <.input
          id="enroll-parent-phone"
          type="tel"
          inputmode="tel"
          name="enroll[parent_phone]"
          value={@enroll["parent_phone"]}
          phx-debounce="300"
          placeholder={gettext("Téléphone : 6XX XX XX XX")}
          aria-label={gettext("Téléphone du parent")}
          class="input input-sm w-full"
        />
        <div :if={@parent_matches != []} id="enroll-parent-matches" class="space-y-2">
          <label
            :for={g <- @parent_matches}
            class="flex cursor-pointer items-start gap-2 rounded-[0.5rem] bg-primary/10 p-2 text-sm"
          >
            <input
              type="radio"
              name="enroll[parent_id]"
              value={g.id}
              checked={@enroll["parent_id"] == g.id or length(@parent_matches) == 1}
              class="radio radio-sm mt-0.5"
            />
            <span>
              {ngettext(
                "Déjà enregistré : %{name} (%{relationship} de %{count} élève)",
                "Déjà enregistré : %{name} (%{relationship} de %{count} élèves)",
                g.student_count,
                name: g.full_name,
                relationship: GuardianRelationship.label(g.relationship)
              )}
              <span class="block text-xs text-base-content/70">
                {gettext("Sera lié automatiquement.")}
              </span>
            </span>
          </label>
        </div>
        <div :if={@parent_matches == []} class="grid gap-2 sm:grid-cols-[1fr_auto]">
          <.input
            id="enroll-parent-name"
            type="text"
            name="enroll[parent_name]"
            value={@enroll["parent_name"]}
            placeholder={gettext("Nom du parent")}
            aria-label={gettext("Nom du parent")}
            class="input input-sm w-full"
          />
          <.input
            id="enroll-parent-relationship"
            type="select"
            name="enroll[parent_relationship]"
            value={@enroll["parent_relationship"]}
            options={Enum.map(GuardianRelationship.values(), &{GuardianRelationship.label(&1), &1})}
            aria-label={gettext("Lien")}
            class="select select-sm"
          />
        </div>
      </fieldset>
    </form>

    <div :if={@enroll_mode == :existing} class="space-y-3">
      <form id="enroll-search-form" phx-change="search" phx-target={@myself}>
        <.input
          type="search"
          id="enroll-search"
          name="q"
          value={@q}
          phx-debounce="300"
          placeholder={gettext("Nom ou matricule d'un ancien élève")}
          aria-label={gettext("Rechercher un ancien élève")}
          class="input input-sm w-full"
        />
      </form>
      <ul id="search-results" class="space-y-2">
        <li
          :for={student <- @search_results}
          class="flex items-center justify-between gap-3 rounded-[0.5rem] border border-base-300 px-3 py-2"
        >
          <span class="min-w-0 text-sm">
            <span class="block font-semibold">{student.full_name}</span>
            <span class="ta-num block text-xs text-base-content/70">
              {Enum.join(Enum.reject([student.matricule, last_class(student)], &is_nil/1), " · ")}
            </span>
          </span>
          <button
            :if={!enrolled_in?(student, @year_id)}
            id={"search-enroll-#{student.id}"}
            type="button"
            class="btn btn-primary btn-xs"
            phx-click="enroll_existing"
            phx-target={@myself}
            phx-value-student-id={student.id}
          >
            {gettext("Réinscrire")}
          </button>
          <button
            :if={enrolled_in?(student, @year_id)}
            id={"search-enrolled-#{student.id}"}
            type="button"
            class="btn btn-xs"
            disabled
          >
            {gettext("Déjà inscrit cette année")}
          </button>
        </li>
      </ul>
      <p :if={@q != "" and @search_results == []} class="text-sm text-base-content/70">
        {gettext("Aucun élève trouvé.")}
      </p>
    </div>
    """
  end

  # --- Events -------------------------------------------------------------------

  def handle_event("pick_class", %{"class_id" => id}, socket),
    do: {:noreply, assign(socket, class_id: id, enroll_error: nil)}

  def handle_event("enroll_mode", %{"mode" => mode}, socket) do
    mode = if mode == "existing", do: :existing, else: :new
    {:noreply, assign(socket, mode: mode, enroll_error: nil)}
  end

  def handle_event("enroll_change", %{"enroll" => params}, socket) do
    phone = params["parent_phone"] || ""

    matches =
      cond do
        not socket.assigns.can_manage_guardians? -> []
        phone == (socket.assigns.enroll["parent_phone"] || "") -> socket.assigns.parent_matches
        true -> Enrollment.find_guardians_by_phone(socket.assigns.scope, phone)
      end

    {:noreply, assign(socket, enroll: params, parent_matches: matches)}
  end

  def handle_event("enroll_new", %{"enroll" => params} = all, socket) do
    socket = assign(socket, :enroll, params)
    then = if all["then"] == "another", do: :another, else: :close

    with {:ok, {cg, _capacity}} <- picked(socket.assigns),
         {:ok, attrs} <- enroll_attrs(params, socket.assigns),
         {:ok, _} <- Enrollment.enroll_new(socket.assigns.scope, cg, attrs) do
      send(self(), {__MODULE__, {:enrolled, cg, then}})
      {:noreply, if(then == :another, do: reset(socket), else: socket)}
    else
      {:error, :duplicate_matricule} ->
        {:noreply,
         assign(
           socket,
           :enroll_error,
           gettext("This matricule already belongs to another student.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        send(self(), {__MODULE__, :forbidden})
        {:noreply, socket}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, :enroll_error, message)}

      {:error, _} ->
        {:noreply, assign(socket, :enroll_error, gettext("Could not enroll the student."))}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     assign(socket, search_results: Enrollment.search_students(socket.assigns.scope, q), q: q)}
  end

  def handle_event("enroll_existing", %{"student-id" => sid}, socket) do
    with %{} = student <- Enum.find(socket.assigns.search_results, &(&1.id == sid)),
         {:ok, {cg, _capacity}} <- picked(socket.assigns) do
      case Enrollment.enroll_existing(socket.assigns.scope, cg, student) do
        {:ok, _} ->
          send(self(), {__MODULE__, {:reenrolled, cg}})
          {:noreply, socket}

        {:error, :already_enrolled} ->
          {:noreply,
           assign(socket, :enroll_error, gettext("This student is already enrolled this year."))}

        {:error, %Ash.Error.Forbidden{}} ->
          send(self(), {__MODULE__, :forbidden})
          {:noreply, socket}

        {:error, _} ->
          {:noreply, assign(socket, :enroll_error, gettext("Could not enroll the student."))}
      end
    else
      {:error, message} -> {:noreply, assign(socket, :enroll_error, message)}
      _ -> {:noreply, socket}
    end
  end

  defp picked(assigns) do
    case target(assigns) do
      nil -> {:error, gettext("Choisissez une classe.")}
      target -> {:ok, target}
    end
  end

  # Ready for the next student; the picker's headcounts include the one just added.
  defp reset(socket) do
    options = socket.assigns.options && class_options(socket.assigns.scope)

    assign(socket,
      options: options,
      enroll: %{"sex" => "f", "parent_relationship" => "mere"},
      enroll_error: nil,
      parent_matches: [],
      search_results: [],
      q: ""
    )
  end

  # The form's params as `Enrollment.enroll_new/3` attributes, or a message.
  defp enroll_attrs(params, assigns) do
    name = String.trim(params["full_name"] || "")

    with :ok <- required_name(name),
         {:ok, birth_date} <- parse_birth_date(params["birth_date"]),
         {:ok, guardian} <- guardian_attrs(params, assigns) do
      {:ok,
       %{
         full_name: name,
         sex: if(params["sex"] == "m", do: :m, else: :f),
         birth_date: birth_date,
         birth_place: presence(params["birth_place"]),
         matricule: presence(params["matricule"]),
         repeater: params["repeater"] == "true",
         guardian: guardian
       }}
    end
  end

  defp required_name(""), do: {:error, gettext("Le nom de l'élève est obligatoire.")}
  defp required_name(_name), do: :ok

  defp parse_birth_date(value) when value in [nil, ""], do: {:ok, nil}

  defp parse_birth_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, gettext("Date de naissance invalide.")}
    end
  end

  defp guardian_attrs(_params, %{can_manage_guardians?: false}), do: {:ok, nil}

  defp guardian_attrs(params, %{parent_matches: matches}) do
    phone = String.trim(params["parent_phone"] || "")
    name = String.trim(params["parent_name"] || "")
    picked = Enum.find(matches, &(&1.id == params["parent_id"])) || single(matches)

    cond do
      picked ->
        {:ok, %{guardian_id: picked.id}}

      matches != [] ->
        {:error, gettext("Choisissez le parent parmi ceux déjà enregistrés.")}

      phone == "" and name == "" ->
        {:ok, nil}

      not TeacherAssistant.Academics.Guardian.Phone.valid?(phone) ->
        {:error, gettext("Numéro de téléphone du parent invalide.")}

      name == "" ->
        {:error, gettext("Indiquez le nom du parent.")}

      true ->
        {:ok,
         %{
           full_name: name,
           phone: phone,
           relationship: relationship(params["parent_relationship"])
         }}
    end
  end

  # « 6ème A · 2024-2025 », the student's most recent class.
  defp last_class(%{enrollments: []}), do: nil

  defp last_class(%{enrollments: enrollments}) do
    e = Enum.max_by(enrollments, & &1.academic_year.start_date, Date)
    "#{e.class_group.label} · #{e.academic_year.name}"
  end

  defp enrolled_in?(%{enrollments: enrollments}, year_id),
    do: Enum.any?(enrollments, &(&1.academic_year_id == year_id))

  defp single([one]), do: one
  defp single(_), do: nil

  defp relationship(value),
    do: Enum.find(GuardianRelationship.values(), :autre, &(to_string(&1) == value))

  defp presence(nil), do: nil

  defp presence(v) do
    case String.trim(v) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
