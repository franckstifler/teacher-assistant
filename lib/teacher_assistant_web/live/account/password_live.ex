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
      <div
        id="own-password-identity"
        class="flex items-center gap-3 rounded-xl border p-3"
        style="border-color: #EFEAE0; background: #FAF8F3"
      >
        <span
          class="grid size-10 flex-none place-items-center rounded-full text-sm font-semibold"
          style="background: #172321; color: #E8E5DC; font-family: Fraunces, Georgia, serif"
        >
          {@initials}
        </span>
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold" style="margin: 0; color: #1E2A2B">
            {@display_name}
          </p>
          <p :if={@identity_line} class="ta-mono truncate text-xs" style="margin: 0; color: #5A6668">
            {@identity_line}
          </p>
        </div>
      </div>

      <div>
        <p
          class="ta-mono"
          style="margin: 0; font-size: 0.66rem; font-weight: 600; letter-spacing: 0.14em; text-transform: uppercase; color: #0E7A5F"
        >
          {gettext("Votre compte · étape unique")}
        </p>
        <h1 style="margin: 0.4rem 0 0; font-size: 1.55rem; font-weight: 700; letter-spacing: -0.01em; color: #1E2A2B">
          {gettext("Choisissez votre mot de passe")}
        </h1>
        <p style="margin: 0.5rem 0 0; font-size: 0.86rem; line-height: 1.55; color: #5A6668">
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
    <li id={@id} data-met={@met} class="flex items-center gap-2 text-sm" style="color: #44514F">
      <span
        class="grid size-5 flex-none place-items-center rounded-full border transition-colors duration-200"
        style={
          if @met,
            do: "background: #0E7A5F; border-color: #0E7A5F; color: #FFFFFF",
            else: "background: #FFFFFF; border-color: #D7CFBE; color: transparent"
        }
      >
        <.icon name="hero-check" class="size-3" />
      </span>
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
