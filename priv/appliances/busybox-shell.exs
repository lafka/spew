%{
  name: "busybox-shell",
  runtime: "TARGET == 'busybox'",
  instance: %{
    runner: Spew.Runner.Systemd,
    command: "/bin/busybox sh"
  },
  enabled?: true
}
