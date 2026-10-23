defmodule TeacherAssistantWeb.School.BulletinsLive do
  @moduledoc """
  Bulletins (spec I2, Pilotage redesign §2.3): one class and one period at a time —
  a séquence (read-only), a trimester or the year. The ranked list with a side card
  for the selected student; for the Proviseur and Censeur a banner (published, or a
  draft with its pre-publish checklist and the publish button), withdrawal with a
  reason and the history. Teachers of the class see published periods only.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.ReportCards
  alias TeacherAssistant.Academics.Reference

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} = year <- scope.current_academic_year,
         [_ | _] = classes <- ReportCards.visible_classes(scope, year) do
      {:ok,
       assign(socket,
         year: year,
         classes: classes,
         periods: periods_for(scope, year),
         can_publish?: ReportCards.can_publish?(scope),
         confirm?: false,
         withdrawing?: false
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  # Séquence report cards are live figures: only the school's managers see them.
  defp periods_for(scope, year) do
    periods = ReportCards.periods(scope, year)

    if ReportCards.can_publish?(scope),
      do: periods,
      else: Enum.reject(periods, &match?({_, _, {:sequence, _}}, &1))
  end

  def handle_params(params, _uri, socket) do
    %{classes: classes, periods: periods} = socket.assigns
    cg = Enum.find(classes, &(&1.id == params["class"])) || hd(classes)

    {param, _label, period} =
      Enum.find(periods, &(elem(&1, 0) == params["period"])) || default_period(periods)

    if same_view?(socket, cg, param) do
      # Only the student changed: the class's figures are already loaded.
      rows = socket.assigns.rows
      selected = Enum.find(rows, &(&1.student.id == params["student"])) || List.first(rows)
      {:noreply, assign(socket, selected: selected)}
    else
      {:noreply,
       socket
       |> assign(
         cg: cg,
         period: period,
         period_param: param,
         confirm?: false,
         withdrawing?: false
       )
       |> load(params["student"])}
    end
  end

  defp same_view?(%{assigns: %{rows: _, cg: %{id: id}, period_param: param}}, %{id: id}, param),
    do: true

  defp same_view?(_socket, _cg, _param), do: false

  # The trimester whose séquences cover today, else the first one.
  defp default_period(periods) do
    today = Reference.today()

    Enum.find(periods, fn
      {_, _, {:trimester, term}} ->
        Enum.any?(term.sequences, fn s ->
          Date.compare(s.start_date, today) != :gt and Date.compare(today, s.end_date) != :gt
        end)

      _ ->
        false
    end) || hd(periods)
  end

  defp load(socket, student_id) do
    %{current_scope: scope, cg: cg, period: period, can_publish?: can_publish?} = socket.assigns

    {status, publication, view} =
      case ReportCards.view_for(scope, cg, period) do
        {:published, pub, view} -> {:published, pub, view}
        {:draft, view} -> {:draft, nil, view}
        _ -> {:not_published, nil, nil}
      end

    rows = rows(view)

    checks =
      checks(can_publish? and status == :draft and publishable?(period), scope, cg, period, view)

    assign(socket,
      status: status,
      publication: publication,
      view: view,
      rows: rows,
      selected: Enum.find(rows, &(&1.student.id == student_id)) || List.first(rows),
      publishable?: publishable?(period),
      checks: checks,
      rate: rate(checks, can_publish? and publishable?(period), scope, cg, period),
      council_held?: council_held?(can_publish?, scope, cg, period),
      history: if(can_publish?, do: ReportCards.history(scope, cg, period), else: [])
    )
  end

  defp publishable?({kind, _}), do: kind in [:trimester, :annual]

  defp checks(true, scope, cg, period, view),
    do: ReportCards.publish_checklist(scope, cg, period, view)

  defp checks(false, _scope, _cg, _period, _view), do: []

  # The checklist already measured the entry rate (it reads every class's marks
  # over the period); only compute it when there is no checklist.
  defp rate(checks, measure?, scope, cg, period) do
    case Enum.find(checks, &(&1.key == :notes)) do
      %{data: %{rate: rate}} -> rate
      nil -> if measure?, do: ReportCards.entry_rate(scope, cg, period)
    end
  end

  # Spec I3/I4: a trimester or the year is published only once its class council is held;
  # the last trimester carrying the year also needs the end-of-year council (bulletin v2).
  defp council_held?(true, scope, cg, {kind, _} = period) when kind in [:trimester, :annual] do
    TeacherAssistant.Councils.held?(scope, cg, period) and
      (not ReportCards.needs_annual_council?(scope, cg, period) or
         ReportCards.annual_council_held?(scope, cg))
  end

  defp council_held?(_can_publish?, _scope, _cg, _period), do: true

  defp council_path(cg, {:trimester, term}), do: ~p"/school/councils/#{cg.id}?term=#{term.id}"
  defp council_path(cg, {:annual, _year}), do: ~p"/school/councils/#{cg.id}?period=annee"

  defp rows(nil), do: []
  defp rows(%{results: nil}), do: []

  defp rows(%{results: results, roster: roster}) do
    roster
    |> Enum.flat_map(fn %{student: s, enrollment: e} ->
      case results.per_student[s.id] do
        nil -> []
        data -> [%{student: s, enrollment: e, data: data}]
      end
    end)
    |> Enum.sort_by(&{&1.data.rank || 9_999, String.downcase(&1.student.full_name)})
  end

  def handle_event("publish", _params, %{assigns: %{rate: 100}} = socket), do: publish(socket)
  def handle_event("publish", _params, socket), do: {:noreply, assign(socket, confirm?: true)}
  def handle_event("confirm_publish", _params, socket), do: publish(socket)

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, confirm?: false, withdrawing?: false)}

  def handle_event("ask_withdraw", _params, socket),
    do: {:noreply, assign(socket, withdrawing?: true)}

  def handle_event("withdraw", %{"reason" => reason}, socket) do
    case ReportCards.withdraw(socket.assigns.current_scope, socket.assigns.publication, reason) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(withdrawing?: false)
         |> load(selected_id(socket))
         |> put_flash(:info, gettext("Bulletins dépubliés."))}

      {:error, :not_published} ->
        {:noreply,
         socket
         |> assign(withdrawing?: false)
         |> load(selected_id(socket))
         |> put_flash(:error, gettext("Ces bulletins ont déjà été dépubliés."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Le motif est obligatoire."))}
    end
  end

  defp publish(socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    case ReportCards.publish(scope, cg, period) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(confirm?: false)
         |> load(selected_id(socket))
         |> put_flash(:info, gettext("Bulletins publiés."))}

      {:error, :council_not_held} ->
        {:noreply,
         socket
         |> assign(confirm?: false)
         |> load(selected_id(socket))
         |> put_flash(:error, gettext("Conseil de classe non tenu."))}

      {:error, :annual_council_not_held} ->
        {:noreply,
         socket
         |> assign(confirm?: false)
         |> load(selected_id(socket))
         |> put_flash(:error, gettext("Conseil de fin d'année non tenu."))}

      {:error, :already_published} ->
        {:noreply,
         socket
         |> assign(confirm?: false)
         |> load(selected_id(socket))
         |> put_flash(:error, gettext("Bulletins déjà publiés."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Publication impossible."))}
    end
  end

  defp selected_id(socket), do: socket.assigns.selected && socket.assigns.selected.student.id

  defp patch_to(assigns, overrides) do
    query =
      %{class: assigns.cg.id, period: assigns.period_param}
      |> Map.merge(overrides)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    ~p"/school/bulletins?#{query}"
  end

  defp period_label(periods, param),
    do: Enum.find_value(periods, fn {p, label, _} -> p == param && label end)

  defp dom_id(param), do: String.replace(param, ":", "-")
  defp date(pub), do: Calendar.strftime(ReportCards.published_on(pub), "%d/%m/%Y")

  defp date_of(%DateTime{} = at),
    do: at |> DateTime.add(3600) |> Calendar.strftime("%d/%m/%Y")

  defp who(nil), do: "—"
  defp who(user), do: User.display_name(user)

  defp fmt(nil), do: "—"

  defp fmt(%Decimal{} = d),
    do: d |> Decimal.round(2) |> Decimal.to_string() |> String.replace(".", ",")

  defp coef(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp coef(_), do: "—"

  defp low?(%Decimal{} = d), do: Decimal.lt?(d, 10)
  defp low?(_), do: false

  defp short_date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
  defp short_date(_), do: "—"

  defp ordinal(nil), do: "—"

  defp ordinal(n) when is_integer(n),
    do: ordinal(Gettext.get_locale(TeacherAssistantWeb.Gettext), n)

  @doc false
  def ordinal("en" <> _, n) do
    suffix =
      case {rem(n, 100), rem(n, 10)} do
        {r, _} when r in 11..13 -> "th"
        {_, 1} -> "st"
        {_, 2} -> "nd"
        {_, 3} -> "rd"
        _ -> "th"
      end

    "#{n}#{suffix}"
  end

  def ordinal(_fr, 1), do: "1er"
  def ordinal(_fr, n), do: "#{n}e"

  defp check_text(%{key: :notes, data: %{rate: rate, unassigned: 0}}),
    do: gettext("Notes : %{rate} saisies", rate: rate_text(rate))

  defp check_text(%{key: :notes, data: %{rate: rate, unassigned: n}}),
    do:
      ngettext(
        "Notes : %{rate} saisies (%{count} matière sans enseignant)",
        "Notes : %{rate} saisies (%{count} matières sans enseignant)",
        n,
        rate: rate_text(rate)
      )

  defp check_text(%{key: :conduct, data: %{entered: entered, effectif: effectif}}),
    do: gettext("Conduite : %{entered} / %{effectif} notes", entered: entered, effectif: effectif)

  defp check_text(%{key: :council, data: %{status: :held, date: date}}),
    do: gettext("Conseil de classe : tenu le %{date}", date: short_date(date))

  defp check_text(%{key: :council, data: %{status: :planned, date: date, time: time}}),
    do:
      gettext("Conseil de classe : prévu le %{date} à %{time}",
        date: short_date(date),
        time: Calendar.strftime(time, "%H:%M")
      )

  defp check_text(%{key: :council}), do: gettext("Conseil de classe : à planifier")

  defp check_text(%{key: :annual_council, data: %{status: :held, date: date}}),
    do: gettext("Conseil de fin d'année : tenu le %{date}", date: short_date(date))

  defp check_text(%{key: :annual_council, data: %{status: :planned, date: date, time: time}}),
    do:
      gettext("Conseil de fin d'année : prévu le %{date} à %{time}",
        date: short_date(date),
        time: Calendar.strftime(time, "%H:%M")
      )

  defp check_text(%{key: :annual_council}), do: gettext("Conseil de fin d'année : à planifier")

  defp check_text(%{key: :competences, data: %{missing: []}}),
    do: gettext("Compétences : toutes renseignées")

  defp check_text(%{key: :competences, data: %{missing: missing}}),
    do:
      ngettext(
        "Compétences : %{count} matière sans compétence",
        "Compétences : %{count} matières sans compétence",
        length(missing)
      )

  defp check_text(%{key: :page_fit, ok?: true}), do: gettext("Tient sur une page")

  defp check_text(%{key: :page_fit, data: %{subjects: n}}),
    do:
      ngettext(
        "Bulletin trop long pour une page (%{count} matière)",
        "Bulletin trop long pour une page (%{count} matières)",
        n
      )

  defp rate_text(nil), do: "—"
  defp rate_text(rate), do: "#{rate} %"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="bulletins" class="space-y-4">
        <.page_header
          eyebrow={gettext("Bulletins · %{class}", class: @cg.label)}
          title={gettext("Bulletins")}
        />

        <div id="bulletins-classes" class="flex flex-wrap gap-2">
          <.link
            :for={cg <- @classes}
            id={"class-#{cg.id}"}
            patch={patch_to(assigns, %{class: cg.id, student: nil})}
            class={[
              "btn btn-sm rounded-full transition-colors",
              if(cg.id == @cg.id, do: "btn-primary", else: "btn-ghost border-base-300")
            ]}
          >
            {cg.label}
          </.link>
        </div>

        <div role="tablist" class="tabs tabs-box max-w-full flex-nowrap overflow-x-auto">
          <.link
            :for={{param, label, _} <- @periods}
            id={"period-#{dom_id(param)}"}
            role="tab"
            patch={patch_to(assigns, %{period: param, student: nil})}
            class={["tab shrink-0", param == @period_param && "tab-active"]}
          >
            {label}
          </.link>
        </div>

        <div
          :if={@status == :published}
          id="published-banner"
          class="flex flex-wrap items-center justify-between gap-3 rounded-box border border-primary/45 bg-primary/10 p-3 text-sm"
        >
          <p>
            {gettext("Publiés le %{date} par %{who}",
              date: date(@publication),
              who: who(@publication.published_by)
            )} · {gettext("visibles par les professeurs principaux et imprimables.")}
          </p>
          <a
            id="print-class"
            href={~p"/school/classes/#{@cg.id}/bulletin/print?period=#{@period_param}"}
            target="_blank"
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer toute la classe")}
          </a>
        </div>

        <div
          :if={@status == :draft and @publishable? and @can_publish?}
          id="draft-banner"
          class="space-y-3 rounded-box border border-warning/45 bg-warning/10 p-3 text-sm"
        >
          <p class="font-semibold">
            {gettext("%{period} — pas encore publiés", period: period_label(@periods, @period_param))}
          </p>
          <ul id="publish-checks" class="space-y-1">
            <li :for={check <- @checks} data-check={check.key} class="flex items-start gap-2">
              <span class={["font-bold", if(check.ok?, do: "text-primary", else: "text-warning")]}>
                {if check.ok?, do: "✓", else: "!"}
              </span>
              <span>{check_text(check)}</span>
            </li>
          </ul>
          <div class="flex flex-wrap items-center gap-2">
            <button
              id="publish-bulletins"
              type="button"
              phx-click="publish"
              disabled={not @council_held?}
              class="btn btn-primary btn-sm"
            >
              {gettext("Publier les bulletins")}
            </button>
            <span :if={not @council_held?} id="council-not-held" class="text-sm text-warning">
              {gettext("Conseil de classe non tenu")} ·
              <.link navigate={council_path(@cg, @period)} class="link">
                {gettext("Ouvrir le conseil")}
              </.link>
            </span>
            <a
              id="print-class"
              href={~p"/school/classes/#{@cg.id}/bulletin/print?period=#{@period_param}"}
              target="_blank"
              class="btn btn-ghost btn-sm gap-1"
            >
              <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer toute la classe")}
            </a>
          </div>
        </div>

        <div :if={@status == :not_published} id="bulletins-not-published">
          <.empty_state
            icon="hero-lock-closed"
            title={gettext("Pas encore publiés")}
            message={gettext("Les bulletins de cette période n'ont pas encore été publiés.")}
          />
        </div>

        <div :if={@status != :not_published} class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="min-w-0 overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="bulletin-ranking" class="table">
              <thead>
                <tr>
                  <th>{gettext("Rang")}</th>
                  <th>{gettext("Élève")}</th>
                  <th class="text-right">{gettext("Moyenne")}</th>
                  <th>{gettext("Distinction")}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @rows}
                  id={"bulletins-row-#{row.student.id}"}
                  phx-click={JS.patch(patch_to(assigns, %{student: row.student.id}))}
                  class={[
                    "cursor-pointer transition-colors hover:bg-base-200",
                    @selected && @selected.student.id == row.student.id && "bg-primary/10"
                  ]}
                >
                  <td class="ta-num">{ordinal(row.data.rank)}</td>
                  <td>
                    <.link
                      data-role="select"
                      patch={patch_to(assigns, %{student: row.student.id})}
                      class="link link-hover"
                    >
                      {row.student.full_name}
                    </.link>
                  </td>
                  <td class={[
                    "ta-num text-right font-semibold",
                    low?(row.data.moyenne_generale) && "text-error"
                  ]}>
                    {fmt(row.data.moyenne_generale)}
                  </td>
                  <td>
                    <.distinction_badge distinction={
                      ReportCards.final_distinction(@view, row.student.id, row.data)
                    } />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <aside
            :if={@selected}
            id="student-panel"
            class="self-start space-y-3 rounded-box border border-primary/40 bg-base-100 p-4"
          >
            <h2 class="text-lg font-semibold">{@selected.student.full_name}</h2>
            <p class="ta-num text-sm text-base-content/70">
              {ordinal(@selected.data.rank)} / {@view.results.effectif} · {gettext("moyenne")} {fmt(
                @selected.data.moyenne_generale
              )}
            </p>
            <dl class="divide-y divide-base-300 text-sm">
              <div :for={s <- @selected.data.subjects} class="flex justify-between gap-2 py-1">
                <dt>{s.label} · {gettext("coef")} {coef(s.coefficient)}</dt>
                <dd class={["ta-num", low?(s.average) && "text-error"]}>{fmt(s.average)}</dd>
              </div>
            </dl>
            <.link
              navigate={
                ~p"/school/classes/#{@cg.id}/students/#{@selected.enrollment.id}/bulletin?period=#{@period_param}"
              }
              class="btn btn-ghost btn-sm"
            >
              {gettext("Ouvrir →")}
            </.link>
          </aside>
        </div>

        <div
          :if={@status == :draft and @rows != []}
          class="flex flex-wrap items-center gap-2"
        >
          <a
            :if={@publishable? and not @can_publish?}
            id="print-class"
            href={~p"/school/classes/#{@cg.id}/bulletin/print?period=#{@period_param}"}
            target="_blank"
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer toute la classe")}
          </a>
        </div>

        <div :if={@can_publish? and @status == :published and not @withdrawing?}>
          <button
            id="ask-withdraw"
            type="button"
            phx-click="ask_withdraw"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Dépublier")}
          </button>
        </div>

        <div :if={@confirm?} id="publish-confirm" class="alert alert-warning">
          <span>
            {gettext("Saisie incomplète : %{rate}. Publier quand même ?", rate: rate_text(@rate))}
          </span>
          <div class="flex gap-2">
            <button
              id="confirm-publish"
              type="button"
              phx-mounted={JS.focus()}
              phx-click="confirm_publish"
              class="btn btn-sm btn-warning"
            >
              {gettext("Publier quand même")}
            </button>
            <button type="button" phx-click="cancel" class="btn btn-sm btn-ghost">
              {gettext("Annuler")}
            </button>
          </div>
        </div>

        <.form
          :if={@withdrawing?}
          for={%{}}
          id="withdraw-form"
          phx-submit="withdraw"
          class="flex flex-wrap items-end gap-2"
        >
          <.input
            name="reason"
            value=""
            label={gettext("Motif du retrait")}
            class="input input-sm w-80"
            required
          />
          <button type="submit" class="btn btn-sm btn-error">{gettext("Dépublier")}</button>
          <button type="button" phx-click="cancel" class="btn btn-sm btn-ghost">
            {gettext("Annuler")}
          </button>
        </.form>

        <ul :if={@history != []} id="bulletins-history" class="space-y-1 text-sm text-base-content/70">
          <li :for={pub <- @history}>
            {gettext("Publié le %{date} par %{who}", date: date(pub), who: who(pub.published_by))}
            <span :if={pub.status == :withdrawn}>
              · {gettext("Retiré le %{date} par %{who} : %{reason}",
                date: date_of(pub.withdrawn_at),
                who: who(pub.withdrawn_by),
                reason: pub.withdrawal_reason
              )}
            </span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
