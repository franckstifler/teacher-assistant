defmodule TeacherAssistant.Accounts.Permissions do
  @moduledoc """
  Coarse, role-based access checks for school workspaces (P2.1).

  Permissions in the domain split on three axes — pedagogical, disciplinary,
  and financial (see docs/domain/05 §1). P2.1 implements only coarse role
  checks; the fine-grained per-axis matrix arrives with the features it
  protects (bulletins → P2.3, fees → P2.4).
  """
  alias TeacherAssistant.Scope

  def member?(%Scope{current_workspace_type: :school}), do: true
  def member?(_), do: false

  def head?(%Scope{current_workspace_type: :school, current_roles: roles}),
    do: :head in (roles || [])

  def head?(_), do: false

  def bursar?(%Scope{current_workspace_type: :school, current_roles: roles}),
    do: :bursar in (roles || [])

  def bursar?(_), do: false

  def admin?(%Scope{current_workspace_type: :school, current_roles: roles}) do
    r = roles || []
    :head in r or :vice_principal in r
  end

  def admin?(_), do: false
end
