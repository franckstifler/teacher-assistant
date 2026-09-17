defmodule TeacherAssistant.Accounts.CameroonRegion do
  use Ash.Type.Enum,
    values: [
      :adamawa,
      :centre,
      :east,
      :far_north,
      :littoral,
      :north,
      :northwest,
      :south,
      :southwest,
      :west
    ]
end
