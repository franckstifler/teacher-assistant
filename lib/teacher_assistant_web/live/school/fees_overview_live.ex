defmodule TeacherAssistantWeb.School.FeesOverviewLive do
  @moduledoc """
  Frais (Fees 1, rule 21): the school's recovery figures, one row per class, a student
  search (name or matricule) that opens the student's fee card, and the latest receipts.
  Fees axis (Proviseur, Censeur, Intendant).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, Fees, Organization}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.{Money, ReceiptPrintHTML}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Fees.can_manage_fees?(scope),
         %{} = year <- Organization.current_academic_year(scope) do
      {:ok,
       socket
       |> assign(
         page_title: gettext("Frais"),
         year: year,
         recovery: Fees.recovery(scope, year, Reference.today()),
         recent: Fees.recent_payments(scope, year),
         q: "",
         results: []
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    results =
      if String.length(String.trim(q)) >= 2,
        do:
          Enrollment.list_school_students(socket.assigns.current_scope, socket.assigns.year,
            query: q
          ).results
          |> Enum.take(10),
        else: []

    {:noreply, assign(socket, q: q, results: results)}
  end

  defp tone(rate) when rate >= 80, do: "text-success"
  defp tone(rate) when rate >= 50, do: "text-warning"
  defp tone(_rate), do: "text-error"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="fees-overview" class="space-y-6">
        <.page_header eyebrow={gettext("Intendance")} title={gettext("Frais")} subtitle={@year.name}>
          <:actions>
            <.link navigate={~p"/school/settings/fees"} class="btn btn-ghost btn-sm">
              <.icon name="hero-cog-6-tooth" class="size-4" /> {gettext("Paramètres des frais")}
            </.link>
          </:actions>
        </.page_header>

        <% r = @recovery.school %>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <div class="ta-panel p-3 sm:p-4">
            <p class="ta-eyebrow">{gettext("Recouvrement")}</p>
            <p class={["ta-num text-2xl font-semibold sm:text-3xl", tone(r.rate)]}>{r.rate} %</p>
            <p class="text-sm text-base-content/70">{gettext("de l'année")}</p>
          </div>
          <div class="ta-panel p-3 sm:p-4">
            <p class="ta-eyebrow">{gettext("À ce jour")}</p>
            <p class={["ta-num text-2xl font-semibold sm:text-3xl", tone(r.rate_to_date)]}>
              {r.rate_to_date} %
            </p>
            <p class="text-sm text-base-content/70">{gettext("de ce qui est échu")}</p>
          </div>
          <div class="ta-panel p-3 sm:p-4">
            <p class="ta-eyebrow">{gettext("Encaissé")}</p>
            <p id="recovery-collected" class="ta-num text-lg font-semibold sm:text-xl">
              {Money.format_fcfa(r.collected)}
            </p>
            <p id="recovery-expected" class="text-sm text-base-content/70">
              {gettext("sur %{amount}", amount: Money.format_fcfa(r.expected))}
            </p>
          </div>
          <div class="ta-panel p-3 sm:p-4">
            <p class="ta-eyebrow">{gettext("En retard")}</p>
            <p class={["ta-num text-2xl font-semibold sm:text-3xl", r.behind > 0 && "text-warning"]}>
              {r.behind}
            </p>
            <p class="text-sm text-base-content/70">
              {ngettext("élève sur %{total}", "élèves sur %{total}", r.behind, total: r.students)}
            </p>
          </div>
        </div>

        <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="recovery-classes" class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Classe")}</th>
                  <th class="hidden text-right sm:table-cell">{gettext("Élèves")}</th>
                  <th class="hidden text-right sm:table-cell">{gettext("Attendu")}</th>
                  <th class="text-right">{gettext("Encaissé")}</th>
                  <th class="text-right">%</th>
                  <th class="text-right">{gettext("En retard")}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @recovery.classes}
                  id={"recovery-class-#{row.class_group.id}"}
                  class="hover:bg-base-200/60"
                >
                  <td>
                    <div class="flex items-center gap-1">
                      <.link
                        navigate={~p"/school/classes/#{row.class_group.id}/fees"}
                        class="link font-semibold"
                      >
                        {row.class_group.label}
                      </.link>
                      <.link
                        id={"control-#{row.class_group.id}"}
                        navigate={~p"/school/classes/#{row.class_group.id}/fees/control"}
                        class="btn btn-ghost btn-xs"
                        title={gettext("Contrôle des frais")}
                        aria-label={
                          gettext("Contrôle des frais — %{class}", class: row.class_group.label)
                        }
                      >
                        <.icon name="hero-clipboard-document-check" class="size-4" />
                      </.link>
                    </div>
                  </td>
                  <td class="ta-num hidden text-right sm:table-cell">{row.recovery.students}</td>
                  <td class="ta-num hidden whitespace-nowrap text-right sm:table-cell">
                    {Money.format_fcfa(row.recovery.expected)}
                  </td>
                  <td class="ta-num whitespace-nowrap text-right">
                    {Money.format_fcfa(row.recovery.collected)}
                  </td>
                  <td class={["ta-num whitespace-nowrap text-right", tone(row.recovery.rate)]}>
                    {row.recovery.rate} %
                  </td>
                  <td class="ta-num text-right">{row.recovery.behind}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <aside class="order-first space-y-4 lg:order-none">
            <div class="ta-panel space-y-2 p-4">
              <h2 class="ta-eyebrow">{gettext("Encaisser pour un élève")}</h2>
              <form id="fee-search" phx-change="search" phx-submit="search">
                <input
                  name="q"
                  value={@q}
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder={gettext("Nom ou matricule")}
                  aria-label={gettext("Nom ou matricule")}
                  class="input input-sm w-full"
                />
              </form>
              <p
                :if={@results == [] and String.length(String.trim(@q)) >= 2}
                id="search-empty"
                class="text-sm text-base-content/70"
              >
                {gettext("Aucun élève trouvé.")}
              </p>
              <ul id="search-results" class="space-y-1">
                <li :for={e <- @results}>
                  <.link
                    navigate={~p"/school/classes/#{e.class_group_id}/fees?student=#{e.id}"}
                    class="flex items-center justify-between rounded-[0.5rem] px-2 py-1.5 text-sm hover:bg-base-200"
                  >
                    <span class="font-semibold">{e.student.full_name}</span>
                    <span class="text-base-content/70">{e.class_group.label}</span>
                  </.link>
                </li>
              </ul>
            </div>

            <div id="recent-payments" class="ta-panel space-y-2 p-4">
              <h2 class="ta-eyebrow">{gettext("Derniers paiements")}</h2>
              <p :if={@recent == []} class="text-sm text-base-content/70">
                {gettext("Aucun paiement.")}
              </p>
              <div :for={p <- @recent} class="flex items-center justify-between gap-2 text-sm">
                <div>
                  <a
                    href={~p"/school/fees/receipts/#{p.id}/print"}
                    target="_blank"
                    class="link font-semibold"
                  >{p.number}</a>
                  <span :if={p.status == :cancelled} class="badge badge-error badge-xs">{gettext(
                    "Annulé"
                  )}</span>
                  <span class="block text-xs text-base-content/70">
                    {p.enrollment.student.full_name} · {p.enrollment.class_group.label} · {ReceiptPrintHTML.date(
                      p.paid_on
                    )}
                  </span>
                </div>
                <span class="ta-num">{Money.format_fcfa(p.amount)}</span>
              </div>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
