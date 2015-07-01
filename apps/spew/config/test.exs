use Mix.Config

config :spew, :appliancepaths, ["./test/appliances"]
config :spew, :provision, [
  domain: "spew.tm",
  networks: %{
    "spew" => %{
      iface: "spewtest",
      range: [
        "172.21.0.0/16#25",
        "fc00:4000:4::0/64#100"
      ]
    }
  }
]
