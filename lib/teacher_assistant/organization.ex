defmodule TeacherAssistant.Organization do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.Workspace
    resource TeacherAssistant.Academics.AcademicYear
    resource TeacherAssistant.Academics.Term
    resource TeacherAssistant.Academics.Sequence
  end
end
