defmodule Spew.Host do
  @moduledoc """
  Provide information about the connected spew hosts
  """

  @name __MODULE__.Server

  @doc """
  Query the host machines
  """
  def query(q \\ []), do: GenServer.call(@name, {:query, q})
  def get(node), do: GenServer.call(@name, {:get, node})

  @doc """
  Describe this host
  """
  def describe do
    {:ok, ifs} = :inet.getifaddrs

    ifaces = Enum.reduce ifs, [], fn
      ({:lo, _stats}, acc) ->
        acc

      ({iface, stats}, acc) ->
        cond do
          Enum.member? stats[:flags], :up ->
            [packiface(iface, stats) | acc]

          true ->
            acc
        end
    end

    %{
      name: node,
      inet: ifaces,
      builds: []
    }
  end

  defp packiface(iface, stats) do
    masksize = (stats[:netmask] || {})
      |> Tuple.to_list
      |> Enum.reduce("", fn(n, acc) -> Integer.to_string(n,2) <> acc end)
      |> String.replace("0", "")
      |> byte_size

    %{
      iface: iface,
      macaddr: stats[:hwaddr],
      netmask: {stats[:netmask], masksize},
      broadcast: stats[:broadaddr],
      ip: [stats[:addr]]
    }
  end

  defmodule Server do
    use GenServer

    require Logger

    alias Spew.Host

    @name __MODULE__

    def start_link() do
      GenServer.start_link(@name, %{}, [name: @name])
    end

    def init(state) do
      {:ok, Map.put(%{}, "#{node}", Host.describe)}
    end

    def handle_call({:query, []}, _from, state) do
      {:reply, Map.values(state), state}
    end

    def handle_call({:get, ref}, _from, state) do
      case state[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:host, ref}}}, state}

        host ->
          {:reply, {:ok, host}, state}
      end
    end

    def handle_info({:update_builds, node, builds}, state) do
      node = "#{node}"
      case state[node] do
        nil ->
          {:noreply, state}

        data ->
          Logger.debug "host[#{node}] updated builds"
          {:noreply, Dict.put(state, node, Dict.put(data, :builds, builds))}
      end
    end
  end
end
