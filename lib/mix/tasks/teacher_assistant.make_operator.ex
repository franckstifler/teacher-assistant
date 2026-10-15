defmodule Mix.Tasks.TeacherAssistant.MakeOperator do
  @shortdoc "Gives a user the platform operator role"
  @moduledoc """
      mix teacher_assistant.make_operator someone@example.com
      mix teacher_assistant.make_operator "6 77 12 34 56"

  An admin task (operator console spec §5): finds the user by e-mail or phone and
  runs `User :promote_to_admin` without an actor.
  """
  use Mix.Task

  require Ash.Query

  alias TeacherAssistant.Accounts.{Phone, User}

  @requirements ["app.start"]

  @impl Mix.Task
  def run([identifier]) do
    with %User{} = user <- find(String.trim(identifier)),
         {:ok, user} <-
           user
           |> Ash.Changeset.for_update(:promote_to_admin, %{})
           |> Ash.update(authorize?: false) do
      Mix.shell().info("#{User.display_name(user)} est maintenant opérateur.")
    else
      _ -> Mix.raise("Aucun utilisateur pour #{identifier}")
    end
  end

  def run(_args), do: Mix.raise("Usage : mix teacher_assistant.make_operator <e-mail|téléphone>")

  defp find(identifier) do
    query =
      case Phone.normalize(identifier) do
        {:ok, phone} -> Ash.Query.filter(User, phone == ^phone)
        _ -> Ash.Query.filter(User, email == ^identifier)
      end

    Ash.read_one!(query, authorize?: false)
  end
end
