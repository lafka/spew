use Mix.Config


config :spew, :spewroot, spewroot = "/tmp/spew"
config :spew, :buildpath, ["#{spewroot}/build", "~/.spew/builds"]
