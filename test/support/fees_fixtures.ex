defmodule TeacherAssistant.FeesFixtures do
  @moduledoc "A school year with Frais exigibles 50 000 + PTA 10 000 for one class and two tranches (Fees 1)."
  alias TeacherAssistant.{Enrollment, Fees}
  alias TeacherAssistant.TeacherFixtures

  def fees_school_fixture do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, _} = Fees.create_default_fee_types(scope, year)
    [fe, pta] = Fees.list_fee_types(scope, year)
    {:ok, _} = Fees.set_class_fee(scope, cg, fe, 50_000)
    {:ok, _} = Fees.set_class_fee(scope, cg, pta, 10_000)

    {:ok, _} =
      Fees.add_tranche(scope, year, %{label: "1re tranche", due_date: ~D[2025-10-15], percent: 50})

    {:ok, _} =
      Fees.add_tranche(scope, year, %{label: "2e tranche", due_date: ~D[2026-01-15], percent: 100})

    {:ok, %{enrollment: e, student: s}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa A", sex: :f})

    %{scope: scope, year: year, cg: cg, fe: fe, pta: pta, e: e, student: s}
  end

  def cash(amount, paid_on \\ ~D[2025-10-01]),
    do: %{amount: amount, paid_on: paid_on, method: :cash}
end
