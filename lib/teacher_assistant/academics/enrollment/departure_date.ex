defmodule TeacherAssistant.Academics.Enrollment.DepartureDate do
  @moduledoc """
  Guards `:leave` (review of A7): the departure day lies within the enrollment's
  academic year and is not after today. A future date or a wrong year would
  otherwise drop the student silently from rolls, counts and every period after it.
  """
  use Ash.Resource.Validation

  alias TeacherAssistant.Academics.{AcademicYear, Reference}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    left_on = Ash.Changeset.get_attribute(changeset, :left_on)

    # Another school's enrollment finds no year here: the tenant guard refuses it.
    case left_on &&
           Ash.get(AcademicYear, changeset.data.academic_year_id,
             tenant: changeset.tenant || context.tenant,
             authorize?: false
           ) do
      {:ok, year} -> check(left_on, year, Reference.today())
      _ -> :ok
    end
  end

  defp check(left_on, year, today) do
    cond do
      Date.compare(left_on, today) == :gt ->
        {:error, field: :left_on, message: "La date de départ ne peut pas être dans le futur."}

      Date.compare(left_on, year.start_date) == :lt or
          Date.compare(left_on, year.end_date) == :gt ->
        {:error, field: :left_on, message: "La date de départ doit tomber dans l'année scolaire."}

      true ->
        :ok
    end
  end
end
