# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :advisor_agent,
  ecto_repos: [AdvisorAgent.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :advisor_agent, AdvisorAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AdvisorAgentWeb.ErrorHTML, json: AdvisorAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AdvisorAgent.PubSub,
  live_view: [signing_salt: "cLjHDRtF"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  advisor_agent: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  advisor_agent: [
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

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.

config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [
      client_id: System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
      default_scope: "email profile https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events",
      redirect_uri: "http://localhost:4000/auth/google/callback"
    ]},
    hubspot: {Ueberauth.Strategy.Hubspot, [
      client_id: System.get_env("HUBSPOT_CLIENT_ID"),
      client_secret: System.get_env("HUBSPOT_CLIENT_SECRET"),
      scope: "crm.objects.contacts.read crm.objects.contacts.write oauth"
    ]}
  ]

config :ueberauth, Ueberauth.Strategy.Hubspot.OAuth,
  client_id: System.get_env("HUBSPOT_CLIENT_ID"),
  client_secret: System.get_env("HUBSPOT_CLIENT_SECRET")

config :ueberauth_hubspot,
  base_api_url: "https://api.hubapi.com"

import_config "#{config_env()}.exs"
