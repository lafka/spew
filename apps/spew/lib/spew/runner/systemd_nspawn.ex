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
    cmd = []
      |> cmd(:command, instance)
      |> cmd(:runtime, instance)
      |> cmd(:network, instance)
      |> cmd(:env, instance)
      |> cmd(:mounts, instance)
      |> List.flatten

    defaultopts = ["--kill-signal", "SIGTERM"]
    cmd = maybe_sudo ++ ["systemd-nspawn" | [defaultopts | cmd]]

    PortRunner.run %{instance | network: nil,
                                env: nil,
                                mounts: nil,
                                command: cmd}, opts
  end

  defp maybe_sudo do
    case System.get_env("USER") do
      "root" -> []
      _ -> ["sudo"]
    end
  end

  defp cmd(acc, :runtime, %Item{runtime: {:chroot, rootfs}} = instance) do
    ["-D", rootfs | acc]
  end
  defp cmd(acc, :network, instance) do
    acc
  end
  defp cmd(acc, :env, instance) do
    env = Enum.map instance.env, fn({k, v}) -> "--setenv=#{k}=#{v}" end
    env ++ acc
  end
  defp cmd(acc, :mounts, instance) do
    acc
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
