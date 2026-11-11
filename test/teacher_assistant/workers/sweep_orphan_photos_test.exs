defmodule TeacherAssistant.Workers.SweepOrphanPhotosTest do
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  alias TeacherAssistant.Accounts.AuditEvent
  alias TeacherAssistant.Workers.SweepOrphanPhotos

  require Ash.Query

  test "the weekly job sweeps and journals its counts, which the digest reads" do
    root = Path.join(System.tmp_dir!(), "sweep-job-#{System.unique_integer([:positive])}")
    orphan = Path.join([root, "student_photos", Ash.UUIDv7.generate(), "x.jpg"])
    File.mkdir_p!(Path.dirname(orphan))
    File.write!(orphan, "x")
    File.touch!(orphan, {{2020, 1, 1}, {0, 0, 0}})
    on_exit(fn -> File.rm_rf!(root) end)

    assert :ok = perform_job(SweepOrphanPhotos, %{"root" => root})
    refute File.exists?(orphan)

    assert [%{details: %{"deleted" => 1}}] =
             AuditEvent
             |> Ash.Query.filter(action == :files_swept)
             |> Ash.read!(authorize?: false)

    assert TeacherAssistant.Operator.digest().swept_files == 1
  end

  test "a refused sweep is journaled and the digest says it stopped (minors)" do
    root = Path.join(System.tmp_dir!(), "sweep-job-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    for _ <- 1..12 do
      orphan = Path.join([root, "student_photos", Ash.UUIDv7.generate(), "x.jpg"])
      File.mkdir_p!(Path.dirname(orphan))
      File.write!(orphan, "x")
      File.touch!(orphan, {{2020, 1, 1}, {0, 0, 0}})
    end

    assert :ok = perform_job(SweepOrphanPhotos, %{"root" => root})
    assert TeacherAssistant.Operator.digest().sweep_refused == true
  end
end
