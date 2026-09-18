defmodule TeacherAssistant.Enrollment do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.ClassGroup
    resource TeacherAssistant.Academics.Student
    resource TeacherAssistant.Academics.Enrollment
  end
end
