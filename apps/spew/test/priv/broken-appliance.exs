%{
  name: "broken-appliance",
  runtime: nil,
  instance: %{
    runner: Spew.Runner.Void,
  },
  appliance: :change,
  enabled?: true
}
