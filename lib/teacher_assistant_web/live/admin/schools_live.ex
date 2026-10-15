defmodule TeacherAssistantWeb.Admin.SchoolsLive do
  @moduledoc "Operator console spec §5: every school, searchable and filterable."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Modules, Operator}

  alias TeacherAssistant.Accounts.{
    CameroonRegion,
    SchoolSubsystem,
    SchoolType,
    SchoolVerificationStatus
  }

  @params ~w(q status suspended module)

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      status: parse_status(params["status"]),
      suspended: if(params["suspended"] == "1", do: true),
      module: parse_module(params["module"])
    }

    {:noreply,
     assign(socket,
       filters: filters,
       schools: Operator.list_schools(socket.assigns.current_scope, filters)
     )}
  end

  def handle_event("filter", params, socket) do
    params = params |> Map.take(@params) |> Map.reject(fn {_k, v} -> v in ["", nil] end)
    {:noreply, push_patch(socket, to: ~p"/admin/schools?#{params}")}
  end

  defp parse_status(status) do
    case SchoolVerificationStatus.match(status || "") do
      {:ok, status} -> status
      :error -> nil
    end
  end

  defp parse_module(module) do
    case Modules.Key.match(module || "") do
      {:ok, key} -> key
      :error -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-schools" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Établissements")} />

        <form
          id="schools-filter"
          phx-change="filter"
          phx-submit="filter"
          class="flex flex-wrap items-center gap-2"
        >
          <input
            type="search"
            name="q"
            value={@filters.q}
            placeholder={gettext("Nom ou ville")}
            class="input input-bordered input-sm"
            phx-debounce="300"
          />
          <select name="status" class="select select-bordered select-sm">
            <option value="">{gettext("Tous les statuts")}</option>
            <option
              :for={s <- SchoolVerificationStatus.values()}
              value={s}
              selected={@filters.status == s}
            >
              {SchoolVerificationStatus.label(s)}
            </option>
          </select>
          <label class="label cursor-pointer gap-2 text-sm">
            <input
              type="checkbox"
              name="suspended"
              value="1"
              checked={@filters.suspended}
              class="checkbox checkbox-sm"
            />
            {gettext("Suspendus")}
          </label>
          <select name="module" class="select select-bordered select-sm">
            <option value="">{gettext("Tous les modules")}</option>
            <option :for={k <- Modules.keys()} value={k} selected={@filters.module == k}>
              {Modules.label(k)}
            </option>
          </select>
        </form>

        <.empty_state
          :if={@schools == []}
          icon="hero-building-library"
          title={gettext("Aucun établissement")}
        />

        <.link
          :for={row <- @schools}
          id={"school-row-#{row.workspace.id}"}
          navigate={~p"/admin/schools/#{row.workspace.id}"}
          class="ta-leaf block space-y-1 p-4"
        >
          <span class="flex flex-wrap items-center gap-2">
            <span class="font-semibold">{row.workspace.name}</span>
            <span class="badge badge-sm">
              {SchoolVerificationStatus.label(row.profile.verification_status)}
            </span>
            <span :if={row.workspace.suspended_at} class="badge badge-error badge-sm">
              {gettext("Suspendu")}
            </span>
          </span>
          <span class="block text-sm text-base-content/70">
            {SchoolType.label(row.profile.school_type)} · {SchoolSubsystem.label(
              row.profile.subsystem
            )} · {CameroonRegion.label(row.profile.region)} · {row.profile.town}
          </span>
          <span :if={row.owner} class="block text-sm text-base-content/70">
            {Accounts.User.contact(row.owner)}
          </span>
          <span class="flex flex-wrap gap-1">
            <span :for={k <- row.workspace.modules} class="badge badge-outline badge-xs">
              {Modules.label(k)}
            </span>
          </span>
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
