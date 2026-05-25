defmodule TeacherAssistant.Academics do
  use Ash.Domain

  resources do
    resource TeacherAssistant.Academics.School

    resource TeacherAssistant.Academics.Classroom do
      define :list_teacher_classrooms,
        action: :list_teacher_classrooms,
        args: [:academic_year_id, :teacher_id]
    end

    resource TeacherAssistant.Academics.Level do
      define :create_level, action: :create
      define :update_level, action: :update
      define :read_levels, action: :read
      define :destroy_level, action: :destroy
    end

    resource TeacherAssistant.Academics.LevelOption do
      define :read_levels_level_options, action: :read
      define :manage_level_option_subjects, action: :manage_subjects
      define :destroy_level_option, action: :destroy
    end

    resource TeacherAssistant.Academics.LevelOptionSubject
    resource TeacherAssistant.Academics.SequenceSubjectObjective

    resource TeacherAssistant.Academics.Option do
      define :create_option, action: :create
      define :update_option, action: :update
      define :read_options, action: :read
      define :destroy_option, action: :destroy
    end

    resource TeacherAssistant.Academics.Sequence
    resource TeacherAssistant.Academics.ClassroomStudent
    resource TeacherAssistant.Academics.TeachingAssignment

    resource TeacherAssistant.Academics.Student do
      define :create_student, action: :create
      define :update_student, action: :update
      define :read_students, action: :read
      define :destroy_student, action: :destroy

      define :list_students_by_classroom,
        action: :list_students_by_classroom,
        args: [:classroom_id]
    end

    resource TeacherAssistant.Academics.Subject do
      define :create_subject, action: :create
      define :update_subject, action: :update
      define :read_subjects, action: :read
      define :destroy_subject, action: :destroy
      define :list_teacher_subjects, action: :list_teacher_subjects, args: [:year_id]
    end

    resource TeacherAssistant.Academics.Mark do
      define :save_mark, action: :create
      define :read_marks, action: :read
      define :destroy_mark, action: :destroy
    end

    resource TeacherAssistant.Academics.Attendance do
      define :create_attendance, action: :create
      define :update_attendance, action: :update
      define :read_attendances, action: :read
      define :destroy_attendance, action: :destroy
    end

    resource TeacherAssistant.Academics.GradeInterval
    resource TeacherAssistant.Academics.ProgressionPlan
    resource TeacherAssistant.Academics.ProgressionEntry
    resource TeacherAssistant.Academics.TeachingLog
    resource TeacherAssistant.Academics.ApcLessonPlan

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
      define :manage_classrooms, action: :manage_classrooms
    end
  end
end
