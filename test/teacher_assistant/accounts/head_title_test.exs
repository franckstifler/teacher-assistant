defmodule TeacherAssistant.Accounts.HeadTitleTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.HeadTitle

  test "head title by school type" do
    assert HeadTitle.title(:lycee, :fr) == "Le Proviseur"
    assert HeadTitle.title(:lycee_technique, :fr) == "Le Proviseur"
    assert HeadTitle.title(:ces_ceg, :fr) == "Le Directeur"
    assert HeadTitle.title(:cetic, :fr) == "Le Directeur"
    assert HeadTitle.title(:sar_sm, :fr) == "Le Directeur"
    assert HeadTitle.title(:ghs, :fr) == nil
    assert HeadTitle.title(:gths, :fr) == nil
    assert HeadTitle.title(:lycee, :en) == "The Principal"
    assert HeadTitle.title(:gbhs, :en) == "The Principal"
  end
end
