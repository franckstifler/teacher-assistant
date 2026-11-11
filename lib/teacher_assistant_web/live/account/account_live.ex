defmodule TeacherAssistantWeb.Account.AccountLive do
  @moduledoc """
  « Mon compte » (spec audit follow-ups A9), in the paper auth shell like the
  password page: who the person is, their schools, the way to their password, and
  the deletion of their own account — offered only to a member of no school (a
  school's member is removed by the head first, so the school's records keep a
  name until then). An operator acting as a member never reaches it
  (`LiveUserAuth`).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Organization}
  alias TeacherAssistant.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, current_scope: scope} = socket.assigns

    {:ok,
     assign(socket,
       page_title: gettext("Mon compte"),
       display_name: User.display_name(user),
       contact: User.contact(user),
       schools: Organization.list_workspaces_for(scope)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="account" class="space-y-6">
      <div>
        <p class="ta-auth-eyebrow ta-mono">{gettext("Votre compte")}</p>
        <h1 class="ta-auth-title">{gettext("Mon compte")}</h1>
      </div>

      <div id="account-identity" class="ta-identity-card">
        <span class="ta-identity-card__avatar">{initials(@display_name)}</span>
        <div class="min-w-0">
          <p class="ta-identity-card__name truncate">{@display_name}</p>
          <p :if={@contact} class="ta-identity-card__line ta-mono truncate">{@contact}</p>
        </div>
      </div>

      <.link
        id="account-password"
        navigate={~p"/account/password"}
        class="flex min-h-12 items-center gap-3 rounded-box border border-base-300 px-4 py-2"
      >
        <.icon name="hero-key" class="size-5 flex-none" />
        <span class="flex-1">{gettext("Mot de passe")}</span>
        <.icon name="hero-chevron-right" class="size-4" />
      </.link>

      <div id="account-schools" class="space-y-2">
        <h2 class="text-sm font-semibold">{gettext("Mes écoles")}</h2>
        <p :if={@schools == []} class="text-sm text-base-content/70">
          {gettext("Vous n'êtes membre d'aucune école.")}
        </p>
        <ul :if={@schools != []} class="space-y-1 text-sm">
          <li :for={ws <- @schools} class="flex items-center gap-2">
            <.icon name="hero-building-library" class="size-4 flex-none" />
            <span class="truncate">{ws.name}</span>
          </li>
        </ul>
      </div>

      <div id="account-delete" class="space-y-2 border-t border-base-300 pt-4">
        <h2 class="text-sm font-semibold">{gettext("Supprimer mon compte")}</h2>
        <p :if={@schools != []} class="text-sm text-base-content/70">
          {gettext(
            "Tant que vous êtes membre d'une école, demandez d'abord au chef d'établissement de vous retirer de l'école ; vous pourrez ensuite supprimer votre compte ici."
          )}
        </p>
        <p :if={@schools == []} class="text-sm text-base-content/70">
          {gettext(
            "Votre nom, votre e-mail, votre téléphone et votre mot de passe sont effacés. Cette action est définitive."
          )}
        </p>
        <button
          :if={@schools == []}
          type="button"
          phx-click="delete"
          data-confirm={gettext("Supprimer définitivement votre compte ?")}
          class="btn btn-error btn-outline w-full"
        >
          {gettext("Supprimer mon compte")}
        </button>
      </div>

      <p class="text-center text-sm">
        <.link id="account-back" navigate={~p"/school"}>{gettext("Retour")}</.link>
      </p>
    </section>
    """
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Accounts.delete_own_account(socket.assigns.current_scope) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Compte supprimé."))
         |> redirect(to: ~p"/")}

      {:error, :has_membership} ->
        {:noreply,
         socket
         |> assign(:schools, Organization.list_workspaces_for(socket.assigns.current_scope))
         |> put_flash(
           :error,
           gettext("Demandez d'abord au chef d'établissement de vous retirer de l'école.")
         )}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("La suppression a échoué. Réessayez."))}
    end
  end
end
