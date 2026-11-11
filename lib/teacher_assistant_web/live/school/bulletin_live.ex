defmodule TeacherAssistantWeb.School.BulletinLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.ReportCards

  def mount(%{"id" => id, "enrollment_id" => eid} = params, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         access when access != :none <- ReportCards.access(scope, cg),
         roster = Enrollment.list_roster(scope, cg, on: :all),
         %{student: student, enrollment: enrollment} <-
           Enum.find(roster, &(&1.enrollment.id == eid)) do
      year = Organization.class_year(scope, cg)
      sequences = if year, do: Organization.list_sequences(scope, year), else: []
      terms = if year, do: Organization.list_terms(scope, year), else: []

      period =
        (year && Organization.resolve_period(scope, year, params["period"])) ||
          case sequences do
            [seq | _] -> {:sequence, seq}
            [] -> nil
          end

      {:ok,
       socket
       |> assign(
         page_title: "#{student.full_name} · #{gettext("Bulletin")}",
         cg: cg,
         student: student,
         enrollment: enrollment,
         year: year,
         sequences: sequences,
         terms: terms
       )
       |> load_period(period)}
    else
      :none -> {:ok, push_navigate(socket, to: ~p"/school")}
      nil -> {:ok, push_navigate(socket, to: ~p"/school/classes/#{id}/results")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_event("select_period", %{"period" => param}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/school/classes/#{socket.assigns.cg.id}/students/#{socket.assigns.enrollment.id}/bulletin?period=#{param}"
     )}
  end

  def handle_params(%{"period" => _} = params, _uri, socket) do
    year = socket.assigns.year

    period =
      (year && Organization.resolve_period(socket.assigns.current_scope, year, params["period"])) ||
        socket.assigns.period

    {:noreply, load_period(socket, period)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # One place decides what is shown: a published snapshot, a live draft (class
  # managers only) or nothing yet (teachers before publication). The sheet itself is
  # the print document, embedded so screen and paper never drift.
  defp load_period(socket, period) do
    %{current_scope: scope, cg: cg, student: student} = socket.assigns

    {status, publication, view} =
      case period && ReportCards.view_for(scope, cg, period) do
        {:published, pub, view} -> {:published, pub, view}
        {:draft, view} -> {:draft, nil, view}
        _ -> {:not_published, nil, nil}
      end

    assign(socket,
      period: period,
      period_param: period && Organization.period_param(period),
      status: if(period, do: status, else: :draft),
      publication: publication,
      in_view?: is_nil(view) or Enum.any?(view.roster, &(&1.student.id == student.id))
    )
  end

  defp print_path(assigns),
    do:
      ~p"/school/classes/#{assigns.cg.id}/students/#{assigns.enrollment.id}/bulletin/print?period=#{assigns.period_param}"

  defp bulletins_path(%{cg: cg, period_param: nil}), do: ~p"/school/bulletins?class=#{cg.id}"

  defp bulletins_path(%{cg: cg, period_param: param}),
    do: ~p"/school/bulletins?class=#{cg.id}&period=#{param}"

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={["bulletins", "students", "classes"]}
    >
      <section id="bulletin" class="mx-auto max-w-4xl min-w-0 space-y-5">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <.breadcrumb>
            <:crumb id="bulletin-back" navigate={bulletins_path(assigns)}>
              {gettext("Bulletins de la %{class}", class: @cg.label)}
            </:crumb>
            <:crumb>{@student.full_name}</:crumb>
          </.breadcrumb>
          <div class="flex flex-wrap items-center gap-2">
            <.link
              id="bulletin-student"
              navigate={~p"/school/students/#{@student.id}"}
              class="btn btn-ghost btn-sm gap-2"
            >
              <.icon name="hero-user" class="size-4" />
              {gettext("Fiche élève")}
            </.link>
            <a
              :if={(@period && @status != :not_published) and @in_view?}
              id="bulletin-print"
              href={print_path(assigns)}
              target="_blank"
              class="btn btn-primary btn-sm gap-2"
            >
              <.icon name="hero-printer" class="size-4" />
              {gettext("Imprimer")}
            </a>
          </div>
        </div>

        <.page_header eyebrow={gettext("Bulletin de notes")} title={@student.full_name}>
          <:actions>
            <form
              :if={@sequences != []}
              id="bulletin-period-form"
              phx-change="select_period"
              class="inline"
            >
              <.input
                type="select"
                id="bulletin-period-select"
                name="period"
                value={@period_param}
                options={[
                  {gettext("Séquences"),
                   for(s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", "seq:#{s.id}"})},
                  {gettext("Trimestres"),
                   for(t <- @terms, do: {gettext("Trimestre") <> " #{t.position}", "trim:#{t.id}"})},
                  {gettext("Année"), [{gettext("Année scolaire"), "annee"}]}
                ]}
              />
            </form>
          </:actions>
        </.page_header>

        <div class="flex flex-wrap items-center gap-2">
          <p :if={@year && @year.status == :closed} id="year-closed" class="badge badge-ghost gap-1">
            <.icon name="hero-lock-closed" class="size-3.5" />
            {gettext("Année %{name} · clôturée", name: @year.name)}
          </p>
          <p :if={@status == :published} id="bulletin-published" class="badge badge-success gap-1">
            <.icon name="hero-check-badge" class="size-4" />
            {gettext("Publié le %{date}",
              date: Calendar.strftime(ReportCards.published_on(@publication), "%d/%m/%Y")
            )}
          </p>
        </div>

        <div :if={@status == :not_published} id="bulletin-not-published">
          <.empty_state
            icon="hero-lock-closed"
            title={gettext("Pas encore publiés")}
            message={gettext("Les bulletins de cette période n'ont pas encore été publiés.")}
          />
        </div>

        <div :if={@status != :not_published and not @in_view?} id="bulletin-absent">
          <.empty_state
            icon="hero-user-minus"
            title={gettext("Absent des bulletins publiés")}
            message={gettext("Absent des bulletins publiés de cette période.")}
          />
        </div>

        <.empty_state
          :if={is_nil(@period)}
          icon="hero-document-text"
          title={gettext("Aucune donnée")}
          message={gettext("No marks for this séquence yet.")}
        />

        <%!-- An A4 sheet (794 px); on a phone it scrolls inside its own card. --%>
        <div
          :if={(@period && @status != :not_published) and @in_view?}
          id="bulletin-sheet-frame"
          class="ta-panel w-full overflow-x-auto contain-inline-size !p-2"
        >
          <iframe
            id="bulletin-sheet"
            src={print_path(assigns)}
            title={gettext("Bulletin")}
            class="block h-[1400px] w-[794px] max-w-none rounded bg-white shadow-sm"
          ></iframe>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
