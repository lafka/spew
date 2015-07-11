defmodule Spew.Plugin.Instance.Network do
  @moduledoc """
  Plugin to automatically allocate a network address
  """

  use Spew.Plugin

  require Logger

  alias Spew.Network
  alias Spew.Network.Slice
  alias Spew.Instance.Item

  @doc """
  Spec for Build plugin
  """
  def spec(%Item{}), do:
    [ ]

  @doc """
  Plugin init:
    - Ensure the network exists
  """
  def init(%Item{network: nil}, _plugin, _opts), do: {:ok, nil}
  def init(%Item{network: net} = instance, _plugin, opts) do
    Logger.debug "instance[#{instance.ref}]: init plugin #{__MODULE__}"
    case Spew.Network.get_by_name net, opts[Network.Server] || Network.server do
      {:ok, %Network{} = network} ->
        # network slice might not be setup yet so we wait for :start
        res = [network: network.ref,
               slice: nil,
               allocation: nil]

        # this is to give some flexibility during testing
        res = [
                {Spew.Network.Server, opts[Network.Server]},
                {:net_slice_owner, opts[:net_slice_owner]}
                | res]

        {:ok, res}

      {:error, _} = res ->
        res
    end
  end

  @doc """
  Cleanup build:
    - Ensure the allocation is removed from the network slice
  """
  def cleanup(_instance, _state, _opts) do
    Logger.debug "instance[#{_instance.ref}]: cleanup after plugin #{__MODULE__}"
  end

  @doc """
  Handle plugin events
    - on :start allocate the address
    - on {:stop, :normal} deallocate the address
    - on {:stop, {:crash, _}} keep the allocation so we respawn at same address
  """
  def notify(instance, state, :start) do
    netserver = state[Network.Server] || Network.server

    {:ok, slices} = Network.slices state[:network], netserver
    # find my slice
    match = state[:net_slice_owner] || node

    case Enum.filter(slices, fn(%Slice{owner: owner}) -> owner === match end) do
      [] ->
        {:error, {:noslice, state[:network]}}

      [slice] ->
        case Network.allocate slice.ref, {:instance, instance.ref}, netserver do
          {:ok, alloc} ->
            state = state
              |> Dict.put(:slice, slice.ref)
              |> Dict.put(:allocation, alloc)

            {:update, state}

          {:error, _} = res ->
            res
        end
    end
  end
  def notify(_instance, _state, _ev), do: :ok
end

