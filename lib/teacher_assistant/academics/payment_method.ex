defmodule TeacherAssistant.Academics.PaymentMethod do
  use Ash.Type.Enum,
    values: [:cash, :mobile_money, :bank_transfer, :other]
end
