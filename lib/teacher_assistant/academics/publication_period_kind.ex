defmodule TeacherAssistant.Academics.PublicationPeriodKind do
  @moduledoc "The period a report-card publication covers (spec I2): a trimester or the year."
  use Ash.Type.Enum, values: [:trimester, :annual]
end
