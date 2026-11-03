defmodule TeacherAssistantWeb.Plug.RequirePasswordChange do
  @moduledoc """
  Controller-side twin of the `LiveUserAuth` gate: a signed-in user who still
  holds a temporary password is sent to `/account/password` — unless it is the
  operator acting as them, who may not change it. Runs after
  `TeacherAssistantWeb.Plug.Scope` (which assigns `current_user`).
  """
  @behaviour Plug
  use TeacherAssistantWeb, :verified_routes

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{current_scope: %{impersonation: %{}}}} = conn, _opts), do: conn

  def call(%{assigns: %{current_user: %{must_change_password: true}}} = conn, _opts) do
    conn
    |> Phoenix.Controller.redirect(to: ~p"/account/password")
    |> Plug.Conn.halt()
  end

  def call(conn, _opts), do: conn
end
