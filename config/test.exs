use Mix.Config

config :spew, :appliance,
  config: []

config :spew, :discovery,
  opts: [
    port: 7071,
    ip: {172, 20, 0, 1}
  ],
  schema: :http


config :logger, :console, level: :debug
