defmodule SpewPluginTest do
  use ExUnit.Case

  alias Spew.Plugin

  test "plugins" do
    defmodule BasicPlugin do
      use Spew.Plugin

      def spec(SpewPluginTest), do: []

      def init(SpewPluginTest, nil, _opts) do
        {:ok, spawn fn -> loop end}
      end

      def loop, do: loop([])
      def loop(events) do
        receive do
          {:ev, ev} ->
            loop [ev | events]

          {:get, {from, ref}} ->
            send from, {ref, Enum.reverse(events)}
            loop []

          {:stop, {from, ref}} ->
            send from, {ref, :stop}
            :ok
        end
      end

      def notify(SpewPluginTest, pid, ev) do
        send pid, {:ev, ev}
        :ok
      end

      def cleanup(SpewPluginTest, pid, _opts) do
        ref = make_ref
        send pid, {:stop, {self, ref}}
        receive do
          {^ref, :stop} ->
            :ok
        after 1000 ->
          exit(:timeout)
        end
      end
    end

    {:ok, plugins} = Plugin.init __MODULE__, [BasicPlugin]
    {:ok, plugins} = Plugin.notify __MODULE__, plugins, :hello
    {:ok, plugins} = Plugin.notify __MODULE__, plugins, :you

    ref = make_ref
    send plugins[BasicPlugin], {:get, {self, ref}}
    assert_receive {^ref, [:hello, :you]}

    monref = Process.monitor plugins[BasicPlugin]
    :ok = Plugin.cleanup __MODULE__, plugins

    assert_receive {:DOWN, ^monref, :process, _pid, :normal}
  end

  test "plugin order" do
    # Can run anywhere
    defmodule PluginA do
      use Spew.Plugin

      def spec(_), do: [ ]
      def init(_caller, _plugin, _opts) do
        Process.put({__MODULE__, :init}, t = :erlang.monotonic_time)
        {:ok, t}
      end
      def notify(_caller, _state, _ev), do: :ok
      def cleanup(_caller, _state, _opts), do: Process.put({__MODULE__, :cleanup}, :erlang.monotonic_time)
    end

    # This will run B unless A is enabled, then A will run first
    defmodule PluginB do
      use Spew.Plugin

      def spec(_), do: [ after: [PluginA] ]
      def init(_caller, _plugin, _opts) do
        Process.put({__MODULE__, :init}, t = :erlang.monotonic_time)
        {:ok, t}
      end
      def notify(_caller, _state, _ev), do: :ok
      def cleanup(_caller, _state, _opts), do: Process.put({__MODULE__, :cleanup}, :erlang.monotonic_time)
    end

    # This will run C, A, B
    defmodule PluginC do
      use Spew.Plugin

      def spec(_), do: [ require: [PluginB],
                         before: [PluginA] ]
      def init(_caller, _plugin, _opts) do
        Process.put({__MODULE__, :init}, t = :erlang.monotonic_time)
        {:ok, t}
      end
      def notify(_caller, _state, _ev), do: :ok
      def cleanup(_caller, _state, _opts), do: Process.put({__MODULE__, :cleanup}, :erlang.monotonic_time)
    end

    # this should run A, then B, and afterwards C, D in any order
    defmodule PluginD do
      use Spew.Plugin

      def spec(_), do: [ require: [PluginA, PluginC,],
                         after: [PluginB] ]
      def init(_caller, _plugin, _opts) do
        Process.put({__MODULE__, :init}, t = :erlang.monotonic_time)
        {:ok, t}
      end
      def notify(_caller, _state, _ev), do: :ok
      def cleanup(_caller, _state, _opts), do: Process.put({__MODULE__, :cleanup}, :erlang.monotonic_time)
    end

    {:ok, plugins} = Plugin.init __MODULE__, [PluginD]

    assert [PluginC, PluginA, PluginB, PluginD] == Enum.sort(plugins, fn({_, a}, {_, b}) -> a < b end) |> Dict.keys

    # Cleanup should be called in reverse order
    :ok = Plugin.cleanup __MODULE__, plugins
    assert [PluginD, PluginB, PluginA, PluginC] == Enum.map(
        plugins,
        fn({plugin, _}) -> {plugin,Process.get({plugin, :cleanup})}
      end)
      |> Enum.sort(fn({_, a}, {_, b}) -> a < b end)
      |> Dict.keys

    {:ok, plugins} = Plugin.init __MODULE__, [PluginA, PluginB]
    assert [PluginA, PluginB] == Enum.sort(plugins, fn({_, a}, {_, b}) -> a < b end) |> Dict.keys
  end

  test "plugin order - circular" do
    # Both want the requirement to run before, we should die
    defmodule CircularPlugin1 do
      use Spew.Plugin

      def spec(_), do: [ after: [SpewPluginTest.CircularPlugin2],
                         require: [SpewPluginTest.CircularPlugin2] ]
      def init(_caller, _plugin, _opts) do
        Process.put({__MODULE__, :init}, t = :erlang.monotonic_time)
        {:ok, t}
      end
      def notify(_caller, _state, _ev), do: :ok
      def cleanup(_caller, _state, _opts), do: Process.put({__MODULE__, :cleanup}, :erlang.monotonic_time)
    end

    defmodule CircularPlugin2 do
      use Spew.Plugin

      def spec(_), do: [ after: [CircularPlugin1],
                         require: [CircularPlugin1] ]
      def init(_caller, _plugin, _opts) do
        Process.put({__MODULE__, :init}, t = :erlang.monotonic_time)
        {:ok, t}
      end
      def notify(_caller, _state, _ev), do: :ok
      def cleanup(_caller, _state, _opts), do: Process.put({__MODULE__, :cleanup}, :erlang.monotonic_time)
    end

    assert {:error, {:deps, %{
      CircularPlugin1 => [CircularPlugin2],
      CircularPlugin2 => [CircularPlugin1]
    }}} = Plugin.init __MODULE__, [CircularPlugin2]

    assert {:error, {:deps, %{
      CircularPlugin1 => [CircularPlugin2],
      CircularPlugin2 => [CircularPlugin1]
    }}} = Plugin.init __MODULE__, [CircularPlugin1]

    assert {:error, {:deps, %{
      CircularPlugin1 => [CircularPlugin2],
      CircularPlugin2 => [CircularPlugin1]
    }}} = Plugin.init __MODULE__, [CircularPlugin1, CircularPlugin2]
  end
end
