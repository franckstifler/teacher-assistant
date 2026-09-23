# Teacher-personal surfaces are paused (see docs/audits/2026-09-23-school-focus/README.md §6).
# Their web tests stay in the repo and run with: mix test --include teacher_personal
ExUnit.start(exclude: [:teacher_personal])
Ecto.Adapters.SQL.Sandbox.mode(TeacherAssistant.Repo, :manual)
