defmodule TeacherAssistant.Academics.StampOperator do
  @moduledoc """
  Stamps the operator acting as a member (spec audit follow-ups A6) next to an
  actor column: `change {StampOperator, attribute: :operator_user_id}`. The
  operator's id comes from the scope (`Ash.Scope.ToOpts` puts it in the shared
  context as `operator_user_id`); nil when the member acts themselves, so a write
  by the member clears the stamp of an earlier one.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts) do
    case opts[:attribute] do
      attr when is_atom(attr) and not is_nil(attr) -> {:ok, opts}
      _ -> {:error, "StampOperator needs `attribute:`"}
    end
  end

  @impl true
  def change(changeset, opts, _context),
    do: Ash.Changeset.force_change_attribute(changeset, opts[:attribute], operator_id(changeset))

  @impl true
  def atomic(changeset, opts, _context),
    do: {:atomic, %{opts[:attribute] => operator_id(changeset)}}

  @doc "The operator acting as the member in this write, or nil."
  def operator_id(%{context: context}), do: context[:operator_user_id]
end
