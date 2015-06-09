use Mix.Config

config :spew, :appliance,
  config: [{"priv/dev.config", Spew.Appliance.ConfigParser}],
  statedir: "/tmp/spew"

config :spew, :discovery,
  opts: [port: 80],
  schema: :http

config :logger, :console,
  level: :debug,
  format: "$date $time [$level] $metadata$message\n",
  metadata: []

if File.exists? "config/#{Mix.env}.exs" do
  import_config "#{Mix.env}.exs"
end
