defmodule TeacherAssistant.Discipline do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.SanctionEntry
    resource TeacherAssistant.Academics.ConductMark
  end
end
