use Mix.Config

config :spew, :appliance,
  config: [{"priv/dev.config", Spew.Appliance.ConfigParser}]

config :logger, :console,
  level: :debug,
  format: "$date $time [$level] $metadata$message\n",
  metadata: []

if File.exists? "config/#{Mix.env}.exs" do
  import_config "#{Mix.env}.exs"
end
