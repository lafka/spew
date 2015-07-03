defmodule Spew.Runner.SystemdNspawn do
  @moduledoc """
  Run a systemd-nspawn container

  ## Things to consider before using this

    * nspawn containers are terrible at graceful shutdowns, therefore
      both `stop/2` and `kill/1` will just send `]]]` which will
      terminate the instance

    * Frequent start/stop of same container seems to trigger a
      'Directory tree is currently busy' error

    * Network Configuration using Spew.Network must be done by
      a shell script and calling it manually. If this works or not
      is complete guess work. Ideally the veth would be configured
      before it's injected into the namespace. This is not possible
      since the nic state would be lost on transfer to the namespace.
      This can be fixed by writing a port driver spawning some kind
      of vitalization technology
  """

  use Spew.Plugin
  use Spew.Runner

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

  def pid(%Item{} = instance) do
    PortRunner.pid instance
  end

  def run(%Item{ref: ref} = instance, opts) do
    cmd = []
      |> expand_cmd(instance, opts)
      |> expand_env(instance, opts)
      |> extract_name(instance, opts)
      |> expand_mounts(instance, opts)
      |> extract_runtime(instance, opts)
      |> extract_network(instance, opts)

    cmd = List.flatten cmd

    defaultopts = ["--kill-signal", "SIGTERM"]
    cmd = maybe_sudo ++ ["systemd-nspawn" | cmd]

    PortRunner.run %{instance | command: cmd}, opts
  rescue e in Exception ->
    {:error, e.message}
  end

  defp expand_cmd(acc, %Item{command: "" <> cmd} = instance, opts) do
    expand_cmd acc, %{instance | command: Spew.Utils.String.tokenize(cmd)}, opts
  end
  defp expand_cmd(acc, %Item{command: cmd}, _opts) do
    ["--", cmd | acc]
  end

  defp expand_env(acc, %Item{env: env}, opts) do
    env = Enum.map env, fn({k, v}) -> "--setenv=#{k}=#{v}" end
    env ++ acc
  end

  defp extract_name(acc, %Item{name: name, ref: ref}, _opts) do
    name  = String.replace name || ref, ~r/[^a-z0-9_-]/, ""
    ["-M", name | acc]
  end

  defp extract_runtime(acc, %Item{runtime: nil}, _opts), do: acc
  defp extract_runtime(acc, %Item{runtime: runtime} = instance, _opts) do
    # Find rootfs from overlay plugin
    alias Spew.Plugin.Instance.OverlayMount

    %OverlayMount{mountpoint: root} = instance.plugin[OverlayMount]
    ["-D", root | acc]
  end

  defp extract_network(acc, %Item{network: nil}, _opts), do: acc
  defp extract_network(acc, %Item{network: network}, _opts) do
    # Generate and insert netsetup
    acc
  end

  defp expand_mounts(acc, %Item{mounts: []}, _opts), do: acc
  defp expand_mounts(acc, %Item{mounts: _mounts}, _opts) do
    raise Exception, message: :mount_not_supported
  end


  defp maybe_sudo do
    case System.get_env("USER") do
      "root" -> []
      _ -> ["sudo"]
    end
  end

  def stop(%Item{} = instance, signal) do
    # nspawn in combination with sudo is terrible on graceful
    # shutdowns... kill it with fire
    PortRunner.stop instance, "SIGKILL"
  end

  # Spew.Plugin callbacks
  @doc """
  Plugin spec

  Dynamically inserts Network and Build plugins if needed
  OverlayMount is always required
  """
  def spec(%Item{network: net, runtime: runtime} = instance) do
    alias Spew.Plugin.Instance.Network
    alias Spew.Plugin.Instance.Build
    alias Spew.Plugin.Instance.OverlayMount
    alias Spew.Runner.Port, as: PortRunner

    build? = match? {:build, _}, runtime
    extra = (net && [Network] || []) ++ (build? && [Build] || [])

    [
      require: [PortRunner, OverlayMount | extra],
      after: [PortRunner, OverlayMount | extra]
    ]
  end

  require Logger

  @doc """
  Plugin init
  """
  def init(%Item{ref: ref}, _opts) do
    Logger.debug "instance[#{ref}]: init plugin #{__MODULE__}"
    {:ok, nil}
  end

  @doc """
  Handle cleanup of self

  Making sure the machine is dead using machined calls
  """
  def cleanup(%Item{ref: ref}, _state) do
    Logger.debug "instance[#{ref}]: cleanup after plugin #{__MODULE__}"
    :ok
  end

  @doc """
  Handle plugin events
  """
  def notify(_instance, state, _ev), do: :ok
end
