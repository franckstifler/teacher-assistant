defmodule TeacherAssistant.Academics.Fees do
  @moduledoc "Fees: tranche schedule CRUD (P2.10)."

  require Ash.Query

  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.FeeTranche

  @doc """
  Lists `FeeTranche`s for `class_group`, ordered by `position` ascending.
  """
  def list_tranches(%ClassGroup{id: cg_id}) do
    FeeTranche
    |> Ash.Query.filter(class_group_id == ^cg_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Adds a fee tranche to `class_group`. `attrs` carries `label`, `amount`
  (integer FCFA), optional `due_date`. Rejects a negative `amount` with
  `{:error, :invalid_amount}`. `workspace_id` is taken from the class
  group; `position` is set to the next index (count of existing tranches).
  """
  def add_tranche(%ClassGroup{} = class_group, attrs) do
    amount = attrs[:amount] || attrs["amount"]

    with :ok <- validate_amount(amount) do
      position = length(list_tranches(class_group))

      FeeTranche
      |> Ash.Changeset.for_create(:create, %{
        label: attrs[:label] || attrs["label"],
        amount: amount,
        due_date: attrs[:due_date] || attrs["due_date"],
        position: position,
        workspace_id: class_group.workspace_id,
        class_group_id: class_group.id
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, tranche} -> {:ok, tranche}
        {:error, _error} -> {:error, :tranche_failed}
      end
    end
  end

  @doc """
  Updates `tranche` with `attrs`. Rejects a negative `amount` (when
  present) with `{:error, :invalid_amount}`. Sanitizes any Ash write
  failure to `{:error, :tranche_failed}`.
  """
  def update_tranche(%FeeTranche{} = tranche, attrs) do
    amount = attrs[:amount] || attrs["amount"]

    with :ok <- validate_amount(amount) do
      tranche
      |> Ash.Changeset.for_update(:update, attrs)
      |> Ash.update(authorize?: false)
      |> case do
        {:ok, tranche} -> {:ok, tranche}
        {:error, _error} -> {:error, :tranche_failed}
      end
    end
  end

  defp validate_amount(nil), do: :ok
  defp validate_amount(amount) when is_integer(amount) and amount >= 0, do: :ok
  defp validate_amount(_amount), do: {:error, :invalid_amount}

  @doc "Deletes `tranche`."
  def delete_tranche(%FeeTranche{} = tranche) do
    case Ash.destroy(tranche, authorize?: false) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, _error} -> {:error, :delete_failed}
    end
  end
end
