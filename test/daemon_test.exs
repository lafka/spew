defmodule DaemonTest do
  use ExUnit.Case, async: false

  alias Spew.Appliance
  alias Spew.Appliance.Manager
  alias Spew.Appliance.Config

  @cooldown 250

  setup ctx do
    Config.unload :all

    {:ok, _cfgref} = Appliance.create testname(ctx), %Config.Item{
      name: testname(ctx),
      type: :systemd,
      runneropts: [
        command: [],
        root: {:busybox, "./test/chroot"}
      ]
    }

    flush
  end

  defp testname(ctx) do
    "test " <> name = Atom.to_string ctx[:test]
    tokenize name
  end
  defp tokenize(buf), do: String.replace("#{buf}", ~r/[^a-zA-Z0-9-_]/, "-")

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

  test "logging", ctx do
    flush
    {:ok, appref} = Appliance.run testname(ctx), %{
      runneropts: [
        command: ["/bin/busybox sh -c 'for f in 1 2 3 4 5 6; do echo $f; sleep 0.1; done'"]
      ]
    }

    {:ok, _appcfg} = Manager.get(appref)
    Appliance.subscribe appref, :log

    assert_receive {:log, appref, {:stdout, "1\n"}}, 200
    assert_receive {:log, appref, {:stdout, "2\n"}}, 200
    assert_receive {:log, appref, {:stdout, "3\n"}}, 200
    assert_receive {:log, appref, {:stdout, "4\n"}}, 200
    assert_receive {:log, appref, {:stdout, "5\n"}}, 200
    assert_receive {:log, appref, {:stdout, "6\n"}}, 200

    {:ok, :stop} = Manager.await appref, &match?(:stop, &1), 1000

    # wait for release of chroot
    :timer.sleep @cooldown
  end

  test "attach", ctx do
    flush
    {:ok, appref} = Appliance.run testname(ctx), %{:runneropts => [
        command: ["/bin/busybox sh -c 'read line; echo $line'"],
    ]}

    {:ok, _appcfg} = Manager.get(appref)
    Appliance.subscribe appref, :log

    Appliance.notify appref, :input, "hello\n"
    assert_receive {:log, ^appref, {:stdout, "hello\n"}}, 2000

    # wait for release of chroot
    :timer.sleep @cooldown
  end
end
