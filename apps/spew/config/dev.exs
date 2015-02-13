use Mix.Config

config :spew, :appliancepaths, [
  Path.join([System.cwd, "priv", "appliances"]),
  "/data/spew/appliances"
]

config :spew, :buildpath, [
  Path.join([System.cwd, "priv", "builds"]),
  "#{Application.get_env(:spew, :spewroot)}/build",
  "~/.spew/builds"
]
