defmodule Spew.InstancePlugin.Discovery do
  @moduledoc """
  Instance plugin to handle discovery

  Keeps an up-to-date record of externally consumable information
  like host interfaces, running services etc
  """

  alias Spew.Discovery

  def event(instance, _state, {:init, ref}) do
    {:update, Spew.Discovery.item}
  end

  def event(instance, _state, {:exit, ref, _}) do
    {:update, %{}}
  end

  def event(instance, _state, _ev) do
    :ok
  end
end

