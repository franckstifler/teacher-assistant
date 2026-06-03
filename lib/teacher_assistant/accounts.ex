defmodule TeacherAssistant.Accounts do
  use Ash.Domain,
    otp_app: :teacher_assistant

  resources do
    resource TeacherAssistant.Accounts.Token
    resource TeacherAssistant.Accounts.User
    resource TeacherAssistant.Accounts.UserSchool
    resource TeacherAssistant.Accounts.SchoolInvitation
  end
end
