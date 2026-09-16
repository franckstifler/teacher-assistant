defmodule TeacherAssistant.Academics.ModuleGrouping do
  @moduledoc "Pure grouping of legacy string modules into ordered module buckets."

  def group(entries) do
    entries
    |> Enum.sort_by(& &1.position)
    |> Enum.reduce({[], %{}}, fn e, {order, acc} ->
      key = normalize(Map.get(e, :module))
      order = if Map.has_key?(acc, key), do: order, else: [key | order]
      acc = Map.update(acc, key, [e.id], &[e.id | &1])
      {order, acc}
    end)
    |> then(fn {order, acc} ->
      order
      |> Enum.reverse()
      |> Enum.map(fn key -> %{key: key, entry_ids: Enum.reverse(acc[key])} end)
    end)
  end

  defp normalize(nil), do: :default
  defp normalize(s) when is_binary(s), do: if(String.trim(s) == "", do: :default, else: s)
end
