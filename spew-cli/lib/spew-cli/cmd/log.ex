defmodule SpewCLI.Cmd.Log do

  @manager {:global, Spew.Appliance.Manager}

  def run(args) do
    SpewCLI.maybe_start_network

    refs = for appref_or_name <- args do
      {:ok, {appref, appcfg}} = GenServer.call @manager, {:get_by_name_or_ref, appref_or_name}
      :ok = :rpc.call SpewCLI.host, Spew.Appliance, :subscribe, [appref, :log, self]
      Process.monitor appcfg[:apploop]
    end
    logloop refs
  end

  def help(args) do
    """
    usage: spew-cli log <ref-or-name1, .., ref-or-nameN>

    Logs the output of one or more appliances
    """
  end

  def shorthelp, do:
    "log [opts] <ref-or-name, ..> - log an appliance"

  defp logloop([]) do
    IO.puts :stderr, "all appliances exited... no more logging"
    :ok
  end
  defp logloop(refs) do
    receive do
      {:log, appref, {_device, buf}} ->
        IO.write "#{appref} :: #{buf}"
        logloop refs

      {:DOWN, ref, :process, _pid, reason} ->
        logloop refs -- [ref]
    end
  end
end


