defmodule TeacherAssistant.Academics.Holiday.ValidateDates do
  @moduledoc "Spec J1: a holiday has a label, ends on or after its start, and lies inside its year."
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.AcademicYear

  @impl true
  def validate(changeset, _opts, _context) do
    label = Ash.Changeset.get_attribute(changeset, :label)
    s = Ash.Changeset.get_attribute(changeset, :start_date)
    e = Ash.Changeset.get_attribute(changeset, :end_date)
    year_id = Ash.Changeset.get_attribute(changeset, :academic_year_id)

    cond do
      is_nil(label) or String.trim(label) == "" ->
        {:error, field: :label, message: gettext("Donnez un libellé.")}

      is_nil(s) or is_nil(e) ->
        :ok

      Date.compare(e, s) == :lt ->
        {:error,
         field: :end_date, message: gettext("La fin doit être le même jour ou après le début.")}

      not inside_year?(changeset.tenant, year_id, s, e) ->
        {:error,
         field: :start_date, message: gettext("Les dates doivent être dans l'année scolaire.")}

      true ->
        :ok
    end
  end

  defp inside_year?(tenant, year_id, s, e) do
    case Ash.get(AcademicYear, year_id, tenant: tenant, authorize?: false) do
      {:ok, year} ->
        Date.compare(s, year.start_date) != :lt and Date.compare(e, year.end_date) != :gt

      _ ->
        false
    end
  end
end
