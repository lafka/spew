%{
  name: "busybox-systemd",
  runtime: {:query, "name == 'busybox'"},
  instance: %{
    runner: Spew.Runner.Systemd,
    command: "/bin/busybox sh"
  },
  enabled?: true
}
