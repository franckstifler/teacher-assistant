defmodule TeacherAssistant.Scope do
  @moduledoc """
  Current user/workspace context used by authenticated LiveViews.
  """

  defstruct [
    :current_user,
    :current_workspace,
    :current_workspace_type,
    :current_role,
    :current_academic_year,
    :locale
  ]

  def personal_context?(%__MODULE__{current_workspace_type: :personal_teacher}), do: true
  def personal_context?(_scope), do: false

  # Task 4 will introduce TeacherAssistant.Academics.AcademicYear; until then always false.
  def academic_year_ready?(%__MODULE__{current_academic_year: %{__struct__: TeacherAssistant.Academics.AcademicYear}}), do: true
  def academic_year_ready?(_), do: false

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{current_user: current_user}), do: {:ok, current_user}
    def get_tenant(_), do: :error
    def get_context(%{locale: locale}), do: {:ok, %{shared: %{locale: locale}}}
    def get_tracer(_), do: :error
    def get_authorize?(_), do: :error
  end
end
