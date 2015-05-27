defmodule SpewCLI.Cmd.Run do

  @manager {:global, Spew.Appliance.Manager}

  def run(rawargs) do
    {opts, [name | args], shortopts} = OptionParser.parse rawargs

    type = case opts[:type] do
      type when type in ["systemd", "shell", "void"] ->
        String.to_atom type

      _ ->
        raise ArgumentError, message: "expected type to be either shell, systemd or void"
    end


    SpewCLI.maybe_start_network

    {:ok, appref} = :rpc.call SpewCLI.host, Spew.Appliance, :run, [nil, %{
      name: name,
      type: type,
      runneropts: [
        command: args,
        root: {:busybox, "./test/chroot"}
      ]
    }, [subscribe: [{:log, self}]]], 5000

    if "true" == opts[:foreground] or "true" === opts[:attach] do
      {:ok, {appref, appcfg}} = GenServer.call @manager, {:get, appref}
      mon = Process.monitor appcfg[:apploop]


      parent = self
      if "true" == opts[:attach] do
        spawn_link fn -> waitforinput parent end
      end

      logloop(appref, mon)
    end
  end

  defp waitforinput(parent) do
    buf = IO.gets("")
    send parent, {:input, buf}
    waitforinput parent
  end

  defp logloop(appref, ref) do
    receive do
      {:log, _, {_device, buf}} ->
        IO.write buf
        logloop appref, ref


      {:input, :eof} ->
        :ok

      {:input, buf} ->
        :ok = :rpc.call SpewCLI.host, Spew.Appliance, :notify, [appref, :input, buf]
        logloop appref, ref


      {:DOWN, ^ref, :process, _pid, reason} ->
        IO.puts "appliance exit: #{inspect reason}"
    end
  end

  def help(args) do
    """
    usage: spew-cli run <name> [--systemd | --shell | --void] [opts]

    Runs a transient appliance

    Options:
      --log=true|false
      --foreground=true|false
    """
  end

  def shorthelp, do:
    "run <name> [type] [opts] - run a transient appliance"
end



