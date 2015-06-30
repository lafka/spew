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
config :spew, :provision, [
  domain: "spew.tm",
  networks: %{
    "spew" => %{
      range: [
        "172.20.0.0/16#25",
        "fc00:3000:3::0/64#100"
      ]
    }
  }
]
