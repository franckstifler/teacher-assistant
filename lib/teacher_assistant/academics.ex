defmodule TeacherAssistant.Academics do
  # Intentionally NOT registered in :ash_domains — its resources now live in
  # focused domains (Organization, Enrollment, Curriculum, Assessment,
  # Attendance, Discipline, Timetabling, Fees). Its former bulletin/results
  # trio (`class_subjects/2`, `class_results/2`, `class_results_for_period/2`)
  # moved onto the `Assessment` domain in task D2. This module now carries no
  # substantive logic and survives only as an (empty) Ash.Domain module pending
  # final cleanup (task C13), so skip the config-inclusion check.
  use Ash.Domain, otp_app: :teacher_assistant, validate_config_inclusion?: false

  resources do
  end
end
