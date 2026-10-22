defmodule TeacherAssistant.Accounts.User.Preparations.ThrottleSignIn do
  @moduledoc """
  Caps password guessing on one account: after 10 failed sign-ins in a row
  within 15 minutes, the identity (email or phone) is refused — before the
  password is even checked — until the window ends. A successful sign-in
  clears the count. Goes after `SignInPreparation` so its success hook runs
  only once the password was accepted.
  """
  use Ash.Resource.Preparation

  alias AshAuthentication.Errors.AuthenticationFailed
  alias TeacherAssistant.RateLimit

  @limit 10
  @scale :timer.minutes(15)

  @impl true
  def prepare(query, opts, _context) do
    case Ash.Query.get_argument(query, Keyword.fetch!(opts, :identity)) do
      nil ->
        query

      identity ->
        key = "sign_in:" <> (identity |> to_string() |> String.downcase())

        query
        |> Ash.Query.before_action(fn query ->
          if RateLimit.allow?(key, @limit, @scale),
            do: query,
            else: Ash.Query.add_error(query, throttled(query))
        end)
        |> Ash.Query.after_action(fn _query, results ->
          RateLimit.set(key, @scale, 0)
          {:ok, results}
        end)
    end
  end

  @doc "Whether a sign-in error is this refusal (the page says to wait, not to retype)."
  def throttled?(%AuthenticationFailed{caused_by: %{module: __MODULE__}}), do: true
  def throttled?(%{caused_by: cause}) when not is_nil(cause), do: throttled?(cause)
  def throttled?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &throttled?/1)
  def throttled?(_error), do: false

  defp throttled(query) do
    AuthenticationFailed.exception(
      query: query,
      caused_by: %{module: __MODULE__, action: :sign_in, message: "Too many sign-in attempts"}
    )
  end
end
