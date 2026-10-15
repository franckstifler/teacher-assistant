defmodule TeacherAssistant.Modules do
  @moduledoc """
  The switchable parts of the product (operator console spec §1): which LiveViews and
  controller actions each module owns. Everything listed under `@core` is always on.
  This map is the single source for the route guard, the controller plug, the menus
  and the router coverage test.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistantWeb, as: W

  @keys [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]

  @views %{
    notes: [
      W.Teacher.RosterLive,
      W.Teacher.MarksLive,
      W.Teacher.MarksSummaryLive,
      W.School.ResultsLive,
      W.School.BulletinLive,
      W.School.BulletinsLive,
      W.School.CouncilsLive,
      W.School.CouncilLive,
      W.School.CorrectionsLive,
      W.School.CorrectionReviewLive,
      W.School.SequenceTrackingLive,
      W.School.EvaluationsLive,
      W.School.CoefficientsLive,
      W.School.AppreciationsLive,
      W.School.PassageLive,
      W.School.BulletinTemplateLive
    ],
    appel: [
      W.School.MyDayLive,
      W.School.AttendanceLive,
      W.School.RegisterLive,
      W.School.DayLive,
      W.School.AbsencesLive
    ],
    discipline: [
      W.School.DisciplineLive,
      W.School.ConductLive,
      W.School.SanctionsLive,
      W.School.SchoolLifeSettingsLive
    ],
    emploi_du_temps: [
      W.School.TimetableLive,
      W.School.TimetableEditorLive,
      W.School.MyTimetableLive
    ],
    frais: [W.School.FeesLive],
    photos: [W.School.ClassPhotosLive]
  }

  @controllers %{
    {W.BulletinPrintController, :show} => :notes,
    {W.BulletinPrintController, :class} => :notes,
    {W.CouncilPrintController, :show} => :notes,
    {W.StudentPhotoController, :frozen} => :notes,
    {W.TimetablePrintController, :class} => :emploi_du_temps,
    {W.TimetablePrintController, :me} => :emploi_du_temps,
    {W.CardPrintController, :show} => :photos,
    {W.StudentPhotoController, :show} => :core,
    {W.SchoolLogoController, :show} => :core
  }

  @core [
    W.School.DashboardLive,
    W.School.CoursesLive,
    W.School.ClassesLive,
    W.School.ClassLive,
    W.School.TeachingsLive,
    W.School.StudentsLive,
    W.School.StudentLive,
    W.School.EnrollImportLive,
    W.School.MembersLive,
    W.School.SettingsLive,
    W.School.OfficialHeaderLive,
    W.School.RolesLive,
    W.School.NewYearLive,
    W.School.YearLive,
    W.School.HolidaysLive,
    W.School.AssignmentsLive,
    W.School.PeriodsLive,
    W.School.NotificationsLive,
    W.School.SuspendedLive,
    W.Onboarding.SetupWizardLive
  ]

  @by_view for {key, views} <- @views, view <- views, into: %{}, do: {view, key}

  def keys, do: @keys

  def label(:notes), do: gettext("Notes et bulletins")
  def label(:appel), do: gettext("Appel et absences")
  def label(:discipline), do: gettext("Discipline")
  def label(:emploi_du_temps), do: gettext("Emploi du temps")
  def label(:frais), do: gettext("Frais de scolarité")
  def label(:photos), do: gettext("Photos et cartes")

  @doc "The module a LiveView belongs to, `:core`, or nil when it is not a school screen."
  def module_for_view(view) do
    cond do
      key = @by_view[view] -> key
      view in @core -> :core
      true -> nil
    end
  end

  @doc "The module a school controller action belongs to, `:core`, or nil."
  def module_for_controller(controller, action), do: @controllers[{controller, action}]

  @doc "Modules a newly created school starts with (config `:new_school_modules`)."
  def new_school_default, do: Application.fetch_env!(:teacher_assistant, :new_school_modules)
end
