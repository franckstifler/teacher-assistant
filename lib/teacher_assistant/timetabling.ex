defmodule TeacherAssistant.Timetabling do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.TimetableSlot
  end
end
