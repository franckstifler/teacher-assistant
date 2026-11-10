defmodule TeacherAssistant.Academics.YearOpen do
  @moduledoc """
  Spec KLM9: nothing of a closed school year is created, changed or deleted — by anyone.
  Each year-bound resource names the `path` of `belongs_to` relationships from itself to
  a record carrying `academic_year_id` (`[]`: the record carries it; on `AcademicYear`
  itself, the record is the year). The written value and the stored one are both
  checked, so a record cannot be moved into or out of a closed year either. Internal
  reads (`authorize?: false`): the check must see the year whatever the actor may read.

  A change rather than a validation (spec audit follow-ups A2): a bulk write (the roll
  call, `Ash.bulk_create`) runs `batch_change/3` once per batch, so the parents and the
  years are read once for the whole batch instead of twice per row.

  No compile-time reference to `AcademicYear` (no struct pattern): that resource uses
  this change, so a struct pattern here would deadlock compilation.
  """
  use Ash.Resource.Change

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
  def batch_callbacks?(_changesets, _opts, _context), do: true

  @impl true
  def change(changeset, opts, context) do
    [changeset] = batch_change([changeset], opts, context)
    changeset
  end

  @impl true
  def batch_change(changesets, opts, _context) do
    path = opts[:path]

    # Every changeset of a batch shares one tenant; group all the same, so a mixed
    # batch is still checked against the right school.
    changesets
    |> Enum.group_by(& &1.tenant)
    |> Enum.flat_map(fn {tenant, group} -> check_group(group, path, tenant) end)
  end

  # A single-record update or destroy carries its record, so the check runs now. A
  # query-based (bulk atomic) write has no record to follow: it must run row by row.
  @impl true
  def atomic(changeset, opts, _context) do
    case year_ids(changeset, opts[:path], changeset.tenant) do
      [] ->
        if match?(%{__meta__: %{state: :loaded}}, changeset.data),
          do: :ok,
          else: {:not_atomic, "YearOpen reads each record's year"}

      {:error, _} = error ->
        error

      ids ->
        case closed_years(ids, changeset.tenant) do
          {:error, _} = error -> error
          closed -> if closed == %{}, do: :ok, else: {:error, closed_error(hd(ids), closed)}
        end
    end
  end

  @doc "The refusal for a write touching the closed year `name`."
  def message(name), do: "L'année #{name} est clôturée."

  # --- batch -----------------------------------------------------------------

  defp check_group(changesets, path, tenant) do
    with {:ok, years_by_changeset} <- resolve_years(changesets, path, tenant),
         closed when is_map(closed) <-
           years_by_changeset |> Enum.flat_map(fn {_cs, ids} -> ids end) |> closed_years(tenant) do
      Enum.map(years_by_changeset, fn {changeset, ids} ->
        case Enum.find(ids, &Map.has_key?(closed, &1)) do
          nil -> changeset
          id -> Ash.Changeset.add_error(changeset, closed_error(id, closed))
        end
      end)
    else
      {:error, error} -> Enum.map(changesets, &Ash.Changeset.add_error(&1, error))
    end
  end

  # `[{changeset, [year_id]}]` for the batch: the year ids are read from the records
  # directly (`path: []`), or through the parents at the head of `path`, read once
  # for every distinct parent id of the batch.
  defp resolve_years(changesets, [], _tenant),
    do: {:ok, Enum.map(changesets, &{&1, direct_year_ids(&1)})}

  defp resolve_years([first_cs | _] = changesets, [first | rest], tenant) do
    rel = Ash.Resource.Info.relationship(first_cs.resource, first)
    parent_ids = changesets |> Enum.flat_map(&values(&1, rel.source_attribute)) |> Enum.uniq()

    case parent_years(rel.destination, parent_ids, rest, tenant) do
      {:ok, year_by_parent} ->
        {:ok,
         Enum.map(changesets, fn changeset ->
           ids =
             changeset
             |> values(rel.source_attribute)
             |> Enum.map(&Map.get(year_by_parent, &1))
             |> Enum.filter(&is_binary/1)
             |> Enum.uniq()

           {changeset, ids}
         end)}

      {:error, _} = error ->
        error
    end
  end

  # A parent that does not exist is simply absent from the map — its foreign key
  # rejects the write anyway. A read that errors refuses the whole batch: a lock that
  # cannot read the year must not let the write through.
  defp parent_years(_resource, [], _rest, _tenant), do: {:ok, %{}}

  defp parent_years(resource, ids, rest, tenant) do
    resource
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.load(nested(rest))
    |> Ash.read(tenant: tenant, authorize?: false)
    |> case do
      {:ok, records} ->
        {:ok,
         Map.new(records, fn record ->
           {record.id, rest |> Enum.reduce(record, &(&2 && Map.get(&2, &1))) |> year_of()}
         end)}

      {:error, _} ->
        {:error, unreadable()}
    end
  end

  # `%{year_id => name}` of the closed years among `ids`, or `{:error, _}`.
  defp closed_years([], _tenant), do: %{}

  defp closed_years(ids, tenant) do
    AcademicYear
    |> Ash.Query.filter(id in ^Enum.uniq(ids))
    |> Ash.read(tenant: tenant, authorize?: false)
    |> case do
      {:ok, years} ->
        for %{id: id, status: :closed, name: name} <- years, into: %{}, do: {id, name}

      {:error, _} ->
        {:error, unreadable()}
    end
  end

  defp closed_error(id, closed), do: [field: :academic_year_id, message: message(closed[id])]

  # --- single changeset (atomic path) -----------------------------------------

  defp year_ids(changeset, [], _tenant), do: direct_year_ids(changeset)

  defp year_ids(changeset, [first | rest], tenant) do
    rel = Ash.Resource.Info.relationship(changeset.resource, first)

    case parent_years(rel.destination, values(changeset, rel.source_attribute), rest, tenant) do
      {:ok, by_parent} -> by_parent |> Map.values() |> Enum.filter(&is_binary/1) |> Enum.uniq()
      {:error, _} = error -> error
    end
  end

  defp direct_year_ids(%{resource: AcademicYear, data: %{id: id}}) when is_binary(id), do: [id]
  defp direct_year_ids(%{resource: AcademicYear}), do: []
  defp direct_year_ids(changeset), do: values(changeset, :academic_year_id)

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

  defp unreadable,
    do: [field: :academic_year_id, message: "Impossible de vérifier l'année scolaire."]
end
