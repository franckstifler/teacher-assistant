# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Modules a new school starts with (operator console spec §1): none; the operator enables them.
config :teacher_assistant, :new_school_modules, []

config :teacher_assistant, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: TeacherAssistant.Repo,
  plugins: [
    # UTC; school time is UTC+1.
    {Oban.Plugins.Cron,
     crontab: [
       {"30 11 * * 1-6", TeacherAssistant.Workers.MissedRollCalls, args: %{"half" => "morning"}},
       {"30 16 * * 1-6", TeacherAssistant.Workers.MissedRollCalls,
        args: %{"half" => "afternoon"}},
       # Monday 06:30 school time: paper roll-call sheets of past weeks not typed in.
       {"30 5 * * 1", TeacherAssistant.Workers.PaperSheetsOverdue},
       {"10 6 * * *", TeacherAssistant.Workers.ExpiredTemporaryPasswords},
       # 07:00 school time: the operators' morning message on Telegram, when set up.
       {"0 6 * * *", TeacherAssistant.Workers.TelegramDigest},
       # Sunday 04:00 school time (A9): students who left three years ago lose what
       # identifies them.
       {"0 3 * * 0", TeacherAssistant.Workers.AnonymiseDepartedStudents}
     ]}
  ]

# Unhandled errors, grouped into issues in this app's database and shown to the
# operator at /admin/errors (TeacherAssistant.ErrorReporting). The filter keeps
# no request or job data: these are records about minors.
config :error_tracker,
  repo: TeacherAssistant.Repo,
  otp_app: :teacher_assistant,
  filter: TeacherAssistant.ErrorReporting.Filter,
  # A resolved error and its occurrences are deleted 30 days later.
  plugins: [{ErrorTracker.Plugins.Pruner, max_age: :timer.hours(24 * 30)}]

config :ash,
  default_string_length_count: :codepoints,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :teacher_assistant,
  ecto_repos: [TeacherAssistant.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    TeacherAssistant.Accounts,
    TeacherAssistant.Organization,
    TeacherAssistant.Enrollment,
    TeacherAssistant.Curriculum,
    TeacherAssistant.Assessment,
    TeacherAssistant.Attendance,
    TeacherAssistant.Discipline,
    TeacherAssistant.Timetabling,
    TeacherAssistant.Fees
  ],
  uploads_dir: "priv/uploads"

# Configures the endpoint
config :teacher_assistant, TeacherAssistantWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TeacherAssistantWeb.ErrorHTML, json: TeacherAssistantWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TeacherAssistant.PubSub,
  live_view: [signing_salt: "kuZvqzTn"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :teacher_assistant, TeacherAssistant.Mailer, adapter: Swoosh.Adapters.Local

config :teacher_assistant, TeacherAssistant.Accounts.Emails,
  from: {"Scolaka", "no-reply@scolaka.com"}

# How a visitor reaches us from the landing. A missing or blank value hides its
# link. Production may override them with CONTACT_WHATSAPP and CONTACT_EMAIL.
config :teacher_assistant, :contact,
  whatsapp: "+237 678 28 42 65",
  email: "contact@scolaka.com"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  teacher_assistant: [
    args:
      ~w(js/app.js js/print.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  teacher_assistant: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :teacher_assistant, TeacherAssistantWeb.Gettext, locales: ~w(en fr), default_locale: "fr"

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
