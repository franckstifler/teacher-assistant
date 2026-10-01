defmodule TeacherAssistant.Accounts.SchoolProfile.ValidateAppreciations do
  @moduledoc """
  Spec I1 rules for the appreciation scale and the distinction thresholds:
  bands start at 0, strictly increase, stay within 0..20 and have a label;
  set thresholds stay within 0..20 with Félicitations ≥ Encouragements ≥ Tableau
  d'honneur, Blâme < Avertissement and Avertissement ≤ Tableau d'honneur.
  """
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @zero Decimal.new(0)
  @twenty Decimal.new(20)

  @thresholds [
    :felicitations_min,
    :encouragements_min,
    :tableau_honneur_min,
    :avertissement_travail_below,
    :blame_travail_below
  ]

  @impl true
  def validate(changeset, _opts, _context) do
    with :ok <- validate_bands(Ash.Changeset.get_attribute(changeset, :appreciation_bands)) do
      validate_thresholds(Map.new(@thresholds, &{&1, Ash.Changeset.get_attribute(changeset, &1)}))
    end
  end

  defp validate_bands(bands) when bands in [nil, []], do: :ok

  defp validate_bands([first | _] = bands) do
    froms = Enum.map(bands, & &1.from)

    cond do
      Enum.any?(bands, &blank?(&1.label)) ->
        band_error(gettext("Chaque tranche doit avoir une appréciation."))

      not Decimal.equal?(first.from, @zero) ->
        band_error(gettext("La première tranche doit commencer à 0."))

      Enum.any?(froms, &out_of_range?/1) ->
        band_error(gettext("Les bornes doivent être comprises entre 0 et 20."))

      not strictly_increasing?(froms) ->
        band_error(gettext("Les bornes doivent être croissantes."))

      true ->
        :ok
    end
  end

  defp validate_thresholds(t) do
    cond do
      t |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.any?(&out_of_range?/1) ->
        threshold_error(gettext("Les seuils doivent être compris entre 0 et 20."))

      not non_increasing?([t.felicitations_min, t.encouragements_min, t.tableau_honneur_min]) ->
        threshold_error(gettext("Félicitations ≥ Encouragements ≥ Tableau d'honneur."))

      both?(t.blame_travail_below, t.avertissement_travail_below) and
          not lt?(t.blame_travail_below, t.avertissement_travail_below) ->
        threshold_error(
          gettext("Le seuil du blâme doit être inférieur à celui de l'avertissement.")
        )

      both?(t.avertissement_travail_below, t.tableau_honneur_min) and
          lt?(t.tableau_honneur_min, t.avertissement_travail_below) ->
        threshold_error(
          gettext("Le seuil de l'avertissement ne peut pas dépasser celui du tableau d'honneur.")
        )

      true ->
        :ok
    end
  end

  defp blank?(label), do: is_nil(label) or String.trim(label) == ""

  defp out_of_range?(d), do: lt?(d, @zero) or lt?(@twenty, d)

  defp strictly_increasing?(values),
    do: values |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> lt?(a, b) end)

  # Over the set values only, in the given order.
  defp non_increasing?(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> not lt?(a, b) end)
  end

  defp both?(a, b), do: not is_nil(a) and not is_nil(b)
  defp lt?(a, b), do: Decimal.compare(a, b) == :lt

  defp band_error(message), do: {:error, field: :appreciation_bands, message: message}
  defp threshold_error(message), do: {:error, field: :felicitations_min, message: message}
end
