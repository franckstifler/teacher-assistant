defmodule TeacherAssistant.RuntimeMailConfigTest do
  @moduledoc "Production email goes through Brevo, with the sender taken from the environment."
  # Changes process-wide environment variables.
  use ExUnit.Case, async: false

  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @base %{
    "DATABASE_URL" => "ecto://u:p@localhost/db",
    "SECRET_KEY_BASE" => String.duplicate("s", 64),
    "TOKEN_SIGNING_SECRET" => "t"
  }
  @mail_vars ~w(BREVO_API_KEY MAIL_FROM_ADDRESS MAIL_FROM_NAME)

  setup do
    saved = Map.new(Map.keys(@base) ++ @mail_vars, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end)

    System.put_env(@base)
    Enum.each(@mail_vars, &System.delete_env/1)
    :ok
  end

  defp prod_config, do: Config.Reader.read!(@runtime, env: :prod, target: :host)

  test "the Brevo adapter with the key from BREVO_API_KEY" do
    System.put_env("BREVO_API_KEY", "xkeysib-test")
    mailer = prod_config()[:teacher_assistant][TeacherAssistant.Mailer]
    assert mailer[:adapter] == Swoosh.Adapters.Brevo
    assert mailer[:api_key] == "xkeysib-test"
  end

  test "production refuses to start without BREVO_API_KEY" do
    assert_raise RuntimeError, ~r/BREVO_API_KEY/, fn -> prod_config() end
  end

  test "the sender comes from MAIL_FROM_NAME and MAIL_FROM_ADDRESS" do
    System.put_env(%{
      "BREVO_API_KEY" => "k",
      "MAIL_FROM_ADDRESS" => "ecole@exemple.cm",
      "MAIL_FROM_NAME" => "Lycée X"
    })

    emails = prod_config()[:teacher_assistant][TeacherAssistant.Accounts.Emails]
    assert emails[:from] == {"Lycée X", "ecole@exemple.cm"}
  end

  test "without them the sender keeps its default" do
    System.put_env("BREVO_API_KEY", "k")
    refute prod_config()[:teacher_assistant][TeacherAssistant.Accounts.Emails]
  end
end
