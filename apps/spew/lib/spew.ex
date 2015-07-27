defmodule Spew do
  use Application

  require Logger

  def start(_type, _args) do
    :ok = check_prereqs

    import Supervisor.Spec, warn: false

    children = [
      worker(Spew.Host.Server, []),
      worker(Spew.Build.Server, []),
      worker(Spew.Appliance.Server, []),
      worker(Spew.Network.Server, [])
    ]

    opts = [strategy: :one_for_one, name: Spewhost.Supervisor]
    sup = Supervisor.start_link(children, opts)

    :ok = start_node

    sup
  end

  def start_node do
    dir = Path.join(Application.get_env(:spew, :spewroot), "cluster")
    file = Path.join(dir, "hostname")
    case File.read Path.join(dir, file) do
      {:ok, name} ->
        start_node2 :"#{name}"

      {:error, :enoent} ->
        name = :crypto.strong_rand_bytes(8)
          |> Base.encode16
          |> String.downcase

        File.mkdir_p! dir
        File.write file, name
        start_node2 :"#{name}"
    end
  end

  def start_node2(name) do
    case Node.start name do
      {:ok, _} -> :ok
      {:error, _} = err ->
        err
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
