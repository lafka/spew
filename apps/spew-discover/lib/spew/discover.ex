defmodule Spew.Discover do
  @moduledoc """
  API to discovery service

  The discovery service works on top of the Instance API by reading
  information from the individual
  """

  @name __MODULE__.Server

  @states [
    "running",
    "waiting",
    "stopped",
    "crashed",
    "unknown"
  ]

  @doc """
  Add a new item
  """
  def add(ref, %{} = item), do: GenServer.call(@name, {:add, item})

  @doc """
  Delete an existing item
  """
  def delete(ref), do: GenServer.call(@name, {:delete, ref})

  if Mix.env in [:test, :dev] do
    def flush, do: GenServer.call(@name, :flush)
  end
end
