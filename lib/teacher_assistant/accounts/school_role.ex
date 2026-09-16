defmodule TeacherAssistant.Accounts.SchoolRole do
  use Ash.Type.Enum,
    values: [
      :head,
      :vice_principal,
      :discipline_master,
      :bursar,
      :hod,
      :form_master,
      :teacher,
      :guidance_counsellor,
      :librarian
    ]
end
