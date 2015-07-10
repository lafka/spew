defmodule Spew.Runner.Void do
  use Spew.Plugin

  @moduledoc """
  A void runner that does not actually run anything
  """

  alias Spew.Instance.Item
  alias Spew.Utils.Time

  def capabilities, do: [
    :plugin
  ]

  def supported?, do: true

  def pid(%Item{plugin: %{__MODULE__ => %{pid: pid}}}), do: {:ok, pid}
  def pid(%Item{ref: ref}), do: {:error, {:no_pid, {:instance, ref}}}

  def run(%Item{ref: ref} = spec, _) do
    pid = spawn fn ->
      receive do
        {^ref, :stop} ->
          :ok
      end
    end
    plugins = Map.put spec.plugin, __MODULE__, %{pid: pid}
    {:ok, %{spec |
              state: {:running, Time.now(:milli_seconds)},
              plugin: plugins}}
  end

  def stop(%Item{state: {state, _}} = spec, _signal)
      when state in [:stopping, :stopped, :killed, :killing] do

    {:ok, spec}
  end
  def stop(%Item{state: {{:crashed, _}, _}} = spec, _signal), do:
    {:ok, spec}
  def stop(%Item{plugin: %{__MODULE__ => %{pid: pid}},
                 ref: ref} = spec,
           _signal) when is_pid(pid) do

    # just send it, if it's dead it should be monitored and we
    # should receive a :DOWN msg
    send pid, {ref, :stop}
    {:ok, %{spec | state: {:stopping, Time.now(:milli_seconds)}}}
  end
  def stop(%Item{ref: ref}, _signal) do
    {:error, {:no_pid, {:instance, ref}}}
  end

  def kill(%Item{plugin: %{__MODULE__ => %{pid: pid}}} = spec) when is_pid(pid) do
    Process.exit pid, :kill
    {:ok, %{spec | state: {:killing, Time.now(:milli_seconds)}}}
  end
  def kill(%Item{ref: ref, state: {_, _, _pid}}), do:
    {:error, {:no_pid, {:instance, ref}}}


  # Spew.Plugin Callback
  @doc """
  Plugin spec
  """
  def spec(_instance), do: []

  @doc """
  Plugin init, unused
  """
  def init(_instance, _plugin, _opts), do: {:ok, nil}

  @doc """
  Handle cleanup of self
  """
  def cleanup(_instance, _state, _opts), do: :ok

  @doc """
  Handle plugin events
  """
  def notify(_instance, _state, _ev), do: :ok
end
