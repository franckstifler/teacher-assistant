defmodule TeacherAssistant.ModulesTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Modules
  alias TeacherAssistantWeb.School

  test "six keys, labelled" do
    assert Modules.keys() == [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]
    for key <- Modules.keys(), do: assert(is_binary(Modules.label(key)))
  end

  test "views and controller actions map to their module or the core" do
    assert Modules.module_for_view(School.BulletinsLive) == :notes
    assert Modules.module_for_view(School.AbsencesLive) == :appel
    assert Modules.module_for_view(School.SanctionsLive) == :discipline
    assert Modules.module_for_view(School.TimetableEditorLive) == :emploi_du_temps
    assert Modules.module_for_view(School.FeesLive) == :frais
    assert Modules.module_for_view(School.ClassPhotosLive) == :photos
    assert Modules.module_for_view(School.ClassesLive) == :core
    assert Modules.module_for_view(TeacherAssistantWeb.Admin.SchoolsLive) == nil

    assert Modules.module_for_controller(TeacherAssistantWeb.CardPrintController, :show) ==
             :photos

    assert Modules.module_for_controller(TeacherAssistantWeb.StudentPhotoController, :frozen) ==
             :notes

    assert Modules.module_for_controller(TeacherAssistantWeb.StudentPhotoController, :show) ==
             :core
  end

  test "the new-school default is read from config" do
    assert Modules.new_school_default() ==
             Application.fetch_env!(:teacher_assistant, :new_school_modules)
  end
end
