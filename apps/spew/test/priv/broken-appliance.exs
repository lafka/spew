%{
  name: "broken-appliance",
  runtime: "",
  instance: %{
    runner: Spew.Runner.Void,
  },
  appliance: :change,
  enabled?: true
}
