defmodule SystemdTest do
  use ExUnit.Case

  alias Spew.Appliance
  alias Spew.Appliance.Config
  alias Spew.Appliance.Manager

  defp flush(echo? \\ false) do
    receive do
      m ->
        if echo? do
          IO.inspect m
        end
        flush
    after
      0 -> :ok
    end
  end

  setup do
    Config.unload :all
    {:ok, status} = Appliance.status
    Dict.keys(status) |> Enum.each fn(appref) -> Manager.delete appref end

    #if File.exists? __DIR__ <> "/chroot" do
    #  File.rm_rf! __DIR__ <> "/chroot"
    #end
    flush
  end

  defp testname(ctx) do
    "test " <> name = Atom.to_string ctx[:test]
    tokenize name
  end
  defp tokenize(buf), do: String.replace("#{buf}", ~r/[^a-zA-Z0-9-_]/, "-")

  test "status", ctx do
    {:ok, _cfgref} = Appliance.create testname(ctx), %Config.Item{
      name: testname(ctx),
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh -c 'echo systemd-container; sleep 1'"],
        root: {:busybox, "./test/chroot"}
      ]
    }

    {:ok, appref} = Appliance.run testname(ctx), %{}, [subscribe: [:log]]

    assert_receive {:log, ^appref, {:stdout, "systemd-container\n"}}, 1000

    assert {:ok, {_, :alive}} = Appliance.status appref
    {:ok, :stop} = Manager.await appref, &match?(:stop, &1), 2000
    assert {:ok, {_, :stopped}} = Appliance.status appref
  end

#  test "dir chroot" do
#    assert nil, "dir chroot test not implemented"
#  end
#
  test "archive chroot", ctx do
    {:error, :checksum} = Appliance.run nil, %{
      name: testname(ctx),
      type: :systemd,
      runneropts: [root: {:archive, "test/spew-builds/dummy-checksum-fail/1760bbafbd386052ce1810891ea5a22bf0d4ed8.tar.gz"}]
    }

    {:error, :signature} = Appliance.run nil, %{
      name: testname(ctx),
      type: :systemd,
      runneropts: [root: {:archive, "test/spew-builds/dummy-gpg-fail/1760bbafbd386052ce1810891ea5a22bf0d4ed8e.tar.gz"}]
    }

    {:ok, appref} = Appliance.run nil, %{
      name: testname(ctx),
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh -c 'echo systemd-container; sleep 1'"],
        root: {:archive, "/home/user/.spew/builds/dummy/0.0.3/735eea0793cf82dfe22e8e1ee2f9460a07ff379b/adc83b19e793491b1c6ea0fd8b46cd9f32e592fc/a7b979c840c366668920d7b9ba1056102c1f700b.tar.gz"}
      ]
    }, [subscribe: [:log]]

    assert_receive {:log, appref, {:stdout, "systemd-container\n"}}, 1000

    # There will be some weird stderr messages, completely version
    # dependant... flush them
    assert {:ok, {_, :alive}} = Appliance.status appref

    {:ok, :stop} = Manager.await appref, &match?(:stop, &1), 2000

    assert {:ok, {_, :stopped}} = Appliance.status appref
  end

#  test "image chroot" do
#    assert nil, "image chroot test not implemented"
#  end

  test "bridge network", ctx do
    # test for non existing bridge
    {:ok, _cfgref} = Appliance.create testname(ctx) <> "a", %Config.Item{
      name: "bridge",
      type: :systemd,
      runneropts: [
        network: [{:bridge, "noonenamestheirbridgethis"}]
      ]
    }

    {:error, {:no_such_iface, _}} = Appliance.run testname(ctx) <> "a"

    # test for non-bridge iface
    {:ok, _cfgref} = Appliance.create testname(ctx) <> "b", %Config.Item{
      name: "bridge",
      type: :systemd,
      runneropts: [
        network: [{:bridge, "lo"}]
      ]
    }

    {:error, {:iface_not_bridge, _}} = Appliance.run testname(ctx) <> "b"

    # run with the bridge
    {:ok, _cfgref} = Appliance.create testname(ctx), %Config.Item{
      name: "bridge",
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox ip link"],
        root: {:busybox, "./test/chroot"},
        network: [{:bridge, "tm"}]
      ]
    }

    {:ok, _appref} = Appliance.run testname(ctx), %{}, [subscribe: [:log]]
    buf = collect 1000
    # check that network is okey, we assume that the host system
    # manages to ensure the bridge availability
    assert Regex.match? ~r/2: host0/, buf
  end

  defp collect(timeout), do: collect("", timeout)
  defp collect(buf, timeout) do
    receive do
      {:log, _, {:stdout, data}} ->
        collect(buf <> data, timeout)
    after
      timeout ->
        buf
    end
  end

#  test "host iface network" do
#    assert nil, "host iface net test not implemented"
#  end
#
#  test "vlan network" do
#    assert nil, "vlan net test not implemented"
#  end
#
#  test "macvlan network" do
#    assert nil, "macvlan net test not implemented"
#  end
#
#  test "expose ports" do
#    assert nil, "expose ports test not implemented"
#  end
#
  test "tmpfs", ctx do
    {:ok, _cfgref} = Appliance.run nil, %{
      name: testname(ctx),
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox mount"],
        root: {:busybox, "./test/chroot"},
        tmpfs: ["/test-tmpfs"]
      ]
    }, [subscribe: [:log]]

    buf = collect(1000)
    assert String.match? buf, ~r/\/test-tmpfs/
  end

  test "mounts", ctx do
    {:ok, _cfgref} = Appliance.run nil, %{
      name: testname(ctx),
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox mount"],
        root: {:busybox, "./test/chroot"},
        mount: [
          "./:/bind:ro"
        ]
      ]
    }, [subscribe: [:log]]

    buf = collect(1000)
    assert String.match? buf, ~r/\/bind/
  end

  test "spew-build archive" do
    {:ok, appref} = Appliance.run nil, %{
      name: "test-spew-build-archive",
      type: :systemd,
      appliance: ["dummy", %{type: :spew, tag: "0.0.3", busybox: true}]
    }

    assert :ok = Appliance.stop appref
  end
end
