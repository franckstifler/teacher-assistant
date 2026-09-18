defmodule TeacherAssistant.Assessment do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.Assessment
    resource TeacherAssistant.Academics.Mark
  end
end
