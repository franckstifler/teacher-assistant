defmodule TeacherAssistant.Fees do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.FeeTranche
    resource TeacherAssistant.Academics.FeeAdjustment
    resource TeacherAssistant.Academics.Payment
  end
end
