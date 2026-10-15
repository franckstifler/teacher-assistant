defmodule TeacherAssistant.Modules.Key do
  @moduledoc "The switchable modules of a school (operator console spec §1)."
  use Ash.Type.Enum, values: [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]
end
