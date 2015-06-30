defmodule Spew.InstancePlugin.Discovery do
  @moduledoc """
  Instance plugin to handle discovery

  Keeps an up-to-date record of externally consumable information
  like host interfaces, running services etc
  """

  alias Spew.Discovery

  def handle(instance, {:init, ref}) do
    {:update, Spew.Discovery.item}
  end

  def handle(instance, {:exit, ref, _}) do
    {:update, %{}}
  end

  def handle(instance, _) do
    :ok
  end
end

