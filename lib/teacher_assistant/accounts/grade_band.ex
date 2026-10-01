defmodule TeacherAssistant.Accounts.GradeBand do
  @moduledoc """
  One band of a school's anglophone grade scale (spec I5), embedded in
  `SchoolProfile.grade_scale`: marks from `from` up to the next band's `from` get
  `letter` and `remark`. List rules live in `SchoolProfile.ValidateGradeScale`.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :from, :decimal, allow_nil?: false, public?: true
    # Nullable so blanks reach `ValidateGradeScale` and its own message.
    attribute :letter, :string, public?: true
    attribute :remark, :string, public?: true
  end
end
