defmodule TeacherAssistant.Academics.MarkStatus do
  @moduledoc """
  What a stored mark records (spec D2b-2): a score, an unjustified absence (`abs`) or a
  justified one (`abj`). "Not entered yet" is the absence of a mark row.
  """
  use Ash.Type.Enum, values: [:graded, :absent, :excused]

  def code(:absent), do: "abs"
  def code(:excused), do: "abj"
end
