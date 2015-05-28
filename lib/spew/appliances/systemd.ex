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
      path() :: HostPath, <> ":" <> path() :: ContainerPath <> ":" string :: Opts
    ],
    env: %{
      key() => val()
    },
    ro: bool(),
  """

  def run(appopts, _opts) do
    runneropts = Dict.put_new appopts[:runneropts] || [], :name, appopts[:name]
    case build_cmd Enum.into(runneropts, []), appopts do
      {:ok, cmd, cont} ->
        bin = System.find_executable "systemd-nspawn"
        shellopts = %{appopts | :runneropts => cmd,
                                :appliance => [bin, appopts]}

        Enum.each cont, fn(f) -> f.() end

        Spew.Appliances.Shell.run shellopts, []

      {:error, _e} = err ->
        err
    end
  end

  defp build_cmd(vals, opts), do: build_cmd(vals, opts, [], [])
  defp build_cmd([], opts, acc, cont), do: {:ok, ["sudo systemd-nspawn" | acc], cont}

  defp build_cmd([{:name, v} | rest], opts, acc, cont), do:
    build_cmd(rest, opts, ["--machine", v | acc], cont)

  defp build_cmd([{:command, v} | rest], appcfg, acc, cont), do:
    build_cmd(rest, appcfg, acc ++ [appcfgtpl(Enum.join(v, " "), appcfg)], cont)

  defp build_cmd([{:root, {:archive, archive}} | rest], opts, acc, cont) do
    case verify_archive archive do
      :ok ->
        shasum = Path.basename archive, ".tar.gz"
        target = Path.join [System.tmp_dir, "spew-#{shasum}"]

        unpack = fn() ->
          File.mkdir_p target
          :erl_tar.extract archive, [:compressed, {:cwd, target}]
        end
        build_cmd(rest, opts, ["-D", target | acc], [unpack | cont])

      {:error, _} = res ->
          res
    end
  end
  defp build_cmd([{:root, {:busybox, dir}} | rest], opts, acc, cont) do
    case System.find_executable "busybox" do
      nil ->
        {:error, "busybox not installed"}

      busybox ->
        unless File.exists? Path.join([dir, "bin", "busybox"]) do
          File.mkdir_p! Path.join([dir, "bin"])
          File.copy! busybox, path = Path.join([dir, "bin", "busybox"])
          File.chmod! path, 777
        end

        build_cmd(rest, opts, ["-D #{Path.absname(dir)}" | acc], cont)
    end
  end
  defp build_cmd([{:root, {:chroot, dir}} | rest], opts, acc, cont) do
    cond do
      ! File.exists? dir ->
        {:error, {:enoent, dir}}
      ! File.dir? dir ->
        {:error, {:eisfile, dir}}
      true ->
        build_cmd rest, opts, ["-D", Path.absname(dir) | acc], cont
    end
  end

  defp build_cmd([{:network, net} | rest], opts, acc, cont) do
    case build_net_cmd(net, rest, acc) do
      {:ok, [rest, acc]} ->
        build_cmd rest, opts, acc, cont

      {:error, _} = res ->
        res
    end
  end

  defp build_cmd([{:tmpfs, target} | rest], opts, acc, cont) do
    build_cmd rest, opts, ["--tmpfs", target | acc], cont
  end

  defp build_cmd([{:mount, mounts} | rest], appcfg, acc, cont) do
    acc = Enum.reduce mounts, acc, fn(mount, acc) ->
      [item | opts] = String.split mount, ":"
      item = expandpath item, appcfg

      unless File.exists? item do
        raise ArgumentError, message: item
      end

      case opts do
        [] -> ["--bind", item | acc]
        [target] -> ["--bind", item <> ":" <> target | acc]
        [target, "ro"] -> ["--bind-ro", item <> ":" <> target | acc]
      end
    end

    build_cmd rest, appcfg, acc, cont
  rescue e in ArgumentError ->
    {:error, {:enoent, e.message}}
  end

  defp build_cmd([{k, _v} | _rest], _opts, _acc, _cont), do: {:error, "unsupported key: `#{k}`"}

  defp expandpath(path, appcfg) do
    appcfgtpl(path, appcfg) |> Path.expand
  end

  defp appcfgtpl(buf, appcfg) do
    Regex.replace ~r/{{([^}]*)}}/,
      buf,
      fn(ctx, k) ->
        appcfg[String.to_atom(k)]
      end
  end


  defp verify_archive(archive) do
    shasum = Path.basename archive, ".tar.gz"
    cond do
      ! File.exists? archive ->
        {:error, {:archive, :not_found, archive}}

      shasum != Spew.Utils.hashfile(:sha, archive) ->
        {:error, :checksum}

      :ok != Spew.Utils.gpgverify(archive <> ".asc", archive) ->
        {:error, :signature}

      :true ->
        :ok
    end
  end

  defp build_net_cmd([], rest, acc), do: {:ok, [rest, acc]}
  defp build_net_cmd([{:bridge, iface} | r], rest, acc) do
    {:ok, ifaces} = :inet.getiflist
    # totaly non-portable way of checking if it's a bridge
    if Enum.member? ifaces, '#{iface}' do
      if File.exists? "/sys/class/net/#{iface}/bridge" do
        build_net_cmd(r, rest, ["--network-bridge", iface | acc])
      else
        {:error, {:iface_not_bridge, "not a bridge: #{iface}, refusing to start container"}}
      end
    else
      {:error, {:no_such_iface, "no such iface: #{iface}, refusing to start container"}}
    end
  end

  def stop(appcfg, opts \\ []) do
    Spew.Appliances.Shell.stop appcfg, opts
  end

  def status(appstate) do
    # note that if there are unleft messages in mailbox these will be
    # returned here. probably upstream error.... spawn new task
    executable = System.find_executable("machinectl")

    t = Task.async fn ->
      :exec.run '#{executable} status #{appstate.appcfg.name}', [:stdout, :stderr, :sync]
    end

    case Task.await t do
      {:ok, _} ->
        {_, _state} = appstate[:state]

      {:error, [exit_status: 256,
                stderr: ["Could not get path to machine:" <> _]]} ->
        {nil, :stopped}
    end
  end
end
