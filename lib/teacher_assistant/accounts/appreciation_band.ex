defmodule TeacherAssistant.Accounts.AppreciationBand do
  @moduledoc """
  One band of a school's appreciation scale (spec I1), embedded in
  `SchoolProfile.appreciation_bands`: averages from `from` up to the next band's
  `from` read `label`. The list-level rules live in `SchoolProfile.ValidateAppreciations`.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :from, :decimal, allow_nil?: false, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
  end
end
