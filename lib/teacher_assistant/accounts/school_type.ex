defmodule TeacherAssistant.Accounts.SchoolType do
  use Ash.Type.Enum,
    values: [
      :lycee,
      :ces_ceg,
      :lycee_technique,
      :cetic,
      :gss,
      :ghs,
      :gbss,
      :gbhs,
      :gtc,
      :gths,
      :sar_sm
    ]
end
