use Mix.Config

config :spew, :appliance,
  config: [{"priv/dev.config", Spew.Appliance.ConfigParser}]

config :spew, :discovery,
  opts: [
    port: 7070,
    ip: {172,20,0,1}
  ],
  schema: :http

