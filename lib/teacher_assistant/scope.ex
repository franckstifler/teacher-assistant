defmodule TeacherAssistant.Scope do
  defstruct [
    :current_user,
    :current_tenant,
    :current_workspace,
    :current_workspace_type,
    :current_role,
    :current_academic_year,
    :locale
  ]

  def school_context?(%__MODULE__{current_workspace_type: :school}), do: true
  def school_context?(_scope), do: false

  def personal_context?(%__MODULE__{current_workspace_type: :personal_teacher}), do: true
  def personal_context?(_scope), do: false

  def academic_year_ready?(%__MODULE__{
        current_academic_year: %TeacherAssistant.Academics.AcademicYear{}
      }),
      do: true

  def academic_year_ready?(_scope), do: false

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{current_user: current_user}), do: {:ok, current_user}
    def get_tenant(%{current_tenant: current_tenant}), do: {:ok, current_tenant}
    def get_context(%{locale: locale}), do: {:ok, %{shared: %{locale: locale}}}
    # You typically configure tracers in config files
    # so this will typically return :error
    def get_tracer(_), do: :error

    # This should likely always return :error
    # unless you want a way to bypass authorization configured in your scope
    def get_authorize?(_), do: :error
  end
end
