defmodule TeacherAssistant.Accounts.SchoolProfile.ValidateGradeScale do
  @moduledoc """
  Spec I5 rules for the grade scale: bands start at 0, strictly increase, stay within
  0..20, and each has a letter and a remark. nil or [] means the default scale.
  """
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @zero Decimal.new(0)
  @twenty Decimal.new(20)

  @impl true
  def validate(changeset, _opts, _context),
    do: changeset |> Ash.Changeset.get_attribute(:grade_scale) |> check()

  defp check(bands) when bands in [nil, []], do: :ok

  defp check([first | _] = bands) do
    froms = Enum.map(bands, & &1.from)

    cond do
      Enum.any?(bands, &(blank?(&1.letter) or blank?(&1.remark))) ->
        error(gettext("Chaque tranche doit avoir une lettre et une remarque."))

      not Decimal.equal?(first.from, @zero) ->
        error(gettext("La première tranche doit commencer à 0."))

      Enum.any?(froms, &(lt?(&1, @zero) or lt?(@twenty, &1))) ->
        error(gettext("Les bornes doivent être comprises entre 0 et 20."))

      not (froms |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> lt?(a, b) end)) ->
        error(gettext("Les bornes doivent être croissantes."))

      true ->
        :ok
    end
  end

  defp blank?(text), do: is_nil(text) or String.trim(text) == ""
  defp lt?(a, b), do: Decimal.compare(a, b) == :lt
  defp error(message), do: {:error, field: :grade_scale, message: message}
end
