defmodule TeacherAssistantWeb.Account.PasswordLive do
  @moduledoc """
  Forced first-sign-in password change for school-created accounts (spec
  2026-10-07). Rendered in the paper auth shell (`Layouts.auth`, set by the
  `:account` live_session); `LiveUserAuth` sends every other signed-in page here
  while `must_change_password` is true.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User

  @min_length 8

  @impl true
  def mount(
        _params,
        _session,
        %{assigns: %{current_user: %{must_change_password: false}}} = socket
      ) do
    {:ok, redirect(socket, to: ~p"/school")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:auth_screen, :own_password)
     |> assign(:page_title, gettext("Choisissez votre mot de passe"))
     |> assign(:display_name, User.display_name(user))
     |> assign(:initials, initials(User.display_name(user)))
     |> assign(:identity_line, identity_line(user, socket.assigns.current_scope))
     |> assign(:form, password_form(user))
     |> assign_checks(%{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="own-password" class="space-y-6">
      <div id="own-password-identity" class="ta-identity-card">
        <span class="ta-identity-card__avatar">{@initials}</span>
        <div class="min-w-0">
          <p class="ta-identity-card__name truncate">{@display_name}</p>
          <p :if={@identity_line} class="ta-identity-card__line ta-mono truncate">
            {@identity_line}
          </p>
        </div>
      </div>

      <div>
        <p class="ta-auth-eyebrow ta-mono">{gettext("Votre compte · étape unique")}</p>
        <h1 class="ta-auth-title">{gettext("Choisissez votre mot de passe")}</h1>
        <p class="ta-auth-sub">
          {gettext(
            "Votre établissement vous a donné un mot de passe temporaire. Choisissez-en un que vous seul·e connaissez."
          )}
        </p>
      </div>

      <.form for={@form} id="own-password-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:password]}
          type="password"
          label={gettext("Nouveau mot de passe")}
          autocomplete="new-password"
          class="w-full"
          error_class="ta-field-input-error"
          phx-debounce="200"
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label={gettext("Confirmer le mot de passe")}
          autocomplete="new-password"
          class="w-full"
          error_class="ta-field-input-error"
          phx-debounce="200"
        />

        <ul id="own-password-checks" class="my-4 space-y-2" aria-live="polite">
          <.check id="check-length" met={@checks.length}>
            {gettext("8 caractères au moins")}
          </.check>
          <.check id="check-match" met={@checks.match}>
            {gettext("Les deux saisies sont identiques")}
          </.check>
        </ul>

        <button type="submit" class="w-full" phx-disable-with={gettext("Enregistrement…")}>
          {gettext("Enregistrer et continuer")}
        </button>
      </.form>

      <p class="text-center text-sm">
        <.link href={~p"/sign-out"} method="delete">{gettext("Se déconnecter")}</.link>
      </p>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :met, :boolean, required: true
  slot :inner_block, required: true

  defp check(assigns) do
    ~H"""
    <li id={@id} data-met={@met} class="ta-check">
      <span class="ta-check__mark"><.icon name="hero-check" class="size-3" /></span>
      {render_slot(@inner_block)}
    </li>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, AshPhoenix.Form.validate(socket.assigns.form, params))
     |> assign_checks(params)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Mot de passe enregistré."))
         |> push_navigate(to: ~p"/school")}

      {:error, form} ->
        {:noreply, socket |> assign(:form, form) |> assign_checks(params)}
    end
  end

  defp assign_checks(socket, params) do
    password = params["password"] || ""
    confirmation = params["password_confirmation"] || ""

    assign(socket, :checks, %{
      length: String.length(password) >= @min_length,
      match: password != "" and password == confirmation
    })
  end

  defp password_form(%User{} = user) do
    user
    |> AshPhoenix.Form.for_update(:set_own_password, as: "form", actor: user)
    |> to_form()
  end

  # « 6 77 12 34 56 · Lycée de Biyem-Assi » — the school only once one is chosen.
  defp identity_line(user, scope) do
    school = scope && scope.current_workspace && scope.current_workspace.name

    [User.contact(user), school]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp initials(name) do
    name
    |> String.split(~r/[\s@.]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end
