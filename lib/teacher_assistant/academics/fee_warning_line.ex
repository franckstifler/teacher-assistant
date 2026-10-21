defmodule TeacherAssistant.Academics.FeeWarningLine do
  @moduledoc "One fee type's overdue amount on a warning, frozen when it is issued (Fees 2)."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :amount, :integer, allow_nil?: false, public?: true
  end
end
