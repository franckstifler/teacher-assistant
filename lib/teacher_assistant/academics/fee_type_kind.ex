defmodule TeacherAssistant.Academics.FeeTypeKind do
  @moduledoc "A school fee type (Fees 1): a regular fee, or last year's carried arrears."
  use Ash.Type.Enum, values: [:regular, :arrears]
end
