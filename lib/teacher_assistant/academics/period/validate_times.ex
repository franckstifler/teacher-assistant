defmodule TeacherAssistant.Academics.Period.ValidateTimes do
  @moduledoc "Spec J1 (S03): a period ends after it starts and overlaps no other period of the school."
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.Period

  @impl true
  def validate(changeset, _opts, _context) do
    s = Ash.Changeset.get_attribute(changeset, :start_time)
    e = Ash.Changeset.get_attribute(changeset, :end_time)

    cond do
      is_nil(s) or is_nil(e) ->
        :ok

      Time.compare(e, s) != :gt ->
        {:error, field: :end_time, message: gettext("La période doit finir après son début.")}

      other = overlapping(changeset, s, e) ->
        {:error,
         field: :start_time,
         message:
           gettext("Chevauche %{label} (%{start}–%{end}).",
             label: other.label,
             start: hm(other.start_time),
             end: hm(other.end_time)
           )}

      true ->
        :ok
    end
  end

  defp overlapping(changeset, s, e) do
    id = changeset.data.id
    tenant = changeset.tenant || Ash.Changeset.get_attribute(changeset, :workspace_id)

    Period
    |> Ash.Query.set_tenant(tenant)
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn p ->
      p.id != id and Time.compare(s, p.end_time) == :lt and Time.compare(p.start_time, e) == :lt
    end)
  end

  defp hm(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
end
