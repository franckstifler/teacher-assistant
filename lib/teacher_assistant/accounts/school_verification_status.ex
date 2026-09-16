defmodule TeacherAssistant.Accounts.SchoolVerificationStatus do
  use Ash.Type.Enum, values: [:unverified, :verified, :rejected]
end
