defmodule TeacherAssistant.Accounts.Checks.SchoolVerified do
  @moduledoc """
  Policy check: the subject's school has a `:verified` `SchoolProfile` — the
  "operate" gate on marks and attendance. The school is resolved like
  `TeacherAssistant.Accounts.Checks.SchoolRole`.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole
  alias TeacherAssistant.Accounts.SchoolProfile

  @impl true
  def describe(_opts), do: "the school is verified"

  @impl true
  def match?(_actor, %{subject: subject}, _opts), do: verified?(SchoolRole.workspace_id(subject))
  def match?(_actor, _context, _opts), do: false

  defp verified?(nil), do: false

  # Check-internal read: `authorize?: false`, see `Checks.SchoolRole`.
  defp verified?(workspace_id) do
    SchoolProfile
    |> Ash.Query.for_read(:for_workspace, %{workspace_id: workspace_id})
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{verification_status: :verified}} -> true
      _ -> false
    end
  end
end
