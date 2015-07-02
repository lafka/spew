use Mix.Config


config :spew, :spewroot, spewroot = "/tmp/spew"
config :spew, :buildpath, ["#{spewroot}/build", "~/.spew/builds"]
config :spew, :appliancepaths, []
config :spew, :provision, [
  domain: "spew.tm",
  networks: %{
    "spew" => %{
      range: [
        "172.24.0.0/13#25",
        "fc00:2000:2::0/64#100"
      ]
    }
  },
  hosts: "/etc/spew/allocations.ex"
]


import_config "#{Mix.env}.exs"
