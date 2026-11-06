defmodule TeacherAssistantWeb.Admin.ResetModal do
  @moduledoc """
  Operator console spec §3: confirm a password reset, then show the temporary password
  once with a ready-to-send message. The clear password lives only in the LiveView's
  assigns until the modal is closed. The LiveView handles `reset_confirm` and
  `reset_cancel`.
  """
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.Modal

  attr :user, :map, required: true
  attr :password, :string, default: nil

  def reset_modal(assigns) do
    ~H"""
    <.modal
      id="reset-modal"
      title={
        gettext("Réinitialiser le mot de passe de %{name}",
          name: TeacherAssistant.Accounts.User.display_name(@user)
        )
      }
      on_close="reset_cancel"
    >
      <%= if @password do %>
        <p class="text-sm">{gettext("Mot de passe temporaire, affiché une seule fois :")}</p>
        <p id="reset-password-value" class="ta-num text-2xl font-semibold tracking-wider">
          {@password}
        </p>
        <textarea id="reset-message" readonly class="textarea textarea-bordered w-full text-sm">{gettext(
          "Votre mot de passe temporaire Scolaka : %{password}. Il est valable 7 jours ; vous en choisirez un nouveau à la connexion.",
          password: @password
        )}</textarea>
      <% else %>
        <p class="text-sm">
          {gettext(
            "Un mot de passe temporaire valable 7 jours remplacera l'actuel. La personne sera déconnectée de tous ses appareils."
          )}
        </p>
      <% end %>
      <:actions>
        <%= if @password do %>
          <button id="reset-close" type="button" class="btn btn-primary" phx-click="reset_cancel">
            {gettext("Fermer")}
          </button>
        <% else %>
          <button type="button" class="btn btn-ghost" phx-click="reset_cancel">
            {gettext("Annuler")}
          </button>
          <button id="reset-confirm" type="button" class="btn btn-primary" phx-click="reset_confirm">
            {gettext("Réinitialiser")}
          </button>
        <% end %>
      </:actions>
    </.modal>
    """
  end
end
