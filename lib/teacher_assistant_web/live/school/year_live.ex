defmodule TeacherAssistantWeb.School.YearLive do
  @moduledoc """
  Spec KLM9 (rule 12): one school year's classes, each linking to its results and its
  printed bulletins — read only when the year is closed. Proviseur and Censeur.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, Organization}

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with true <- Organization.can_manage_calendar?(scope),
         {:ok, year} <- Organization.get_academic_year(scope, id) do
      {:ok, assign(socket, year: year, classes: Enrollment.list_class_groups(scope, year))}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="past-year" class="mx-auto flex w-full max-w-3xl flex-col gap-4">
        <.back_header
          back={~p"/school/settings/year"}
          back_label={gettext("Année scolaire et calendrier")}
          title={@year.name}
          subtitle={
            if @year.status == :closed,
              do: gettext("Année clôturée · lecture seule"),
              else: gettext("Année en cours")
          }
        />
        <div class="ta-panel flex flex-col !p-0">
          <p :if={@classes == []} id="past-year-empty" class="p-4 text-sm text-base-content/70">
            {gettext("Aucune classe cette année-là.")}
          </p>
          <div
            :for={cg <- @classes}
            id={"past-class-#{cg.id}"}
            class="flex flex-wrap items-center justify-between gap-2 border-b border-base-300 px-4 py-2.5 last:border-0"
          >
            <span class="font-semibold">{cg.label}</span>
            <span class="flex gap-4 text-sm">
              <.link navigate={~p"/school/classes/#{cg.id}/results"} class="link link-primary">
                {gettext("Résultats")}
              </.link>
              <.link
                href={~p"/school/classes/#{cg.id}/bulletin/print?period=annee"}
                class="link link-primary"
              >
                {gettext("Bulletins de l'année")}
              </.link>
            </span>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
