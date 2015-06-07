defmodule Spew.Appliances.Shell do

  require Logger

  use Bitwise

  # @todo
  # exec calls should be spawned in a gen_server to handle stdin/out
  # and exits

  def run(appopts, _opts) do
    #cmd = appopts[:runneropts]
    cmd = List.flatten(appopts.runneropts) |> Enum.join(" ") |> String.to_char_list


    [file, _] = appopts.appliance

    if ! File.exists?(file) or 0 === (File.stat!(file).mode &&& 0o111) do
      {:error, {:missing_runtime, file}}
    else
      opts = [:stdin, {:stdout, self}, :monitor, {:stderr, self}]

      Logger.debug "exec/shell: #{cmd}"

      {:ok, pid, extpid} = :exec.run_link cmd, opts

      {:ok, [
        handler: __MODULE__,
        pid: pid,
        extpid: extpid,
        cmd: cmd
      ], pid}
    end
  end

  def stop(appcfg, opts \\ []) do
    kill? = opts[:kill?]
    wait = opts[:wait]


    case appcfg[:runstate][:pid] do
      nil ->
        {:error, {:argument_error, :no_pid}}

      pid when kill? ->
        Logger.debug "exec/shell: sending SIGTERM to #{inspect pid} (ext: #{appcfg[:runstate][:extpid]})"
        :ok = :exec.kill pid, 15

      pid when wait ->
        Logger.debug "exec/shell: stopping #{inspect pid} (ext: #{appcfg[:runstate][:extpid]}) w/wait #{wait}"
        :ok = :exec.stop_and_wait pid, wait

      pid ->
        Logger.debug "exec/shell: stopping #{inspect pid} (ext: #{appcfg[:runstate][:extpid]})"
        :ok = :exec.stop pid
    end
  end

  def status(appstate) do
    {_, _state} =  appstate[:state]
  end
end

