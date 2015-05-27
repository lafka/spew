defmodule SpewCLI.Cmd.Attach do

  @manager {:global, Spew.Appliance.Manager}

  def help(args) do
    """
    usage: spew-cli attach <ref-or-name>

    Attach to a running appliance
    """
  end

  def shorthelp, do:
    "attach <ref-or-name> - attach to a running appliance"


  def run([appref_or_name]) do
    SpewCLI.maybe_start_network

    {:ok, {appref, appcfg}} = GenServer.call @manager, {:get_by_name_or_ref, appref_or_name}
    :ok = :rpc.call SpewCLI.host, Spew.Appliance, :subscribe, [appref, :log, self]
    mon = Process.monitor appcfg[:apploop]

    parent = self
    spawn_link fn -> waitforinput parent end

    ioloop appref, mon
  end

  defp waitforinput(parent) do
    buf = IO.gets("")
    send parent, {:input, buf}
    waitforinput parent
  end

  defp ioloop(appref, ref) do
    receive do
      {:log, _, {_device, buf}} ->
        IO.write buf
        ioloop appref, ref


      {:input, :eof} ->
        :ok

      {:input, buf} ->
        :ok = :rpc.call SpewCLI.host, Spew.Appliance, :notify, [appref, :input, buf]
        ioloop appref, ref


      {:DOWN, ^ref, :process, _pid, reason} ->
        IO.puts "appliance exit: #{inspect reason}"
    end
  end
end


