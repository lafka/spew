defmodule RunnerPortTest do
  use ExUnit.Case

  alias Spew.Instance
  alias Spew.Instance.Server
  alias Spew.Instance.Item
  alias Spew.Runner.Port, as: Runner

  test "basic output" do
    {:ok, server} = Server.start_link name: __MODULE__
    spec = %Item{runner: Runner, command: ["/bin/bash", "-c", "echo pid: $BASHPID"]}

    {:ok, instance} = Instance.run spec, [subscribe: [self]], server

    # Instance should have terminated and stopped immediately
    assert {:stopped, _} = instance.state

    ref = instance.ref
    receive do
      {:output, ^ref, "pid: " <> extpid} ->
        assert {_, 1} = System.cmd System.find_executable("ps"), ["-p", String.rstrip(extpid)]
    after 5000 ->
      raise :timeout
    end
  end

  test "stop normal" do
    {:ok, server} = Server.start_link name: __MODULE__
    spec = %Item{runner: Runner, command: ["/bin/bash", "-c", "echo pid: $BASHPID; sleep 65"]}

    {:ok, instance} = Instance.run spec, [subscribe: [self]], server

    assert {:running, _} = instance.state

    ref = instance.ref
    extpid = receive do
      {:output, ^ref, "pid: " <> extpid} ->
          extpid
    after 5000 ->
      exit(:no_output)
    end

    monref = Process.monitor instance.plugin[Runner][:pid]
    {:ok, instance} = Instance.stop instance.ref, [], server

    receive do
      {:DOWN, ^monref, :process, _pid, reason} ->
        assert {_, 1} = System.cmd System.find_executable("ps"), ["-p", String.rstrip(extpid)]
    after 60000 ->
      raise :timeout
    end
  end

  test "io loop" do
    {:ok, server} = Server.start_link name: __MODULE__
    spec = %Item{runner: Runner, command: ["/bin/bash", "-c", "read line; echo $line; sleep 65"]}

    {:ok, instance} = Instance.run spec, [subscribe: [self]], server

    assert {:running, _} = instance.state

    ref = instance.ref
    :ok = Item.write instance, "hello\n"
    assert_receive {:input, ^ref, "hello\n"}
    assert_receive {:output, ^ref, "hello\n"}
  end
end
