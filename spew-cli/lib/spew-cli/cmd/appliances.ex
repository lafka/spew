defmodule SpewCLI.Cmd.Appliances do

  @manager {:global, Spew.Appliance.Manager}
  @config {:global, Spew.Appliance.Config.Server}

  def run(args) do
    SpewCLI.maybe_start_network

    IO.puts "=> Appliance Instances"

    {:ok, list} = GenServer.call @manager, :list
    for {appref, appcfg} <- list do
      IO.puts "=> #{appcfg[:appcfg][:name]} (#{appref})"
      IO.puts "\thandler:  #{appcfg[:appcfg][:handler]}"
      IO.puts "\tstate:    #{inspect appcfg[:state]}"
      IO.puts "\trestart?: #{inspect appcfg[:appcfg][:restart]}"
      IO.puts "\tsupstate: #{inspect appcfg[:supstate]}"
      IO.puts "\thooks:    #{inspect appcfg[:appcfg][:hooks]}"
      IO.puts "\tapploop:  #{inspect appcfg[:apploop]} at #{node appcfg[:apploop]} (alive?: #{alive? appcfg[:apploop]})"
      IO.puts "\tcommand:  #{List.flatten([appcfg[:appcfg][:runneropts][:command]]) |> Enum.join(" ")}"
      IO.puts "\n"
    end

    IO.write "\n"

    IO.puts "=> Appliance Configurations"

    {:ok, list} = GenServer.call @config, :fetch

    for {appref, appcfg} <- list do
      appcfg = Map.delete appcfg, :__struct__
      cmd = case appcfg[:runneropts][:command] do
        nil -> "(init)"
        cmd -> List.flatten([cmd]) |> Enum.join(" ")
      end

      IO.puts "- #{appcfg[:name]} (#{appcfg[:type]}):  #{cmd}"
    end
  end

  defp alive?(pid) do
    node(pid) |> :rpc.call(:erlang, :is_process_alive, [pid])
  end

  def help(args) do
    """
    usage: spew-cli appliances

    List all appliances (including templates, and non-running)
    """
  end

  def shorthelp, do:
    "appliances - list all appliances (including templates and non-running)"
end




#%{
#  appcfg: %{
#    appliance: nil,
#    depends: [],
#    handler: Spew.Appliances.Systemd,
#    hooks: %{},
#    name: "test",
#    restart: false,
#    runneropts: [
#      command: ["/bin/busybox", "sh"],
#      root: {:busybox, "./test/chroot"}
#    ],
#    type: :systemd
#  },
#  apploop: #PID<7401.322.0>,
#  appref: "/cCxP8G7TvoTeTIjTm0RUi0I/BhXn511jkkZytn+agw=",
#  handler: Spew.Appliances.Systemd,
#  runopts: [subscribe: [log: #PID<0.41.0>]],
#  runstate: [
#    handler: Spew.Appliances.Shell,
#    pid: #PID<7401.323.0>,
#    extpid: 9116,
#    cmd: 'sudo systemd-nspawn -D /data/src/lafka/spew/test/chroot --machine test /bin/busybox sh'
#  ],
#  state: {1432730889637, {:crashed, {:exit_status, 256}}},
#  supstate: %{created: 1432730856535, restartcount: 0, restarts: []}
#}
