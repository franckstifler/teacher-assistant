defmodule TeacherAssistant.Accounts.SanctionPoints do
  @moduledoc """
  Spec KLM2: the conduct points a sanction of each type costs, embedded in
  `SchoolProfile.sanction_points` (nil there = these defaults).
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    for {type, default} <- [
          consigne: "1",
          avertissement: "2",
          blame: "4",
          exclusion_temporaire: "6",
          exclusion_definitive: "0"
        ] do
      attribute type, :decimal,
        allow_nil?: false,
        default: Decimal.new(default),
        public?: true,
        constraints: [min: 0, max: 20]
    end
  end
end
