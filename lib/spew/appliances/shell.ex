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
      # @todo implement restart functionality
      # first version has simple semantics, either restart or don't.
      # restart sleep interval can be specified by # opts[:restart_wait_time]
      # second iteration should support restart frequencies and
      # specfications pr. exit status
      #opts = case appopts[:restart] do
      #  :true -> opts
      #  :on_exit -> opts
      #  :false -> opts
      #end

      opts = [:stdin, {:stdout, self}, :monitor, {:stderr, self}]

      Logger.debug "exec: #{cmd}"

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
    case appcfg[:runstate][:pid] do
      nil ->
        {:error, {:argument_error, :no_pid}}

      pid when kill? ->
        :exec.kill(pid)

      pid ->
        :exec.stop(pid)
    end
  end

  def status(appstate) do
    {_, _state} =  appstate[:state]
  end
end

