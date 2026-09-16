defmodule TeacherAssistant.Accounts.SchoolSector do
  use Ash.Type.Enum, values: [:public, :private_lay, :private_confessional, :community]
end
