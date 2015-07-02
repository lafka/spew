defmodule Spew.Network.InetAllocator do
  @moduledoc """
  Handles IP allocation for instances

  This is an alternative to running a DHCP server and it's primarily
  used with the SystemdNspawn runner.
  """

  @name __MODULE__.Server
  def server, do: @name

  @doc """
  Allocates a ip address
  """
  def allocate(network, forwho?, server \\ @name) do
    GenServer.call server, {:allocate, network, forwho?}
  end

  @doc """
  Removes a previously defined allocation
  """
  def deallocate(ref, server \\ @name) do
    GenServer.call server, {:deallocate, ref}
  end

  @def """
  Retrieve a allocation by it's `ref`
  """
  def get(ref, server \\ @name) do
    GenServer.call server, {:get, ref}
  end

  @def """
  Find a allocated ip by some query

  The query is a tuple like `{:host, node()}`, or `{:owner,
  owner()}` or nil to list all
  """
  def query(query, server \\ @name) do
    GenServer.call server, {:query, query}
  end

  defmodule Allocation do
    defstruct ref: nil,
              owner: {:instance, nil},
              host: nil, # the host that owns the allocation
              network: nil,
              addrs: []
  end

  defmodule Server do
    use GenServer

    require Logger

    use Bitwise

    defmodule State do
      defstruct allocations: %{},
                files: []

      def read_hosts(%State{allocations: table, files: files} = state, file) do
        {:ok, state}
      end
    end

    defmodule AlreadyAllocated do
      defexception message: "address allocated",
                   addr: nil,
                   by: nil
    end

    @name __MODULE__

    alias Spew.Network
    alias Spew.Network.InetAllocator.Allocation
    alias Spew.Utils.Net.InetAddress
    alias Spew.Utils.Net.Iface
    def start_link(opts \\ []) do
      name = opts[:name] || @name
      initopts = opts[:init] || []
      GenServer.start_link(__MODULE__, initopts, [name: name])
    end

    def init(opts) do
      # pre allocate the spew host
      allocations = Enum.into Network.networks, %{}, fn({net, iface}) ->
        ref = Spew.Utils.hash({:network, net})

        %Iface{addrs: addrs} = Iface.stats iface

        {ref, %Allocation{
          ref: ref,
          host: node,
          owner: :spew,
          network: net,
          addrs: Enum.map(addrs, fn({k, v}) -> {v[:addr], v[:netmask]} end)
        }}
      end

      state = %State{allocations: allocations}

      case opts[:hosts] || Application.get_env(:spew, :provision)[:hosts] do
        nil ->
          Logger.warn "inetallocator: no allocation file defined"
          {:ok, state}

        file ->
          if File.exits? file do
            Logger.info "inetallocator: reading allocation file#{file}"
            State.read_hosts state, file
          else
            File.mkdir_p! Path.dirname(file)
            File.touch! file
            Logger.info "inetallocator: created allocation file #{file}"
            State.read_hosts state, file
          end
      end
    end

    def handle_call({:allocate, network, who}, _from, state) do
      case Network.range network do
        {:ok, %{ranges: ranges}} ->
          addrs = Enum.map ranges, fn({range, mask}) ->
            netsize = :math.pow(2, (spacesize(range) - mask)) |> :erlang.trunc
            netmax = netsize - 3 # space for gw and broadcast

            hash = :crypto.hash(:sha, :erlang.term_to_binary(who))
              |> :binary.decode_unsigned

            where = (hash &&& (netmax - 1)) + 2

            addr = InetAddress.increment range, where
            case Enum.filter state.allocations,
                             fn({ref, %Allocation{addrs: addrs}}) ->
                               Enum.member? addrs, {addr, mask}
                             end do

              [{ref, %{owner: owner}}] when owner !== who ->
                raise AlreadyAllocated, message: "address allocated",
                                        addr: addr,
                                        by: {ref, owner}

              # if the address is already allocated by same owner
              # the ref generated SHOULD be the same, no need to error
              _ ->
                {addr, mask}
            end
          end

          ref = Spew.Utils.hash(addrs)
          allocation = %Allocation{ref: ref,
                                   addrs:  addrs,
                                   owner: who,
                                   network: network,
                                   host: node}

          straddrs = Enum.map(addrs, fn({addr, mask}) ->
            InetAddress.to_string(addr) <> "/#{mask}"
          end) |> Enum.join(", ")
          Logger.info "network[#{network}]: allocating #{straddrs} to #{ref}"

          {:reply,
            {:ok, allocation},
            %{state | allocations: Map.put(state.allocations, ref, allocation)}}

        {:error, {:input, :range_or_claim_missing, {:network, _}}} ->
          {:reply, {:error, :invalidcfg, {:network, network}}, state}

        {:error, _} = err ->
          {:reply, err, state}
      end
    rescue e in AlreadyAllocated ->
      {:reply, {:error, {:already_allocated, {:addr, e.addr}}}, state}
    end

    def handle_call({:deallocate, ref}, _from, state) do
      case state.allocations[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:inetallocation, ref}}}, state}

        allocation ->
          Logger.debug "network[#{allocation.network}]: deallocating #{allocation.ref}"
          {:reply, :ok, %{state | allocations: Map.delete(state.allocations, ref)}}
      end
    end

    def handle_call({:get, ref}, _from, state) do
      case state.allocations[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:inetallocation, ref}}}, state}

        allocation  ->
          {:reply, {:ok, allocation}, state}
      end
    end

    def handle_call({:query, nil}, _from, state) do
      {:reply, {:ok, state.allocations}, state}
    end
    def handle_call({:query, {k, v}}, _from, state) do
      res = Enum.filter_map state.allocations,
                            fn({ref, %Allocation{} = allocation}) ->
                              Map.get(allocation, k) === v
                            end,
                            fn({_, allocation}) -> allocation end

      {:reply, {:ok, res}, state}
    end

    defp spacesize({_,_,_,_}), do: 32
    defp spacesize({_,_,_,_,_,_,_,_}), do: 128
  end
end
