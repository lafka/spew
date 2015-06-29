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
    assert :ok == Instance.delete instance.ref, [], server

    assert {:error, {:notfound, {:instance, instance.ref}}} == Instance.get instance.ref, server
  end

  test "list" do
    {:ok, server} = Server.start_link name: __MODULE__

    {:ok, []} = Instance.list server

    {:ok, instance1} = Instance.add "list-test-1", %Item{runner: Void}, server
    {:ok, instance2} = Instance.add "list-test-2", %Item{runner: Void}, server
    {:ok, list} = Instance.list server
    assert Enum.sort([instance1, instance2]) == Enum.sort(list)

    :ok = Instance.delete instance2.ref, [], server
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

    :ok = Instance.delete instance.ref, [kill?: true], server
    assert_receive {:DOWN, _ref, :process, ^pid, :killed}

    assert {:error, {:notfound, {:instance, _ref}}} = Instance.get instance.ref, server
  end

  test "delete: stop?" do
    {:ok, server} = Server.start_link name: __MODULE__
    {:ok, instance} = Instance.add "delete-kill", %Item{runner: Void}, server
    {:ok, instance} = Instance.start instance.ref, [], server

    {:ok, pid} = instance.runner.pid instance
    monref = Process.monitor pid

    :ok = Instance.delete instance.ref, [stop?: true], server
    assert_received {:DOWN, ^monref, :process, ^pid, :normal}

    assert {:error, {:notfound, {:instance, _ref}}} = Instance.get instance.ref, server
  end
end
