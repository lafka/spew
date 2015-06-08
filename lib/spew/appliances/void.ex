defmodule Spew.Appliances.Void do

  alias Spew.Appliance.Manager

  @moduledoc """
  A appliance runner that does nothing

  This is usefull for simulation as well as utilizing existing hooks
  for components not controlled directly by Spew
  """

  def run(appopts, _opts) do
    {:ok, [
      handler: __MODULE__,
      appliance: appopts,
      state: :running
    ]}
  end

  def stop(appcfg, _opts \\ []) do
    {parent, ref} = {self, make_ref}
    spawn fn ->
      send parent, {ref, :sync}
      send parent, {ref, Manager.await(appcfg[:appref], &(&1 == :stop))}
    end
    receive do {^ref, :sync} -> :ok
    after 2000 -> throw :timeout
    end

    p = :global.whereis_name Manager
    send p, {:event, appcfg[:appref], :stop}

    receive do {^ref, {:ok, :stop}} -> :ok
    after 2000 -> {:error, :timeout} end
  end

  def status(appcfg) do
    appcfg[:state]
  end
end
