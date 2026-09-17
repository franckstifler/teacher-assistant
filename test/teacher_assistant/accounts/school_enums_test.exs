defmodule TeacherAssistant.Accounts.SchoolEnumsTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.{
    SchoolType,
    SchoolSubsystem,
    SchoolSector,
    CameroonRegion,
    SchoolVerificationStatus,
    SchoolTypes,
    SchoolSubsystems,
    SchoolSectors,
    CameroonRegions,
    SchoolVerificationStatuses
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

  test "every value has a non-empty label and all/0 covers the value set" do
    for {type, labels} <- [
          {SchoolType, SchoolTypes},
          {SchoolSubsystem, SchoolSubsystems},
          {SchoolSector, SchoolSectors},
          {CameroonRegion, CameroonRegions},
          {SchoolVerificationStatus, SchoolVerificationStatuses}
        ] do
      assert Enum.sort(labels.all()) == Enum.sort(type.values())
      for v <- type.values(), do: assert(is_binary(labels.label(v)) and labels.label(v) != "")
    end
  end
end
