defmodule TeacherAssistant.Accounts.SchoolEnumsTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.{
    SchoolType,
    SchoolSubsystem,
    SchoolSector,
    CameroonRegion,
    SchoolVerificationStatus
  }

  test "enum value sets" do
    assert :bilingual in SchoolSubsystem.values()
    assert :francophone in SchoolSubsystem.values()
    assert :private_confessional in SchoolSector.values()
    assert :northwest in CameroonRegion.values()
    assert length(CameroonRegion.values()) == 10
    assert :gbhs in SchoolType.values()
    assert Enum.sort(SchoolVerificationStatus.values()) == [:rejected, :unverified, :verified]
  end

  test "every value has a non-empty label" do
    for type <- [
          SchoolType,
          SchoolSubsystem,
          SchoolSector,
          CameroonRegion,
          SchoolVerificationStatus
        ] do
      for v <- type.values(), do: assert(is_binary(type.label(v)) and type.label(v) != "")
    end
  end
end
