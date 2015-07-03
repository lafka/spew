defmodule SpewInstanceTest do
  use ExUnit.Case

  alias Spew.Instance
  alias Spew.Instance.Item
  alias Spew.Instance.Server

  alias Spew.Runner.Void

  test "add / get / delete instance" do
    {:ok, server} = Server.start_link name: __MODULE__

    {:ok, instance} = Instance.add "add-test", %Item{runner: Void}, server
    {:error, {:conflict, {:instance, _}}} = Instance.add "add-test", %Item{runner: Void}, server

    assert {:ok, instance} == Instance.get instance.ref, server
    assert {:ok, _} = Instance.delete instance.ref, [], server

    assert {:error, {:notfound, {:instance, instance.ref}}} == Instance.get instance.ref, server
  end

  test "list" do
    {:ok, server} = Server.start_link name: __MODULE__

    {:ok, []} = Instance.list server

    {:ok, instance1} = Instance.add "list-test-1", %Item{runner: Void}, server
    {:ok, instance2} = Instance.add "list-test-2", %Item{runner: Void}, server
    {:ok, list} = Instance.list server
    assert Enum.sort([instance1, instance2]) == Enum.sort(list)

    assert {:ok, _} = Instance.delete instance2.ref, [], server
    assert {:ok, [^instance1]} = Instance.list server
  end

  test "query" do
    {:ok, server} = Server.start_link name: __MODULE__

    {:ok, []} = Instance.query ":true == :true", true, server

    {:ok, instance1} = Instance.add "query-test-1", %Item{runner: Void}, server
    {:ok, instance2} = Instance.add "query-test-2", %Item{runner: Void}, server
    assert {:ok, Enum.sort([instance1.ref, instance2.ref])} == Instance.query ":true == :true", true, server

    match = Map.put %{}, instance1.ref, instance1
    assert {:ok, match} == Instance.query "name == 'query-test-1'", false, server
  end

  test "add, start, stop" do
    {:ok, server} = Server.start_link name: __MODULE__
    {:ok, instance} = Instance.add "query-test-1", %Item{runner: Void}, server
    {:ok, instance} = Instance.start instance.ref, [], server

    assert {:running, _} = instance.state

    {:ok, pid} = instance.runner.pid instance
    Process.monitor pid

    {:ok, instance} = Instance.stop instance.ref, [], server
    assert {:stopping, _} = instance.state

    assert_receive {:DOWN, _ref, :process, ^pid, :normal}

    {:ok, instance} = Instance.get instance.ref, server
    assert {:stopped, _} = instance.state
  end

  test "delete: kill?" do
    {:ok, server} = Server.start_link name: __MODULE__
    {:ok, instance} = Instance.add "delete-kill", %Item{runner: Void}, server
    {:ok, instance} = Instance.start instance.ref, [], server

    {:ok, pid} = instance.runner.pid instance
    Process.monitor pid

    assert {:ok, _} = Instance.delete instance.ref, [kill?: true], server
    assert_receive {:DOWN, _ref, :process, ^pid, :killed}

    assert {:error, {:notfound, {:instance, _ref}}} = Instance.get instance.ref, server
  end

  test "delete: stop?" do
    {:ok, server} = Server.start_link name: __MODULE__
    {:ok, instance} = Instance.add "delete-kill", %Item{runner: Void}, server
    {:ok, instance} = Instance.start instance.ref, [], server

    {:ok, pid} = instance.runner.pid instance
    monref = Process.monitor pid

    assert {:ok, _} = Instance.delete instance.ref, [stop?: true], server
    assert_received {:DOWN, ^monref, :process, ^pid, :normal}

    assert {:error, {:notfound, {:instance, _ref}}} = Instance.get instance.ref, server
  end

  test "hooks", ctx do
    {:ok, server} = Server.start_link name: ctx[:test]
    {:ok, agent} = Agent.start fn -> :waiting end

    spec = %Item{runner: Void,
                 hooks: %{
                   start: [fn(_) -> Agent.update(agent, fn(_) -> :started end) end],
                   stop: [fn(_, reason) -> Agent.update(agent, fn(_) -> reason end) end],
                 }}

    {:ok, instance} = Instance.run spec, [], server

    assert :started = Agent.get agent, &(&1)

    {:ok, _instance} = Instance.stop instance.ref, [], server

    assert :normal = Agent.get agent, &(&1)
  end

  test "plugin events", ctx do
    defmodule ConsumePlugin do
      use Spew.Plugin

      alias Spew.Instance.Item
      def spec(%Item{}), do: []
      def init(%Item{}, {pid, ref}) do
        {:ok, {{pid, ref}, []}}
      end

      def notify(%Item{}, {_ret, _events}, {:event, :ignore}), do: :ok
      def notify(%Item{}, {ret, events}, ev) do
        {:update, {ret, [ev | events]}}
      end

      def cleanup(%Item{}, {{ret, ref}, _}) do
        send ret, {ref, :cleaned}
        :ok
      end
    end

    ref = make_ref
    spec = %Item{runner: Void,
                 plugin: %{ConsumePlugin => {self, ref}}}


    {:ok, server} = Server.start_link name: ctx[:test]

    {:ok, instance} = Instance.add "plugin-test", spec, server
    {:ok, instance} = Instance.start instance.ref, [], server
    {:ok, instance} = Instance.stop instance.ref, [], server
    {:ok, instance} = Instance.start instance.ref, [], server

    Instance.notify instance.ref, :ignore, server
    Instance.notify instance.ref, :ev, server

    monref = Process.monitor instance.plugin[Spew.Runner.Void][:pid]

    {:ok, instance} = Instance.kill instance.ref, [], server
    {:ok, instance} = Instance.delete instance.ref, [], server


    assert {_, [:delete,
                {:stop, :killed},
                :killing,
                {:event, :ev},
                :start,
                {:stop, :normal},
                {:stopping, nil = _signal},
                :start,
                :add]} = instance.plugin[ConsumePlugin]

    # by now we should have received the clean notification
    assert_received {^ref, :cleaned}
  end
end
