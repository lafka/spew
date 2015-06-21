use Mix.Config


config :spew, :spewroot, spewroot = "/tmp/spew"
config :spew, :buildpath, ["#{spewroot}/build", "~/.spew/builds"]
config :spew, :appliancepaths, []

import_config "#{Mix.env}.exs"
