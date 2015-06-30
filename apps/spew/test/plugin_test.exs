defmodule Spew.Instance.TestPlugin do
  alias Spew.Instance.Item

  def setup(_instance, _) do
    %{pid: spawn(&loop/0), started: false}
  end

  def start(%Item{plugin: %{__MODULE__ => state}}, _) do
    %{state | started: true}
  end

  defp loop, do: loop([])
  defp loop(evs) do
    receive do
      {who, ref, :get} when is_pid(who) and is_reference(ref) ->
        send who, {ref, evs}
        loop evs

      {who, ref, :clear} when is_pid(who) and is_reference(ref) ->
        send who, {ref, []}
        loop []

      ev ->
        loop [ev | evs]
    end
  end

  def event(%Item{plugin: %{ __MODULE__ => %{pid: pid}}}, state, ev) do
    send pid, ev
    state
  end

  def setup?(%Item{plugin: %{ __MODULE__ => %{pid: pid}}}), do: true
  def setup?(%Item{}), do: false

  def started?(%Item{plugin: %{ __MODULE__ => %{started: val}}}), do: val
  def started?(%Item{}), do: false

  def clearevs(%Item{plugin: %{ __MODULE__ => %{pid: pid}}}) do
    ref = make_ref
    send pid, {self, ref, :clear}
    monref = Process.monitor pid

    receive do
      {^ref, events} ->
        events

      {:DOWN, ^monref, :process, ^pid, _} ->
        raise Exception, "noproc: #{inspect pid}"
    end
  end

  def getevs(%Item{plugin: %{ __MODULE__ => %{pid: pid}}}) do
    ref = make_ref
    send pid, {self, ref, :get}
    monref = Process.monitor pid

    receive do
      {^ref, events} ->
        events

      {:DOWN, ^monref, :process, ^pid, _} ->
        raise Exception, "noproc: #{inspect pid}"
    end
  end
end

defmodule SpewInstancePluginTest do
  use ExUnit.Case

  alias Spew.Instance
  alias Spew.Runner.Void
  alias Spew.Instance.Server
  alias Spew.Instance.Item
  alias Spew.Instance.TestPlugin

  test "consume events: :add, :start, :stopping, {:stop, _}, :delete" do
    {:ok, server} = Server.start_link name: __MODULE__
    {:ok, instance} = Instance.add "plugin-test",
                                   %Item{runner: Void,
                                         plugin_opts: %{ TestPlugin => true}},
                                   server
    ref = instance.ref

    assert TestPlugin.setup? instance

    {:ok, instance} = Instance.start instance.ref, [], server

    assert TestPlugin.started? instance

    assert [] = TestPlugin.getevs instance

    {:ok, instance} = Instance.stop instance.ref, [], server
    assert [{:stop, :normal}, {:stopping, nil}] = TestPlugin.getevs instance
    assert [] = TestPlugin.clearevs instance

    :ok = Instance.delete instance.ref, [], server
    assert [:delete] = TestPlugin.getevs instance
  end
end
