defmodule TeacherAssistantWeb.PageController do
  use TeacherAssistantWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
