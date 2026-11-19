defmodule TeacherAssistantWeb.School.MemberAccount do
  @moduledoc """
  What a staff manager sees of colleagues' accounts, shared by the Membres list and
  the member page: which accounts the school may reset or rename, each account's
  state (« Mot de passe temporaire », « Compte lié »…) and the temporary-password
  message given after creating or resetting an account.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Dates

  @doc """
  The account rights and states for `members`. Only staff managers (`manager?`) see
  colleagues' password state; others get empty sets and no states.
  """
  def access(_scope, _members, false),
    do: %{resettable: MapSet.new(), renamable: MapSet.new(), states: %{}}

  def access(scope, members, true) do
    resettable = Accounts.resettable_member_ids(scope, members)
    workspace_id = scope.current_workspace.id

    %{
      resettable: resettable,
      renamable: Accounts.renamable_member_ids(scope, members),
      states:
        Map.new(members, fn m ->
          {m.id,
           account_status(
             m.user,
             m.roles,
             workspace_id,
             MapSet.member?(resettable, m.id),
             scope.current_user.id
           )}
        end)
    }
  end

  @doc "The dialog shown after creating (`:created`) or resetting (`:reset`) an account."
  def temporary_password_info(scope, %User{} = user, password, kind) do
    login = User.contact(user)

    %{
      kind: kind,
      name: User.display_name(user),
      login: login,
      value: password,
      expires_on: expiry_date(user),
      message:
        gettext(
          "%{school} — connexion : numéro %{login}, mot de passe temporaire %{password} (valable 7 jours).",
          school: scope.current_workspace.name,
          login: login,
          password: password
        )
    }
  end

  # An account this school created that still cannot be reset, and that is neither
  # an operator's, the viewer's own nor another head's (operator console spec §3),
  # is one the person also uses in another school (see `Checks.ActiveInAnotherSchool`).
  defp account_status(%User{} = user, roles, workspace_id, resettable?, viewer_id) do
    cond do
      user.created_in_workspace_id == workspace_id and not resettable? and user.role != :admin and
        user.id != viewer_id and :head not in roles ->
        %{
          created_here_status(user)
          | note:
              gettext(
                "Ce compte est aussi utilisé dans un autre établissement : la personne doit réinitialiser son mot de passe par e-mail ou demander à un administrateur."
              )
        }

      user.created_in_workspace_id == workspace_id ->
        created_here_status(user)

      # An invited account the head has reset (operator console spec §3).
      is_nil(user.created_in_workspace_id) and user.must_change_password ->
        created_here_status(user)

      user.phone && user.created_in_workspace_id ->
        %{
          kind: :linked,
          label: gettext("Compte lié"),
          note: gettext("Créé par un autre établissement")
        }

      resettable? ->
        %{kind: :active, label: gettext("Actif"), note: gettext("Compte personnel")}

      true ->
        %{
          kind: :active,
          label: gettext("Actif"),
          note: gettext("Mot de passe géré par la personne")
        }
    end
  end

  defp created_here_status(user) do
    cond do
      Accounts.temporary_password_expired?(user) ->
        %{
          kind: :expired,
          label: gettext("Mot de passe expiré"),
          note: gettext("Expiré — donnez-en un nouveau")
        }

      user.must_change_password ->
        %{
          kind: :pending,
          label: gettext("Mot de passe temporaire"),
          note:
            gettext("Pas encore connecté·e · expire le %{date}",
              date: Dates.day_month(expiry_date(user))
            )
        }

      true ->
        %{
          kind: :active,
          label: gettext("Actif"),
          note: gettext("Compte créé par l'établissement")
        }
    end
  end

  defp expiry_date(%User{temporary_password_expires_at: %DateTime{} = at}),
    do: DateTime.to_date(at)

  defp expiry_date(_user), do: Date.add(Reference.today(), 7)
end
