import Config

config :teacher_assistant, uploads_dir: Path.join(System.tmp_dir!(), "ta_test_uploads")

config :bcrypt_elixir, log_rounds: 1
config :teacher_assistant, Oban, testing: :manual

# Never the real Telegram API: tests set a token and stub the requests.
config :teacher_assistant, TeacherAssistant.Telegram,
  req_options: [plug: {Req.Test, TeacherAssistant.Telegram}]

# Off, so a test that makes a page crash writes nothing; ErrorReportingTest turns it on.
config :error_tracker, enabled: false, plugins: []
config :teacher_assistant, token_signing_secret: "stzKJzc4mx3IO7M9Pw+9nK9sEIlPXcOa"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# The marks lock's clock (`Reference.today/0`) is frozen early in the fixtures'
# 2025-2026 year, so their séquences stay open unless a test locks one.
config :teacher_assistant, school_clock_now: ~U[2025-09-15 12:00:00Z]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :teacher_assistant, TeacherAssistant.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "teacher_assistant_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :teacher_assistant, TeacherAssistantWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "VWFiKZqWdrCg1O/aWaTBzCVFq1fHxjuJ+kOsSMhCiBNgJxZ5SS/RsNdIc7tbDfKS",
  server: false

# In test we don't send emails
config :teacher_assistant, TeacherAssistant.Mailer, adapter: TeacherAssistant.TestMailerAdapter

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Tests create schools directly and use every screen (operator console spec §1).
config :teacher_assistant, :new_school_modules, [
  :notes,
  :appel,
  :discipline,
  :emploi_du_temps,
  :frais,
  :photos
]
