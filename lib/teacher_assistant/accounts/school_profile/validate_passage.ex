defmodule TeacherAssistant.Accounts.SchoolProfile.ValidatePassage do
  @moduledoc """
  Spec I4 rules for the passage settings: among the set values,
  0 ≤ exclusion_below < rachat_min ≤ passage_min ≤ 20, and the absence hours positive.
  """
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @zero Decimal.new(0)
  @twenty Decimal.new(20)

  @impl true
  def validate(changeset, _opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)
    chain = [@zero, get.(:exclusion_below), get.(:rachat_min), get.(:passage_min), @twenty]
    hours = get.(:exclusion_absence_hours)

    cond do
      not ordered?(chain, get.(:exclusion_below), get.(:rachat_min)) ->
        {:error, field: :passage_min, message: gettext("Exclusion < rachat ≤ passage ≤ 20.")}

      hours != nil and hours <= 0 ->
        {:error,
         field: :exclusion_absence_hours,
         message: gettext("Le nombre d'heures doit être positif.")}

      true ->
        :ok
    end
  end

  # Non-decreasing over the set values; exclusion strictly below rachat when both set.
  defp ordered?(chain, exclusion, rachat) do
    set = Enum.reject(chain, &is_nil/1)

    non_decreasing? =
      set |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> not lt?(b, a) end)

    strict? = is_nil(exclusion) or is_nil(rachat) or lt?(exclusion, rachat)
    non_decreasing? and strict?
  end

  defp lt?(a, b), do: Decimal.compare(a, b) == :lt
end
