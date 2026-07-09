defmodule TeacherAssistant.Accounts.Permissions do
  @moduledoc """
  Coarse, role-based access checks for school workspaces (P2.1).

  Permissions in the domain split on three axes — pedagogical, disciplinary,
  and financial (see docs/domain/05 §1). P2.1 implements only coarse role
  checks; the fine-grained per-axis matrix arrives with the features it
  protects (bulletins → P2.3, fees → P2.4).
  """
  alias TeacherAssistant.Scope
  alias TeacherAssistant.Academics.ClassGroup

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

  def discipline_master?(%Scope{current_workspace_type: :school, current_roles: roles}),
    do: :discipline_master in (roles || [])

  def discipline_master?(_), do: false

  def conduct_manager?(scope), do: admin?(scope) or discipline_master?(scope)

  def fees_manager?(scope), do: admin?(scope) or bursar?(scope)

  def form_master?(
        %Scope{current_workspace_type: :school, current_user: %{id: uid}},
        %ClassGroup{form_master_user_id: fm_id}
      ),
      do: not is_nil(fm_id) and fm_id == uid

  def form_master?(_, _), do: false

  def admin_or_form_master?(scope, %ClassGroup{} = cg),
    do: admin?(scope) or form_master?(scope, cg)
end
