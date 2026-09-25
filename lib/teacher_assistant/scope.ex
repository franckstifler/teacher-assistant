defmodule TeacherAssistant.Scope do
  @moduledoc """
  Current user/workspace context used by authenticated LiveViews.
  """

  defstruct [
    :current_user,
    :current_workspace,
    :current_role,
    :current_roles,
    :current_membership,
    :current_academic_year,
    :current_context,
    :locale,
    :school_verification_status
  ]

  def school_verified?(%__MODULE__{school_verification_status: :verified}), do: true
  def school_verified?(_scope), do: false

  def academic_year_ready?(%__MODULE__{
        current_academic_year: %TeacherAssistant.Academics.AcademicYear{}
      }),
      do: true

  def academic_year_ready?(_), do: false

  def setup_complete?(%__MODULE__{current_workspace: %{}} = scope) do
    year = scope.current_academic_year

    year != nil and
      TeacherAssistant.Enrollment.list_class_groups(scope, year) != []
  end

  def setup_complete?(%__MODULE__{current_workspace: nil}), do: true

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{current_user: current_user}), do: {:ok, current_user}
    def get_tenant(%{current_workspace: %{id: id}}), do: {:ok, id}
    def get_tenant(_), do: :error
    def get_context(%{locale: locale}), do: {:ok, %{shared: %{locale: locale}}}
    def get_tracer(_), do: :error
    def get_authorize?(_), do: :error
  end
end
