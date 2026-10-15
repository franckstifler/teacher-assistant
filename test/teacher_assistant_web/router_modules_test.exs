defmodule TeacherAssistantWeb.RouterModulesTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Modules

  # Navigation controllers only set a session value and redirect.
  @navigation [
    TeacherAssistantWeb.SpaceController,
    TeacherAssistantWeb.TeacherContextController
  ]

  test "every /school and /teacher screen is core or belongs to a module" do
    unmapped =
      for route <- TeacherAssistantWeb.Router.__routes__(),
          String.starts_with?(route.path, ["/school/", "/teacher/"]) or route.path == "/school",
          target = target(route),
          target != :skip,
          mapped(target) == nil,
          do: {route.path, target}

    assert unmapped == []
  end

  defp target(%{metadata: %{phoenix_live_view: {view, _action, _opts, _extra}}}),
    do: {:view, view}

  defp target(%{plug: plug}) when plug in @navigation, do: :skip
  defp target(%{plug: plug, plug_opts: action}), do: {:controller, plug, action}

  defp mapped({:view, view}), do: Modules.module_for_view(view)
  defp mapped({:controller, c, a}), do: Modules.module_for_controller(c, a)
end
