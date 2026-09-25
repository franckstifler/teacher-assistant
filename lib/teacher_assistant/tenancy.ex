defmodule TeacherAssistant.Tenancy do
  @moduledoc """
  Read-side tenant guard for the two `global? true` resources
  (`SchoolMembership`, `SchoolInvitation`): Ash lets every action of a global
  resource run without a tenant, so a tenant-scoped read on one must refuse a
  missing tenant explicitly or it silently spans every school. (Writes are
  tenant-safe at the database: every tenant-to-tenant reference is a composite
  foreign key on `(x_id, workspace_id)`.)
  """

  @doc """
  `Ash.Query.before_action/2` hook: adds `Ash.Error.Invalid.TenantRequired`
  to `query` when no tenant is set.

  Registered from a read action's `prepare` as
  `prepare fn q, _ -> Ash.Query.before_action(q, &Tenancy.require_tenant/1) end`
  rather than run inline: callers set the tenant with a separate
  `Ash.Query.set_tenant/2` *after* `for_read/3` returns, and a plain `prepare`
  runs inside `for_read/3`, before that call, so it would always see `nil`.
  """
  def require_tenant(%Ash.Query{tenant: nil} = query) do
    Ash.Query.add_error(
      query,
      Ash.Error.Invalid.TenantRequired.exception(resource: query.resource)
    )
  end

  def require_tenant(%Ash.Query{} = query), do: query
end
