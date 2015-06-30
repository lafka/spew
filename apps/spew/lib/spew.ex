defmodule Spew do
  use Application

  require Logger

  def start(_type, _args) do
    :ok = check_prereqs

    import Supervisor.Spec, warn: false

    setup_network

    children = [
      worker(Spew.Host.Server, []),
      worker(Spew.Build.Server, []),
      worker(Spew.Appliance.Server, [])
    ]

    opts = [strategy: :one_for_one, name: Spewhost.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def setup_network do
    setup? = false !== Application.get_env(:spew, :provision)[:auto_setup_networks]

    if setup? do
      networks = Map.keys Application.get_env(:spew, :provision)[:networks]
      Enum.each networks, &(true = setup_network(&1))
    else
      Logger.info "network: not auto-configuring networks"
    end
  end
  def setup_network(network) do
    case Spew.Network.setupbridge network do
      true ->
        iface = Spew.Utils.Net.Iface.stats network
        addrs = for {addr, opts} <- iface.addrs, do:
          "  #{String.rjust("#{opts[:type]}:", 9)} #{addr}/#{opts[:netmask]}\n"

        Logger.info """
        network[#{network}]: configured:
          mac: #{iface.hwaddr}
          flags: #{inspect iface.flags}
        #{addrs}
        """
        true

      {:error, _} = err ->
        Logger.error "network[#{network}]: failed to setup: #{inspect err}"
    end
  end

  def root do
    Application.get_env :spew, :spewroot
  end

  defp check_prereqs do
    Enum.each ["gpg", "tar", "systemd-nspawn"], &has_cmd?/1
    has_overlayfs?
    :ok
  end

  defp has_cmd?(cmd) do
    if nil === System.find_executable cmd do
      raise RuntimeError, message: "missing executable for '#{cmd}'"
    end
  end

  defp has_overlayfs? do
    {kernel, 0} = System.cmd System.find_executable("uname"), ["-r"]
    if File.dir? Path.join(["lib", "modules", kernel, "kernel", "fs", "overlayfs"]) do
      raise RuntimeError, message: "missing kernel support for overlayfs"
    end
  end
end
