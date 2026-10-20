defmodule TeacherAssistant.Academics.PaymentStatus do
  @moduledoc "A recorded payment (receipt) is valid until cancelled (Fees 1); it is never edited."
  use Ash.Type.Enum, values: [:valid, :cancelled]
end
