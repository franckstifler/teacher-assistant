defmodule TeacherAssistantWeb.NotificationHooks do
  @moduledoc """
  Spec KLM8: the header bell on every school LiveView. On mount it puts the bell
  (`Notifications.bell/1`) into `current_scope.capabilities.notifications` for the
  layout and subscribes to the member's topic; it refreshes the bell on
  `:notifications_changed` (a view exporting `notifications_changed/1`, the inbox,
  is told too) and handles the bell's own events, so other pages need no code for
  it. Navigation data only — reading and marking stay under the resource policies.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_navigate: 2]

  alias TeacherAssistant.Notifications

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns.current_scope do
      %{current_workspace: %{}, current_user: %{id: user_id}} ->
        if connected?(socket), do: Notifications.subscribe(user_id)

        {:cont,
         socket
         |> put_bell()
         |> attach_hook(:notification_info, :handle_info, &handle_info/2)
         |> attach_hook(:notification_events, :handle_event, &handle_event/3)}

      _ ->
        {:cont, socket}
    end
  end

  # A page that shows notices itself (the inbox) opts in by exporting
  # `notifications_changed/1`; other views never receive the message.
  defp handle_info(:notifications_changed, socket) do
    socket = put_bell(socket)

    if function_exported?(socket.view, :notifications_changed, 1),
      do: {:halt, socket.view.notifications_changed(socket)},
      else: {:halt, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("notification:open", %{"id" => id}, socket) do
    case Notifications.open(socket.assigns.current_scope, id) do
      {:ok, link} -> {:halt, push_navigate(socket, to: link)}
      :error -> {:halt, socket}
    end
  end

  defp handle_event("notification:read_all", _params, socket) do
    :ok = Notifications.mark_all_read(socket.assigns.current_scope)
    {:halt, put_bell(socket)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp put_bell(socket) do
    scope = socket.assigns.current_scope
    bell = Notifications.bell(scope)
    scope = %{scope | capabilities: Map.put(scope.capabilities || %{}, :notifications, bell)}

    socket |> assign(:current_scope, scope) |> assign(:scope, scope)
  end
end
