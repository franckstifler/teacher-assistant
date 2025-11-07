defmodule TeacherAssistant.Academics do
  use Ash.Domain

  resources do
    resource TeacherAssistant.Academics.School
    resource TeacherAssistant.Academics.Classroom

    resource TeacherAssistant.Academics.Level do
      define :create_level, action: :create
      define :update_level, action: :update
      define :read_levels, action: :read
      define :destroy_level, action: :destroy
    end

    resource TeacherAssistant.Academics.LevelOption
    resource TeacherAssistant.Academics.LevelOptionSubject

    resource TeacherAssistant.Academics.Option do
      define :create_option, action: :create
      define :update_option, action: :update
      define :read_options, action: :read
      define :destroy_option, action: :destroy
    end

    resource TeacherAssistant.Academics.Sequence
    resource TeacherAssistant.Academics.ClassroomStudent
    resource TeacherAssistant.Academics.Student
    resource TeacherAssistant.Academics.Subject

    resource TeacherAssistant.Academics.Term do
      define :create_term, action: :create
      define :update_term, action: :update
      define :read_terms, action: :read
      define :destroy_term, action: :destroy
    end

    resource TeacherAssistant.Academics.AcademicYear do
      define :create_academic_year, action: :create
      define :update_academic_year, action: :update
      define :read_academic_years, action: :read
      define :destroy_academic_year, action: :destroy
    end
  end
end
