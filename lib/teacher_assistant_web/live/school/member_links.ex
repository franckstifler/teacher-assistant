defmodule TeacherAssistantWeb.School.MemberLinks do
  @moduledoc """
  A staff member's name that opens their page (`/school/members/:id`) on screens that
  show teachers: Affectations, Suivi des séquences, the timetable editor. Only those
  who may open a member (staff managers, those who set services) get links; others
  see the plain name.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Accounts

  @doc "Membership ids by user id, for `member_name/1`; empty for viewers who may not open members."
  def member_ids(scope) do
    if Accounts.can_manage_staff?(scope) or Accounts.can_set_member_service?(scope),
      do: Map.new(Accounts.list_members(scope), &{&1.user_id, &1.id}),
      else: %{}
  end

  attr :ids, :map, required: true, doc: "from `member_ids/1`"
  attr :user_id, :any, required: true
  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  def member_name(assigns) do
    assigns = assign(assigns, :member_id, assigns.user_id && assigns.ids[assigns.user_id])

    ~H"""
    <.link
      :if={@member_id}
      navigate={~p"/school/members/#{@member_id}"}
      class={["hover:text-primary hover:underline", @class]}
      {@rest}
    >{@name}</.link>
    <span :if={!@member_id} class={@class} {@rest}>{@name}</span>
    """
  end
end
