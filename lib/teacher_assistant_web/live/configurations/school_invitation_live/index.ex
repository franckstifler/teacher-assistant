defmodule TeacherAssistantWeb.Configurations.SchoolInvitationLive.Index do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.SchoolInvitation
  alias TeacherAssistant.Accounts.Workspaces
  require Ash.Query

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-invitations-page" class="space-y-6">
        <div class="flex flex-col gap-2">
          <p class="ta-section-label">{gettext("School team")}</p>
          <h1 class="text-2xl font-semibold tracking-normal">{gettext("Teacher invitations")}</h1>
          <p class="max-w-2xl text-sm text-base-content/65">
            {gettext("Invite teachers and school staff into this organisation with the right role.")}
          </p>
        </div>

        <.form
          for={@form}
          id="school-invitation-form"
          phx-submit="invite"
          class="ta-panel grid gap-4 p-5 md:grid-cols-[1fr_14rem_auto]"
        >
          <.input field={@form[:email]} type="email" label={gettext("Email")} />
          <.input
            field={@form[:role]}
            type="select"
            label={gettext("Role")}
            options={role_options()}
          />
          <div class="flex items-end">
            <.button id="send-school-invitation" class="btn btn-primary w-full">
              <.icon name="hero-paper-airplane" class="size-4" />
              {gettext("Invite")}
            </.button>
          </div>
        </.form>

        <div class="ta-panel overflow-hidden">
          <table id="school-invitations" class="table">
            <thead>
              <tr>
                <th>{gettext("Email")}</th>
                <th>{gettext("Role")}</th>
                <th>{gettext("Status")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={invitation <- @invitations} id={"school-invitation-#{invitation.id}"}>
                <td>{invitation.email}</td>
                <td>{format_atom(invitation.role)}</td>
                <td>
                  <span class="badge badge-soft">{format_atom(invitation.status)}</span>
                </td>
              </tr>
              <tr :if={@invitations == []}>
                <td colspan="3" class="text-sm text-base-content/55">
                  {gettext("No invitations yet.")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(%{"email" => "", "role" => "teacher"}, as: :invitation))
     |> assign(:invitations, list_invitations(socket.assigns.scope))}
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    role = parse_role(params["role"])

    invitation =
      Workspaces.invite_user!(%{
        school: socket.assigns.scope.current_tenant,
        inviter: socket.assigns.scope.current_user,
        email: params["email"],
        role: role
      })

    {:noreply,
     socket
     |> put_flash(:info, gettext("Invitation created"))
     |> assign(:form, to_form(%{"email" => "", "role" => "teacher"}, as: :invitation))
     |> assign(:invitations, [invitation | socket.assigns.invitations])}
  end

  defp list_invitations(scope) do
    SchoolInvitation
    |> Ash.Query.filter(school_id == ^scope.current_tenant.id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp role_options do
    [
      {gettext("Teacher"), "teacher"},
      {gettext("Principal teacher"), "principal_teacher"},
      {gettext("Accountant"), "accountant"},
      {gettext("Vice-principal"), "vice_principal"}
    ]
  end

  defp parse_role("principal_teacher"), do: :principal_teacher
  defp parse_role("accountant"), do: :accountant
  defp parse_role("vice_principal"), do: :vice_principal
  defp parse_role(_role), do: :teacher

  defp format_atom(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
  end
end
