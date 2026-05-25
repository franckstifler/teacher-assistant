defmodule TeacherAssistant.Academics.GradeIntervalTest do
  use TeacherAssistant.DataCase, async: true

  describe "grade intervals" do
    test "configures school appreciations and resolves report-card appreciation", %{
      tenant: tenant,
      user: user
    } do
      weak =
        Ash.create!(
          TeacherAssistant.Academics.GradeInterval,
          %{
            min_score: Decimal.new("0"),
            max_score: Decimal.new("9.99"),
            label: "Weak",
            appreciation: "Insufficient acquisition",
            position: 1
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      good =
        Ash.create!(
          TeacherAssistant.Academics.GradeInterval,
          %{
            min_score: Decimal.new("10"),
            max_score: Decimal.new("20"),
            label: "Good",
            appreciation: "Competence acquired",
            position: 2
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      assert TeacherAssistant.Academics.ReportCards.appreciation_for(
               Decimal.new("12.25"),
               [weak, good]
             ) == "Competence acquired"

      assert TeacherAssistant.Academics.ReportCards.appreciation_for(
               Decimal.new("8"),
               [weak, good]
             ) == "Insufficient acquisition"
    end

    test "teachers read but do not manage grade intervals", %{tenant: tenant} do
      admin = Ash.Generator.generate(admin_user(tenant: tenant))
      teacher = Ash.Generator.generate(user(tenant: tenant))

      interval =
        Ash.create!(
          TeacherAssistant.Academics.GradeInterval,
          %{
            min_score: Decimal.new("10"),
            max_score: Decimal.new("20"),
            label: "Good",
            appreciation: "Competence acquired"
          },
          tenant: tenant,
          actor: admin,
          authorize?: false
        )

      assert Ash.can?({interval, :read}, teacher, tenant: tenant)
      assert Ash.can?({TeacherAssistant.Academics.GradeInterval, :create}, admin, tenant: tenant)

      refute Ash.can?({TeacherAssistant.Academics.GradeInterval, :create}, teacher,
               tenant: tenant
             )

      refute Ash.can?({interval, :update}, teacher, tenant: tenant)
    end
  end
end
