defmodule Spew.Runner.SystemdNspawn do
  @moduledoc """
  Runner injecting using systemd-nspawn to run a container using the
  Port runner to start/stop etc.
  """

  require Logger

  alias Spew.Utils.Time
  alias Spew.Instance.Item
  alias Spew.Runner.Port, as: PortRunner

  def capabilities, do: [
    :plugin,
    :command,
    :env,
    :runtime,
    {:runtime, :chroot},
    :mounts,
    :network
  ]

  def supported? do
    case System.find_executable "systemd-nspawn" do
      nil -> false
      _bin -> true
    end
  end

  def run(%Item{ref: ref} = instance, opts) do
    {cmd, setup, cleanup} = {[], [], []}
      |> cmd(:command, instance, opts)
      |> cmd(:runtime, instance, opts)
      |> cmd(:network, instance, opts)
      |> cmd(:env, instance, opts)
      |> cmd(:mounts, instance, opts)

    cmd = List.flatten cmd

    defaultopts = ["--kill-signal", "SIGTERM"]
    cmd = maybe_sudo ++ ["systemd-nspawn" | cmd]

    case callbacks [instance], setup do
      :ok ->
        hooks = cleanup ++ instance.hooks[:stop]
        case PortRunner.run %{instance | command: cmd, hooks: hooks}, opts do
          {:ok, _} = res ->
            res

          res ->
            callbacks [instance, res], cleanup, false
            res
        end

      res ->
        callbacks [instance, res], cleanup, false
        res
    end
  rescue e in Exception ->
    {:error, e.message}
  end

  defp callbacks(args, funs), do: callbacks(args, funs, true)
  defp callbacks(_args, [], _strict?), do: :ok
  defp callbacks(args, [fun | rest], strict?) do
    case apply fun, args do
      :ok ->
        callbacks args, rest, strict?

      {:ok, _} ->
        callbacks args, rest, strict?

      res ->
        res
    end
  rescue e in BadArityError ->
    if true === strict? do
      {:error, {:callback, {:badarit, fun}}}
    else
      Logger.error "instance/callbacks: bad arity in #{inspect fun}"
      callbacks args, rest, strict?
    end
  end

  defp maybe_sudo do
    case System.get_env("USER") do
      "root" -> []
      _ -> ["sudo"]
    end
  end

  defp cmd({acc, s, c}, :runtime, %Item{runtime: {:chroot, rootfs}} = instance, _opts) do
    {["-D", rootfs | acc], s, c}
  end
  defp cmd(acc, :network, instance) do
    acc
  end
  defp cmd({acc, s, c}, :env, instance, _opts) do
    env = Enum.map instance.env, fn({k, v}) -> "--setenv=#{k}=#{v}" end
    env ++ acc
    {acc, s, c}
  end
  defp cmd({acc, s, c}, :mounts, instance, _opts) do
    {acc, s, c}
  end
  defp cmd(tmp, :command, %Item{command: "" <> cmd} = instance, opts) do
    cmd tmp, :command, %{instance | command: Spew.Utils.String.tokenize(cmd)}, opts
  end
  defp cmd({acc, s, c}, :command, %Item{command: cmd} = instance, _opts) do
    {["--", cmd | acc], s, c}
  end
  defp cmd(acc, :command, %Item{command: "" <> cmd} = instance) do
    cmd acc, :command, %{instance | command: Spew.Utils.String.tokenize(cmd)}
  end
  defp cmd(acc, :command, %Item{command: cmd} = instance) do
    ["--", cmd | acc]
  end

  def subscribe(instance, who), do: PortRunner.subscribe(instance, who)
  def write(instance, buf), do: PortRunner.write(instance, buf)
  def pid(instance), do: PortRunner.pid(instance)

  def stop(%Item{} = instance, signal), do: PortRunner.stop(instance, signal)

  # To kill we send "]]]" to the running process and let systemd-nspawn
  # handle the rest
  def kill(%Item{} = instance) do
    write instance, "]]]"
    {:ok, %{instance | state: {:killing, Time.now(:milli_seconds)}}}
  end

  @doc """
  Handle events from InstancePlugin
  """
  def event(_instance, state, _ev), do: state
end
