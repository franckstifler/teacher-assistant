defmodule TeacherAssistant.Curriculum do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.Subject
    resource TeacherAssistant.Academics.TeachingContext
    resource TeacherAssistant.Academics.CombinedCourse
    resource TeacherAssistant.Academics.ProgressionPlan
    resource TeacherAssistant.Academics.ProgressionEntry
    resource TeacherAssistant.Academics.ProgressionModule
    resource TeacherAssistant.Academics.TeachingLogEntry
    resource TeacherAssistant.Academics.LessonPlan
    resource TeacherAssistant.Academics.LessonStep
  end
end
