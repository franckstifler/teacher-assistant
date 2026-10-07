defmodule TeacherAssistantWeb.School.BulletinsLive do
  @moduledoc """
  Bulletins (spec I2, mockup Censeur → "Bulletins"): one class and one period
  (a trimester or the year) at a time — the ranked list, a side panel with the
  selected student's report card in short, print buttons, and for the Proviseur and
  Censeur the mark-entry rate, publishing (with a confirmation below 100 %),
  withdrawal with a reason and the history. Teachers of the class see published
  periods only, read-only.
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
         periods: ReportCards.periods(scope, year),
         can_publish?: ReportCards.can_publish?(scope),
         confirm?: false,
         withdrawing?: false
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    %{classes: classes, periods: periods} = socket.assigns
    cg = Enum.find(classes, &(&1.id == params["class"])) || hd(classes)

    {param, _label, period} =
      Enum.find(periods, &(elem(&1, 0) == params["period"])) || default_period(periods)

    {:noreply,
     socket
     |> assign(cg: cg, period: period, period_param: param, confirm?: false, withdrawing?: false)
     |> load(params["student"])}
  end

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

    assign(socket,
      status: status,
      publication: publication,
      view: view,
      rows: rows,
      selected: Enum.find(rows, &(&1.student.id == student_id)) || List.first(rows),
      rate: if(can_publish?, do: ReportCards.entry_rate(scope, cg, period)),
      council_held?: council_held?(can_publish?, scope, cg, period),
      history: if(can_publish?, do: ReportCards.history(scope, cg, period), else: [])
    )
  end

  # Spec I3/I4: a trimester or the year is published only once its class council is held.
  defp council_held?(true, scope, cg, {kind, _} = period) when kind in [:trimester, :annual],
    do: TeacherAssistant.Councils.held?(scope, cg, period)

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

  defp print_one(assigns, row),
    do:
      ~p"/school/classes/#{assigns.cg.id}/students/#{row.enrollment.id}/bulletin/print?period=#{assigns.period_param}"

  defp period_label(periods, param),
    do: Enum.find_value(periods, fn {p, label, _} -> p == param && label end)

  defp dom_id(param), do: String.replace(param, ":", "-")
  defp date(pub), do: Calendar.strftime(ReportCards.published_on(pub), "%d/%m/%Y")

  defp date_of(%DateTime{} = at),
    do: at |> DateTime.add(3600) |> Calendar.strftime("%d/%m/%Y")

  defp who(nil), do: "—"
  defp who(user), do: User.display_name(user)

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp coef(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp coef(_), do: "—"

  defp hours(nil), do: "—"
  defp hours(c), do: c.justified_hours |> Decimal.add(c.unjustified_hours) |> fmt()

  defp rate_text(nil), do: "—"
  defp rate_text(rate), do: "#{rate} %"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="bulletins" class="space-y-4">
        <.page_header
          eyebrow={
            if @can_publish?,
              do: gettext("Censorat · bulletins"),
              else: gettext("Bulletins · lecture seule")
          }
          title={gettext("Bulletins · %{class}", class: @cg.label)}
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

        <div role="tablist" class="tabs tabs-box w-fit">
          <.link
            :for={{param, label, _} <- @periods}
            id={"period-#{dom_id(param)}"}
            role="tab"
            patch={patch_to(assigns, %{period: param})}
            class={["tab", param == @period_param && "tab-active"]}
          >
            {label}
          </.link>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <span
            id="bulletins-status"
            class={["badge", if(@status == :published, do: "badge-success", else: "badge-warning")]}
          >
            {if @status == :published,
              do:
                gettext("Publié le %{date} par %{who}",
                  date: date(@publication),
                  who: who(@publication.published_by)
                ),
              else: gettext("Brouillon")}
          </span>
          <span :if={@can_publish?} id="bulletins-rate" class="ta-num text-sm text-base-content/70">
            {gettext("Saisie des notes : %{rate}", rate: rate_text(@rate))}
          </span>
        </div>

        <div :if={@status == :not_published} id="bulletins-not-published">
          <.empty_state
            icon="hero-lock-closed"
            title={gettext("Pas encore publiés")}
            message={gettext("Les bulletins de cette période n'ont pas encore été publiés.")}
          />
        </div>

        <div
          :if={@status != :not_published}
          class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]"
        >
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="bulletins-table" class="table">
              <thead>
                <tr>
                  <th>{gettext("Rang")}</th>
                  <th>{gettext("Élève")}</th>
                  <th class="text-right">{gettext("Moy. gén.")}</th>
                  <th>{gettext("Appréciation")}</th>
                  <th>{gettext("Distinction")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @rows}
                  id={"bulletins-row-#{row.student.id}"}
                  class={[
                    "transition-colors",
                    @selected && @selected.student.id == row.student.id && "bg-primary/10"
                  ]}
                >
                  <td class="ta-num">{row.data.rank || "—"}</td>
                  <td>
                    <.link
                      data-role="select"
                      patch={patch_to(assigns, %{student: row.student.id})}
                      class="link link-hover"
                    >
                      {row.student.full_name}
                    </.link>
                  </td>
                  <td class="ta-num text-right font-semibold">
                    {fmt(row.data.moyenne_generale)}
                  </td>
                  <td><.mention_badge :if={row.data.mention} mention={row.data.mention} /></td>
                  <td>
                    <.distinction_badge distinction={
                      ReportCards.final_distinction(@view, row.student.id, row.data)
                    } />
                  </td>
                  <td>
                    <a
                      id={"print-#{row.student.id}"}
                      href={print_one(assigns, row)}
                      target="_blank"
                      class="btn btn-ghost btn-xs"
                      aria-label={gettext("Imprimer")}
                    >
                      <.icon name="hero-printer" class="size-4" />
                    </a>
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
            <p class="ta-eyebrow">
              {gettext("Bulletin")} · {period_label(@periods, @period_param)} · {@cg.label}
            </p>
            <h2 class="text-lg font-semibold">{@selected.student.full_name}</h2>
            <dl class="divide-y divide-base-300 text-sm">
              <div :for={s <- @selected.data.subjects} class="flex justify-between gap-2 py-1">
                <dt>{s.label} · {gettext("coef")} {coef(s.coefficient)}</dt>
                <dd class="ta-num">{fmt(s.average)}</dd>
              </div>
              <div class="flex justify-between py-1 font-semibold">
                <dt>{gettext("Moyenne générale")}</dt>
                <dd class="ta-num">{fmt(@selected.data.moyenne_generale)}</dd>
              </div>
              <div class="flex justify-between py-1">
                <dt>{gettext("Rang")}</dt>
                <dd class="ta-num">{@selected.data.rank || "—"} / {@view.results.effectif}</dd>
              </div>
              <div class="flex justify-between py-1">
                <dt>{gettext("Absences")}</dt>
                <dd class="ta-num">
                  {hours(@view.conduct[@selected.enrollment.id])} {gettext("h")}
                </dd>
              </div>
            </dl>
            <div class="flex flex-wrap gap-2">
              <.mention_badge :if={@selected.data.mention} mention={@selected.data.mention} />
              <.distinction_badge distinction={
                ReportCards.final_distinction(@view, @selected.student.id, @selected.data)
              } />
            </div>
            <div class="flex flex-wrap gap-2">
              <.link
                navigate={
                  ~p"/school/classes/#{@cg.id}/students/#{@selected.enrollment.id}/bulletin?period=#{@period_param}"
                }
                class="btn btn-ghost btn-sm"
              >
                {gettext("Ouvrir le bulletin")}
              </.link>
              <a
                href={print_one(assigns, @selected)}
                target="_blank"
                class="btn btn-ghost btn-sm gap-1"
              >
                <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer")}
              </a>
            </div>
          </aside>
        </div>

        <div :if={@status != :not_published} class="flex flex-wrap items-center gap-2">
          <a
            id="print-class"
            href={~p"/school/classes/#{@cg.id}/bulletin/print?period=#{@period_param}"}
            target="_blank"
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer toute la classe")}
          </a>
          <button
            :if={@can_publish? and @status == :draft}
            id="publish"
            type="button"
            phx-click="publish"
            disabled={not @council_held?}
            class="btn btn-primary btn-sm"
          >
            {gettext("Publier les bulletins de la classe")}
          </button>
          <span
            :if={@can_publish? and @status == :draft and not @council_held?}
            id="council-not-held"
            class="text-sm text-warning"
          >
            {gettext("Conseil de classe non tenu")} ·
            <.link
              navigate={council_path(@cg, @period)}
              class="link"
            >
              {gettext("Ouvrir le conseil")}
            </.link>
          </span>
          <button
            :if={@can_publish? and @status == :published and not @withdrawing?}
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
