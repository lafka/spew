defmodule Spew.Appliances.Systemd do
  @moduledoc """
  Runs a systemd-nspawn container.

  This does exactly the same as the Shell appliance, expect it runs
  in a container

  runneropts:
    command: [binary()] | :boot - the command to run, or `:boot`
    root: {:chroot, dir()} |
          {:archive, file()} |
          {:image, file()} |
          {:busybox, dir},
    net: [
      {:bridge, iface()} |
      {:iface, iface()} |
      {:vlan, iface()} |
      {:macvlan, iface()}
    ],
    ports: ["tcp/" <> 1..65535 <> ":" 1..65535 |
            "udp/" <> 1..65535 <> ":" 1..65535],
    user: user(),
    mount: [
      path() :: HostPath, <> "/" <> path() :: ContainerPath <> "/" string :: Opts
    ],
    env: %{
      key() => val()
    },
    ro: bool(),
  """

  def run(appopts, _opts) do
    runneropts = Dict.put_new appopts[:runneropts], :name, appopts[:name]
    case build_cmd runneropts do
      {:ok, cmd} ->
        bin = System.find_executable "systemd-nspawn"
        shellopts = %{appopts | :runneropts => cmd,
                                :appliance => [bin, appopts]}
        Spew.Appliances.Shell.run shellopts, []

      {:error, _e} = err ->
        err
    end
  end

  defp build_cmd(vals), do: build_cmd(vals, [])
  defp build_cmd([], acc), do: {:ok, ["sudo systemd-nspawn" | acc]}
  defp build_cmd([{:name, v} | rest], acc), do:
    build_cmd(rest, ["--machine #{v}" | acc])
  defp build_cmd([{:command, v} | rest], acc), do:
    build_cmd(rest, acc ++ [v])
  defp build_cmd([{:root, {:busybox, dir}} | rest], acc) do
    case System.find_executable "busybox" do
      nil ->
        {:error, "busybox not installed"}
      busybox ->
        unless File.exists? Path.join([dir, "bin", "busybox"]) do
          File.mkdir_p! Path.join([dir, "bin"])
          File.copy! busybox, path = Path.join([dir, "bin", "busybox"])
          File.chmod! path, 777
        end

        build_cmd(rest, ["-D #{Path.absname(dir)}" | acc])
    end
  end
  defp build_cmd([{k, _v} | _rest], _acc), do: {:error, "unsupported key: `#{k}`"}

  def stop(appcfg, opts \\ []) do
  end

  def status(appstate) do
    # note that if there are unleft messages in mailbox these will be
    # returned here. probably upstream error....
    executable = System.find_executable("machinectl")
    case :exec.run '#{executable} status #{appstate.appcfg.name}', [:stdout, :stderr, :sync] do
      {:ok, _} ->
        {_, _state} = appstate[:state]

      {:error, [exit_status: 256,
                stderr: ["Could not get path to machine:" <> _]]} ->
        {nil, :stopped}
    end
  end
end
