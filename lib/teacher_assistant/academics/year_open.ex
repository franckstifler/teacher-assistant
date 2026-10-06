defmodule TeacherAssistant.Academics.YearOpen do
  @moduledoc """
  Spec KLM9: nothing of a closed school year is created, changed or deleted — by anyone.
  Each year-bound resource names the `path` of `belongs_to` relationships from itself to
  a record carrying `academic_year_id` (`[]`: the record carries it; on `AcademicYear`
  itself, the record is the year). The written value and the stored one are both
  checked, so a record cannot be moved into or out of a closed year either. Internal
  reads (`authorize?: false`): the check must see the year whatever the actor may read.

  No compile-time reference to `AcademicYear` (no struct pattern): that resource uses
  this validation, so a struct pattern here would deadlock compilation.
  """
  use Ash.Resource.Validation

  require Ash.Query

  alias TeacherAssistant.Academics.AcademicYear

  @impl true
  def init(opts) do
    case opts[:path] do
      path when is_list(path) ->
        if Enum.all?(path, &is_atom/1), do: {:ok, opts}, else: {:error, "YearOpen: bad path"}

      _ ->
        {:error, "YearOpen needs `path:`, a list of belongs_to relationship names"}
    end
  end

  @impl true
  def validate(changeset, opts, _context),
    do: changeset |> year_ids(opts[:path]) |> check(changeset.tenant)

  # A single-record update or destroy carries its record, so the check runs now. A
  # query-based (bulk atomic) write has no record to follow: it must run row by row.
  @impl true
  def atomic(changeset, opts, _context) do
    case year_ids(changeset, opts[:path]) do
      [] ->
        if match?(%{__meta__: %{state: :loaded}}, changeset.data),
          do: :ok,
          else: {:not_atomic, "YearOpen reads each record's year"}

      ids ->
        check(ids, changeset.tenant)
    end
  end

  @doc "The refusal for a write touching the closed year `name`."
  def message(name), do: "L'année #{name} est clôturée."

  # A lookup that errors (a database error, no tenant) refuses the write: a lock that
  # cannot read the year must not let the write through. A parent that does not exist
  # (`{:ok, nil}`) passes — its foreign key rejects the write anyway.
  defp check({:error, _} = error, _tenant), do: error

  defp check(year_ids, tenant), do: Enum.find_value(year_ids, :ok, &closed_error(&1, tenant))

  defp year_ids(%{resource: AcademicYear, data: %{id: id}}, []) when is_binary(id), do: [id]
  defp year_ids(%{resource: AcademicYear}, []), do: []
  defp year_ids(changeset, []), do: values(changeset, :academic_year_id)

  defp year_ids(changeset, [first | rest]) do
    rel = Ash.Resource.Info.relationship(changeset.resource, first)

    changeset
    |> values(rel.source_attribute)
    |> Enum.map(&parent_year_id(rel.destination, &1, rest, changeset.tenant))
    |> collect()
  end

  defp collect(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> results |> Enum.filter(&is_binary/1) |> Enum.uniq()
      error -> error
    end
  end

  defp parent_year_id(resource, id, rest, tenant) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.load(nested(rest))
    |> Ash.read_one(tenant: tenant, authorize?: false)
    |> case do
      {:ok, %{} = record} ->
        rest |> Enum.reduce(record, &(&2 && Map.get(&2, &1))) |> year_of()

      {:ok, nil} ->
        nil

      {:error, _} ->
        unreadable()
    end
  end

  defp year_of(%{academic_year_id: id}), do: id
  defp year_of(_record), do: nil

  defp nested([]), do: []
  defp nested([rel]), do: [rel]
  defp nested([rel | rest]), do: [{rel, nested(rest)}]

  defp values(changeset, field) do
    [Ash.Changeset.get_attribute(changeset, field), Map.get(changeset.data, field)]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp closed_error(year_id, tenant) do
    case Ash.get(AcademicYear, year_id, tenant: tenant, authorize?: false) do
      {:ok, %{status: :closed, name: name}} ->
        {:error, field: :academic_year_id, message: message(name)}

      {:ok, _open} ->
        nil

      {:error, _} ->
        unreadable()
    end
  end

  defp unreadable,
    do: {:error, field: :academic_year_id, message: "Impossible de vérifier l'année scolaire."}
end
