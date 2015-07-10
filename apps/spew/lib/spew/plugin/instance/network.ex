defmodule Spew.Plugin.Instance.Network do
  @moduledoc """
  Plugin to automatically allocate a network address
  """

  use Spew.Plugin

  require Logger

  alias Spew.Network
  alias Spew.Instance.Item

  @doc """
  Spec for Build plugin
  """
  def spec(%Item{}), do:
    [ ]

  @doc """
  Plugin init:
    - Ensure the network and the slice is setup
  """
  def init(%Item{network: nil}, _plugin, _opts), do: {:ok, nil}
  def init(%Item{network: net} = instance, _plugin, opts) do
    Logger.debug "instance[#{instance.ref}]: init plugin #{__MODULE__}"
    case Spew.Network.get_by_name net, opts[Network] || Network.server do
      {:ok, %Network{} = network} ->
        IO.inspect network
        {:ok, "net-" <> net}

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
  def notify(_instance, _state, _ev), do: :ok
  def notify(_instance, _state, _ev), do: :ok
end

