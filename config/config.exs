use Mix.Config

config :rtfa, :appliance,
  config: "priv/appliances.config"

config :logger, :console,
  level: :info,
  format: "$date $time [$level] $metadata$message\n",
  metadata: []

if File.exists? "config/#{Mix.env}.exs" do
  import_config "#{Mix.env}.exs"
end
