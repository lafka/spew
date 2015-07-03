defmodule Spew.Plugin.Instance.Build do
  @moduledoc """
  Plugin to automatically verify, unpack builds and cleanup builds
  """

  use Spew.Plugin

  require Logger

  alias Spew.Instance.Item

  @doc """
  Spec for Build plugin
  """
  def spec(%Item{}) do
    alias Spew.Plugin.Instance.OverlayMount

    [
      require: [OverlayMount], # If we have a build we have a overlay
      before:  [OverlayMount] # run before on load, and after on cleanup
    ]
  end

  @doc """
  Plugin init:
    - verify build
    - async unpack
  """
  def init(_instance, _opts) do
    Logger.debug "instance[#{_instance.ref}]: init plugin #{__MODULE__}"
    {:ok, nil}
  end

  @doc """
  Cleanup build:
    - remove the actual build
  """
  def cleanup(_instance, _state) do
    Logger.debug "instance[#{_instance.ref}]: cleanup after plugin #{__MODULE__}"
    :ok
  end

  @doc """
  Handle plugin events
  """
  def notify(_instance, _state, _ev), do: :ok
end
