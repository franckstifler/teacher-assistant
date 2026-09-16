defmodule TeacherAssistant.Accounts.SchoolSubsystem do
  use Ash.Type.Enum, values: [:francophone, :anglophone, :bilingual]
end
