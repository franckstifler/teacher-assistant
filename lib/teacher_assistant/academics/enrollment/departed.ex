defmodule TeacherAssistant.Academics.Enrollment.Departed do
  @moduledoc """
  Guards `:leave` and `:return` (spec audit follow-ups A7) on the stored record:
  `departed?: false` refuses a student already marked as left, `departed?: true` one
  who has not left.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    departed? = not is_nil(changeset.data.left_on)

    cond do
      departed? == opts[:departed?] -> :ok
      departed? -> {:error, field: :left_on, message: "Cet élève est déjà marqué parti."}
      true -> {:error, field: :left_on, message: "Cet élève n'est pas marqué parti."}
    end
  end
end
