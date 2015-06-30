defmodule Spew.Runner.Port do
  @moduledoc """
  Runner using plain erlang ports to do all communications

  This is non-portable due to the reliance on `kill`
  """

  require Logger

  alias Spew.Instance.Item

  def capabilities, do: [
    :plugin,
    :command,
    :env,
    :runtime
  ]

  def supported?, do: true

  def subscribe(%Item{plugin: %{__MODULE__ => %{pid: pid}}}, who) do
    ref = make_ref
    monref = Process.monitor pid
    send pid, {:subscribe, {who, ref}}
    receive do
      {^ref, :subscribed} ->
        :ok

      {:DOWN, ^monref, :process, ^pid, _} ->
        {:error, :noproc}
    end
  end

  def write(%Item{plugin: %{__MODULE__ => %{pid: pid}}}, buf) do
    send pid, {:write, buf}
    :ok
  end

  def pid(%Item{plugin: %{__MODULE__ => %{pid: pid}}}) do
    {:ok, pid}
  end
  def pid(%Item{ref: ref}), do:
    {:error, {:no_pid, {:instance, ref}}}

  def run(%Item{ref: ref, command: nil} = spec, _opts), do:
    {:error, {:empty_command, {:instance, ref}}}
  def run(%Item{ref: ref, command: [cmd | args]} = spec, opts) do
    Logger.debug "runner/port: exec #{cmd} #{inspect args}"

    case System.find_executable cmd do
      nil ->
        {:error, {:enoent, cmd, {:instance, ref}}}

      cmd ->
        {parent, ref} = {self, make_ref}
        {pid, monref} = spawn_monitor fn ->
          port = Port.open {:spawn_executable, cmd}, [{:args, args},
                                                      :exit_status,
                                                      :use_stdio,
                                                      :stderr_to_stdout,
                                                      :binary]

          send parent, {ref, :ok, port}

          Process.flag :trap_exit, true
          portproxy spec.ref, port
        end

        receive do
          {^ref, :ok, port} ->
            Enum.each opts[:subscribe] || [], &(send pid, {:subscribe, {&1, make_ref}})
            plugins = Map.put spec.plugin, __MODULE__, %{port: port,
                                                         pid: pid}
            {:ok, %{spec |
                      state: {:running, :erlang.now},
                      plugin: plugins}}

          {:DOWN, ^monref, :process, ^pid, reason} ->
            {:error, {:portexit, reason, {:instance, ref}}}
        end
    end
  end
  def run(%Item{ref: ref} = spec, _opts), do:
    {:error, {:invalid_command, {:instance, ref}}}

  defp portproxy(ref, port), do: portproxy(ref, port, %{})
  defp portproxy(ref, port, subscribers) do
    receive do
      {^port, {:data, buf}} ->
        Enum.each subscribers, fn({_monref, pid}) ->
          send pid, {:output, ref, buf}
        end

        portproxy ref, port, subscribers

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, n}} ->
        exit {:crashed, n}

      {:write, buf} ->
        Port.command port, buf
        Enum.each subscribers, fn({_monref, pid}) ->
          send pid, {:input, ref, buf}
        end
        portproxy ref, port, subscribers

      {:link, pid} ->
        Process.link pid
        portproxy ref, port, subscribers

      {:stop, {who, returnref}, signal} ->
        signal = signal || "TERM"
        send who, {returnref, :stopping}
        # Ask nicely for port to quit
        {:os_pid, ospid} = Port.info(port, :os_pid)
        {"", 0} = System.cmd System.find_executable("kill"), ["-s", signal, "#{ospid}"]
        Port.close port

        # wait for exit
        portproxy ref, port, subscribers

      {:kill, {who, returnref} = from} ->
        send self, {:stop, from, "KILL"}
        portproxy ref, port, subscribers

      {:EXIT, ^port, :normal} ->
        :ok

      {:EXIT, ^port, reason} ->
        exit(reason)

      # this is the kill call in {:stop, _} that we receive because
      # we are trapping exits
      {:EXIT, _, _} ->
        portproxy ref, port, subscribers


      {:subscribe, {pid, returnref}} ->
        monref = Process.monitor pid
        send pid, {returnref, :subscribed}
        portproxy ref, port, Map.put(subscribers, monref, pid)

      {:DOWN, monref, :process, pid, _reason} ->
        portproxy ref, port, Map.delete(subscribers, monref)

      msg ->
        Logger.warn "runner/port[#{ref}] unexpected msg: #{inspect msg}"
        portproxy ref, port, subscribers
    end
  end


  def stop(%Item{state: {state, _}} = spec, _signal)
      when state in [:stopping, :stopped, :killed, :killing] do

    {:ok, spec}
  end
  def stop(%Item{state: {{:crashed, _}, _}} = spec, _signal), do:
    {:ok, spec}
  def stop(%Item{plugin: %{__MODULE__ => %{pid: pid}},
                 ref: ref} = spec,
           signal) do

    {monref, returnref} = {Process.monitor(pid), make_ref}
    send pid, {:stop, {self, returnref}, signal}

    receive do
      {^returnref, :stopping} ->
        {:ok, %{spec | state: {:stopping, :erlang.now}}}

      {:DOWN, monref, :process, ^pid, :normal} ->
        {:ok, %{spec | state: {:stopped, :erlang.now}}}

      {:DOWN, monref, :process, ^pid, :noproc} ->
        {:ok, %{spec | state: {:stopped, :erlang.now}}}

      {:DOWN, monref, :process, ^pid, reason} ->
        {:ok, %{spec | state: {{:crashed, reason}, :erlang.now}}}
    end
  end
  def stop(%Item{ref: ref} = spec, _signal) do
    {:error, {:no_proc, {:instance, ref}}}
  end

  # there's no difference in kill vs stop here as they both rely on
  # Port.close/1 in the end. One could call the OS but this should work
  # until proven otherwise
  def kill(%Item{plugin: %{__MODULE__ => %{pid: pid}},
                 ref: ref} = spec) do
    {monref, returnref} = {Process.monitor(pid), make_ref}
    send pid, {:stop, {self, returnref}}

    receive do
      {^returnref, :stopping} ->
        {:ok, %{spec | state: {:killing, :erlang.now}}}

      {:DOWN, monref, :process, ^pid, :normal} ->
        {:ok, %{spec | state: {:killing, :erlang.now}}}

      {:DOWN, monref, :process, ^pid, :noproc} ->
        {:ok, %{spec | state: {:stopped, :erlang.now}}}

      {:DOWN, monref, :process, ^pid, reason} ->
        {:ok, %{spec | state: {{:crashed, reason}, :erlang.now}}}
    end
  end
  def kill(%Item{ref: ref, state: {_, _, _pid}}), do:
    {:error, {:no_proc, {:instance, ref}}}

  @doc """
  Handle events from InstancePlugin
  """
  def event(_instance, state, _ev), do: state
end
