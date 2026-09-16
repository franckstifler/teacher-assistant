defmodule TeacherAssistant.Accounts.MembershipStatus do
  use Ash.Type.Enum, values: [:titulaire, :contractuel, :vacataire]
end
