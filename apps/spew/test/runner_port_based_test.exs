defmodule RunnerGenTests do
  # Test some aspects of running shell based instances, and their
  # dependencies, more specifically:
  #  * Port runner
  #  * LQXExec runner
  #  * SystemdNspawn runner
  #  * Build and Overlay plugin integration
  # Note that this is also tests # overlay, build and network plugin
  # integration
  use ExUnit.Case

  alias Spew.Network
  alias Spew.Instance
  alias Spew.Instance.Server
  alias Spew.Instance.Item

  alias Spew.Utils.Net.InetAddress

  @runners [Spew.Runner.LXCExec]
  # parallel tests and fuck ups?
  setup_all do
    rootfs = Path.join [__DIR__, "runner", "busyboxroot"]

    unless File.exists? target = Path.join [rootfs, "bin", "busybox"] do
      File.mkdir_p! Path.join([rootfs, "bin"])
      File.cp! System.find_executable("busybox"), target
    end

    {:ok, [rootfs: rootfs]}
  end


  test "set environment", ctx do
    for runner <- @runners do
      {:ok, server} = Server.start_link name: ctx[:test]
      val = "helo"

      # Use chroot runtime if runner supports it, or fallback to
      # whatever the runner actually does
      runtime = if Enum.member?(runner.capabilities, :runtime) do
        {:chroot, ctx[:rootfs]}
      else
        nil
      end

      spec = %Item{runner: runner,
                   name: "#{runner}-#{ctx[:test]}",
                   runtime: runtime,
                   env: %{"VAR" => val},
                   command: "/bin/busybox sh -c 'echo $VAR'"}

      {:ok, instance} = Instance.run spec, [subscribe: [self]], server

      assert {:stopped, _} = instance.state,
        "runner[#{runner}] did not exit on time (#{instance.ref})"

      ref = instance.ref
      match = "#{val}\n"
      assert_received {:output, ^ref, ^match},
        "runner[#{runner}] did not receive expected output `#{val}` (#{instance.ref})"
    end
  end

  test "use chroot", ctx do
    for runner <- @runners do
      {:ok, server} = Server.start_link name: ctx[:test]
      val = "helo"

      # Use chroot runtime if runner supports it, or fallback to
      # whatever the runner actually does
      if Enum.member?(runner.capabilities, :runtime) do
        {:chroot, ctx[:rootfs]}

        spec = %Item{runner: runner,
                     name: "#{runner}-#{ctx[:test]}",
                     runtime: {:chroot, ctx[:rootfs]},
                     command: "/bin/busybox sh -c 'ls /bin'"}

        {:ok, instance} = Instance.run spec, [subscribe: [self]], server

        assert {:stopped, _} = instance.state,
          "runner[#{runner}] did not exit on time (#{instance.ref})"

        # If it's a chroot we will only have busybox in /bin
        ref = instance.ref
        match = "busybox\n"
        assert_received {:output, ^ref, ^match},
          "runner[#{runner}] did not receive expected output `#{val}` (#{instance.ref})"
      else
        IO.puts "WARNING: #{runner} does not support chroot"
      end
    end
  end

  test "use network", ctx do

    # flow:
    #  * container start allocates network
    #  * container crash (we intentionally crash it) keeps the allocation
    #  * container kill keeps the network allocation
    #  * graceful stop removes the allocation

    for runner <- @runners do
      network = %Network{name: netname = "#{ctx[:test]}",
                         ranges: ["172.29.1.1/24#25", "fe00::f:1/48#59"]}

      {:ok, instserver} = Server.start_link name: :"#{ctx[:test]}-net"

      {:ok, netserver} = Network.Server.start name: :"#{ctx[:test]}-ins", init: [networks: [network]]
      {:ok, [network]} = Network.networks netserver

      {:ok, slice} = Network.delegate network.ref, [owner: ctx[:test]], netserver

      # Use chroot runtime if runner supports it, or fallback to
      # whatever the runner actually does
      if Enum.member?(runner.capabilities, :network) do
        {:chroot, ctx[:rootfs]}

        spec = %Item{runner: runner,
                     name: "#{runner}-#{ctx[:test]}",
                     network: netname,
                     command: "/bin/busybox sh -c 'ip addr show dev eth0; sleep 2'"}

        opts = [{:subscribe, [self]},
                {Network.Server, netserver},
                {:net_slice_owner, slice.owner}]

        {:ok, instance} = Instance.run spec, opts, instserver

        buf = collectoutput instance.ref
        addresses = instance.plugin[Spew.Plugin.Instance.Network][:allocation].addresses

        for {ip, mask} <- addresses do
          addr = InetAddress.to_string(ip)
          match = addr <> "/#{mask}"
          case ip do
            {_,_,_,_} ->
              assert String.match?(buf, ~r/inet #{match}/), "address `#{match}` not set"
              assert {_, 0} = System.cmd System.find_executable("ping"), ["-c", "1", "-W", "10", addr]

            _ ->
              assert String.match?(buf, ~r/inet6 #{match}/), "address `#{match}` not set"
              assert {_, 0} = System.cmd System.find_executable("ping6"), ["-c", "1", "-W", "10", addr]
          end
        end
      else
        IO.puts "WARNING: #{runner} does not support network"
      end
    end
  end

  defp collectoutput(ref), do: collectoutput(ref, "")
  defp collectoutput(ref, acc) do
    receive do
      {:output, ^ref, buf} ->
        collectoutput ref, acc <> buf
    after
      0 -> acc
    end
  end
end
