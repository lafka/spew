defmodule Spew.Network do
  @moduledoc """
  Support for automating network setup

  A network consists of:
    * `Network Space` :: Network - the ip range(s) available to a network
    * `Subnet Delegation` :: Slice - The subnet(s) of the Network Space delegated to a slice
    * `Subnet Claim` :: Slice - The size to claim for a Subnet Delegation
    * `IP Allocation` :: Allocation - A allocated ip within a Subnet Delegation

  Each Slice has a one-to-one mapping with a Spew host. The Subnet
  Delegation for that slice is given by mapping the `node` hash to
  the available addresses (subtracting the Subnet Claim from the
  available Network Space).

  Each Spew host runs a network server, this network server is
  responsible for setting up the bridge for that Slice. Routing
  between those is out of scope of this document, but it's assumed
  that all the bridges will enslave a device that connects them all.

  ## IP Allocation

  Once all the Spew hosts agree on a network topology, the Network
  server responsible for a Slice can allocate addresses. This is done
  in the manner as with Subnet Delegation where the hash of the
  claiming entity (ie. a instance) will be mapped to the available
  address space of that Slice. Again collisions are probable.
  """

  alias Spew.Utils
  alias Spew.Cluster

  alias __MODULE__

  @name __MODULE__.Server

  @doc """
  The network structure

  ## Fields

    * `:ref` - a unique string used to identify the network
    * `:name` - name the name of the network
    * `:iface` - the name of the iface to create
    * `:ranges` - the name of the iface
    * `:hosts` - list of nodes in the network
    * `:slices` - All the slices in this network
  """
  defstruct ref: nil,
            name: nil,
            iface: nil,
            ranges: [],
            hosts: %{},
            slices: %{}

  @type t :: %__MODULE__{
      ref: network,
      name: String.t,
      iface: String.t | nil,
      ranges: [Spew.Network.Slice.subnet],
      hosts: %{},
      slices: %{}
  }


  @typedoc """
  The unique reference to a network
  """
  @type network :: String.t


  def genref(term, true = _external?) do
    "net-" <> genref(term, false)
  end

  def genref(term, _full?) do
    Utils.hash(term) |> String.slice(0, 8)
  end

  def server, do: @name


  @doc """
  Create a new network
  """
  @spec create(%Network{}, GenServer.server) :: {:ok, %Network{}} | {:error, term}
  def create(%Network{} = network, server \\ @name) do
    Cluster.call server, {:create, network}
  end


  @doc """
  Get a network definition
  """
  @spec get(network, GenServer.server) :: {:ok, t} | {:error, term}
  def get("net-" <> network, server \\ @name) do
    Cluster.call server, {:get, network}
  end

  @doc """
  Get a network definition by it's name
  """
  @spec get_by_name(String.t, GenServer.server) :: {:ok, t} | {:error, term}
  def get_by_name(netname, server \\ @name) do
    Cluster.call server, {:get_by_name, netname}
  end

  @doc """
  Delete a network

  If the network have any slices this function will fail
  """
  @spec delete(network, GenServer.server) :: :ok | {:error, term}
  def delete("net-" <> network, server \\ @name) do
    Cluster.call server, {:delete, network}
  end


  @doc """
  List networks
  """
  @spec networks(GenServer.server) :: {:ok, [t]} | {:error, term}
  def networks(server \\ @name) do
    Cluster.call server, :list
  end


  @doc """
  Delegate a subnet in `network`

  ## Options

    * `owner :: term` The owning entity, defaults to node
    * `iface :: String.t | nil` The interface name to use, defaults to networks iface
  """
  @spec delegate(network, term, GenServer.server) :: {:ok, Spew.Network.Slice.t} | {:error, term}
  def delegate("net-" <> network, opts, server \\ @name) do
    Cluster.call server, {:delegate, network, opts}
  end


  @doc """
  Remove the delegated `slice` from `network`

  This is a async operation where the slice will be marked as inactive
  and no new ip allocations can be done. It's up to the caller to
  make all the allocations are disabled.

  Once all allocations are removed the slice will be deleted
  """
  @spec undelegate(Spew.Network.Slice.slice, GenServer.server) :: :ok | {:error, term}
  def undelegate("slice-" <> slice, server \\ @name) do
    Cluster.call server, {:undelegate, slice}
  end

  @doc """
  Get a network slice
  """
  @spec slice(Spew.Network.Slice.slice, GenServer.server) :: {:ok, [t]} | {:error, term}
  def slice("slice-" <> slice, server \\ @name) do
    Cluster.call server, {:getslice, slice}
  end

  @doc """
  List Network Slices
  """
  @spec slices(network, GenServer.server) :: {:ok, [t]} | {:error, term}
  def slices("net-" <> network, server \\ @name) do
    Cluster.call server, {:slices, network}
  end





  @doc """
  Allocate a IP for `owner` in `slice`

  If the allocation already exists AND it's state is inactive it will
  be reactivated
  """
  @spec allocate(Spew.Network.Slice.slice, Spew.Network.Allocation.owner, GenServer.server) :: {:ok, Spew.Network.Allocation.t} | {:error, term}
  def allocate("slice-" <> slice, owner, server \\ @name) do
    Cluster.call server, {:allocate, slice, owner}
  end


  @doc """
  Deallocate `ref`

  This is a async operation, the allocation is marked as inactive and
  should not be referenced by any services. Once the owner is dead
  it can safely be removed
  """
  @spec deallocate(Spew.Network.Allocation.allocation, GenServer.server) :: :ok | {:error, term}
  def deallocate("allocation-" <> allocation, server \\ @name) do
    Cluster.call server, {:deallocate, allocation}
  end

  @doc """
  Get a allocation
  """
  @spec allocation(Spew.Network.Allocation.allocation, GenServer.server) :: {:ok, Spew.Network.Allocation.t} | {:error, term}
  def allocation("allocation-" <> allocref, server \\ @name) do
    Cluster.call server, {:get_allocation, allocref}
  end

  @doc """
  List all allocations for either a
  """
  @spec allocations(Spew.Network.network | Spew.Network.Slice.slice, GenServer.server) :: {:ok, [Spew.Network.Allocation.t]} | {:error, term}
  def allocations(ref), do: allocations(ref, @name)
  def allocations("slice-" <> sliceref, server) do
    Cluster.call server, {:allocations, :slice, sliceref}
  end
  def allocations("net-" <> netref, server) do
    Cluster.call server, {:allocations, :network, netref }
  end




  defmodule Server do
    defmodule State do

      @doc """
      The Network server state

      ## Fields

        * `:networks :: %{ Spew.Network.network => Spew.Network.t}` - The network definitions
      """
      defstruct name: nil,
                networks: %{},
                cluster: nil

      @type t :: %__MODULE__{}

      @typep ref :: Network.network | Slice.slice | Allocation.allocation
      @typep types :: Network.t | Slice.t | Allocation.t

      alias __MODULE__
      alias Spew.Network
      alias Spew.Network.Slice
      alias Spew.Network.Allocation

      # All items are stored with two types of ref:
      # - external ref (ie slice-135ab5/fa93eb) stored in the object
      # - the partial ref (ie. fa93eb) used for lookup
      @doc """
      Lookup a item in the state by its external reference

      One can get any of the ancestors by changing the prefix:
        * `allocation-13ab5/fa93eb/31a993e` gets a allocation
        * `slice-13ab5/fa93eb/31a993e` gets the slice for the allocation
        * `net-13ab5/fa93eb/31a993e` gets the network for the allocation
      """
      @spec getbyref(ref, t) :: {:ok, types} | {:error, term}
      def getbyref("net-" <> ref,
                   %State{} = state) do

        [net | _] = String.split ref, "/"
        dobyref ref, [{:network, net}], state
      end

      def getbyref("slice-" <> ref,
                   %State{} = state) do

        [net, slice | _] = String.split ref, "/"
        dobyref ref, [{:network, net}, {:slice, slice}], state
      end

      def getbyref("allocation-" <> ref,
                   %State{} = state) do

        [net, slice, allocation] = String.split ref, "/"
        dobyref ref, [{:network, net}, {:slice, slice}, {:allocation, allocation}], state
      end

      def getbyref(ref, _state) do
        {:error, {:invalid_ref, ref}}
      end



      @doc """
      Update a item in the state by its external reference
      If the item does not previously exist it will be inserted anyway
      """
      @spec putbyref(ref, types, t) :: {:ok, t} | {:error, term}
      def putbyref("net-" <> ref,
                   newnet,
                   %State{} = state) do

        dobyref ref, [{:network, ref, newnet}], state, true
      end


      def putbyref("slice-" <> ref,
                   newslice,
                   %State{} = state) do
        [net, slice] = String.split ref, "/"
        dobyref ref,
                [{:network, net}, {:slice, slice, newslice}],
                state,
                true
      end


      def putbyref("allocation-" <> ref,
                   alloc,
                   %State{} = state) do

        [net, slice, allocation] = String.split ref, "/"
        dobyref ref,
                [{:network, net}, {:slice, slice}, {:allocation, allocation, alloc}],
                state,
                true
      end


      def putbyref(ref, _item, _state) do
        {:error, {:invalid_ref, ref}}
      end



      defp put_or_delete(items, ref, nil), do: Map.delete(items, ref)
      defp put_or_delete(items, ref, val), do: Map.put(items, ref, val)

      defp dobyref(ref, op, state), do:
        dobyref(ref, op, state, false)

      defp dobyref(_extref,
                   [{:network, netref, val}],
                   %State{networks: networks} = state,
                   true), do:

        {:ok, %{state | networks: put_or_delete(networks, netref, val)}}

      defp dobyref(_extref,
                   [{:slice, sliceref, val}],
                   %Network{slices: slices} = network,
                   true), do:

        {:ok, %{network | slices: put_or_delete(slices, sliceref, val)}}

      defp dobyref(_extref,
                   [{:allocation, ref, val}],
                   %Slice{allocations: allocs} = slice,
                   true), do:

        {:ok, %{slice | allocations: put_or_delete(allocs, ref, val)}}


      defp dobyref(extref,
                   [{:network, netref} | rest],
                   %State{networks: networks} = state,
                   keep?) do

        case networks[netref] do
          nil ->
            {:error, {:notfound, "net-" <> extref}}

          %Network{} = network when keep? ->
            maybe dobyref(extref, rest, network, keep?), fn(network) ->
              {:ok, %{state | networks: Map.put(networks, netref, network)}}
            end

          %Network{} = network ->
            dobyref extref, rest, network, keep?
        end
      end


      defp dobyref(extref,
                   [{:slice, sliceref} | rest],
                   %Network{slices: slices} = network,
                   keep?) do

        case slices[sliceref] do
          nil ->
            {:error, {:notfound, "slice-" <> extref}}

          %Slice{} = slice when keep? ->
            maybe dobyref(extref, rest, slice, keep?), fn(slice) ->
              {:ok, %{network | slices: Map.put(slices, sliceref, slice)}}
            end

          %Slice{} = slice ->
            dobyref extref, rest, slice, keep?
        end
      end


      defp dobyref(extref,
        [{:allocation, allocref} | rest],
        %Slice{allocations: allocations} = slice,
        keep?) do

        case allocations[allocref] do
          nil ->
            {:error, {:notfound, "allocation-" <> extref}}

          # this is the last level, no need to keep? anythign
          %Allocation{} = allocation when keep? ->
            maybe dobyref(extref, rest, allocation, keep?), fn(allocation) ->
              {:ok, %{slice | allocations: Map.put(slice, allocref, allocation)}}
            end

          %Allocation{} = allocation ->
            dobyref extref, rest, allocation, keep?
        end
      end

      defp dobyref(_extref, [], term, _keep?), do: {:ok, term}

      defp maybe({:ok, res}, fun), do: fun.(res)
      defp maybe({:error, _} = res, _fun), do: res
    end

    use GenServer
    use Spew.Cluster, synckeys: [:networks]

    alias Spew.Cluster

    alias Spew.Network
    alias Spew.Network.Slice
    alias Spew.Network.Allocation

    require Logger

    @name __MODULE__
    @cluster "network"

    def start(opts \\ []) do
      name = opts[:name] || @name
      initopts = Dict.put(opts[:init] || [], :name, name)

      GenServer.start __MODULE__,  initopts, [name: name]
    end

    def start_link(opts \\ []) do
      name = opts[:name] || @name
      initopts = Dict.put(opts[:init] || [], :name, name)

      GenServer.start_link __MODULE__,  initopts, [name: name]
    end

    def init(opts) do
      cluster = opts[:cluster] || @cluster
      state = Cluster.init(cluster) || %State{name: opts[:name] || node, cluster: cluster}

      networks = Enum.reduce opts[:networks] || [],
                             state.networks, fn
        (%Network{} = network, acc) ->
          ref = Network.genref network.name, false
          if acc[ref] do
            acc # keep previous definition
          else
            extref = Network.genref network.name, true
            ranges = Enum.map network.ranges, &Slice.parserange/1
            Map.put acc, ref, %{network | ref: extref, ranges: ranges}
          end

        (term, acc) ->
          Logger.warn "network[]: invalid network spec: #{inspect term}"
          acc
        end

      {:ok, %State{state | name: opts[:name] || node,
                           networks: networks}}
    end

    synckeys = [:networks]
    def handle_cast({:cluster_update, newstate}, oldstate) do
      r = Enum.reduce unquote(synckeys), oldstate, fn(k, acc) ->
        Map.put acc, k, Map.get(newstate, k)
      end
      {:noreply, r}
    end

    def handle_call(:cluster_state, _from, currentstate) do
      {:reply, {:ok, currentstate}, currentstate}
    end


    def handle_call({:create, %Network{ref: ref} = network},
                    _from,
                    %State{networks: networks} = state) do

      # ref may not be set, or might have an external ref set
      matchref = Network.genref network.name, false
      ref = String.replace ref || matchref, ~r/^net-/, ""
      refmatches? = ref == matchref

      case networks[ref] do
        _ when not refmatches? ->
          {:reply,
           {:error, {:invalid_ref, "net-" <> ref}},
           state}

        nil ->
          ranges = Enum.map network.ranges, &Slice.parserange/1
          network = %{network | ref: Network.genref(network.name, true), ranges: ranges}

          {:reply,
           {:ok, network},
           %{state | networks: Map.put(networks, ref, network)}}

        _network ->
          {:reply,
           {:error, {:conflict, "net-" <> ref}},
           state}
      end
    end


    def handle_call({:get,  ref},
                    _from,
                    %State{networks: networks} = state) do

      case networks[ref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> ref}},
           state}

        network ->
          {:reply,
           {:ok, network},
           state}
      end
    end


    def handle_call({:get_by_name,  name},
                    _from,
                    %State{networks: networks} = state) do

      case Enum.find networks, fn({_, %Network{name: match}}) -> match == name  end do
        nil ->
          {:reply,
           {:error, {:notfound, {:network_name, name}}},
           state}

        {_netref, network} ->
          {:reply,
           {:ok, network},
           state}
      end
    end

    def handle_call({:delete,  ref},
                    _from,
                    %State{networks: networks} = state) do

      case networks[ref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> ref}},
           state}

        %Network{slices: slices} when slices == %{} ->
          newstate = Cluster.sync state.cluster, %{state | networks: Map.delete(networks, ref)}
          {:reply,
           :ok,
           newstate}

        %Network{slices: _slices} ->
          {:reply,
           {:error, {:not_empty, "net-" <> ref}},
           state}
      end
    end


    def handle_call(:list,
                    _from,
                    %State{networks: networks} = state) do

      {:reply,
       {:ok, Map.values(networks)},
       state}
    end


    # @todo 2015-07-30 lafka; more options should be passed when
    # delegating subnet. for instance claim size - which will
    # significantly increase management work
    def handle_call({:delegate, netref, opts},
                    _from,
                    %State{networks: networks} = state) do

      case networks[netref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> netref}},
           state}

        %Network{} = network ->
          case Slice.delegate network, opts do
            {:ok, {sliceref, slice}} ->
              # Check for collision
              collisions = Enum.filter_map network.slices, fn({_sliceref, refslice}) ->
                  Enum.any? refslice.ranges, &Enum.member?(slice.ranges, &1)
                end,
                fn({_sliceeref, refslice}) ->
                  refslice.ref
                end

              case collisions do
                [] ->
                  network = %{network | slices: Map.put(network.slices, sliceref, slice)}
                  newstate = Cluster.sync state.cluster,
                                          %{state | networks: Map.put(networks, netref, network)}

                  {:reply,
                    {:ok, slice},
                    newstate}

                collisions ->
                  {:reply,
                   {:error, {:conflict, {:slices, collisions}, "net-" <> netref}},
                   state}
              end


            {:error, _} = err ->
              {:reply,
               err,
               state}
          end
      end
    end


    def handle_call({:undelegate, sliceref},
                    _from,
                    %State{} = state) do

      alias Spew.Utils.Net.Iface

      case State.getbyref "slice-" <> sliceref, state do
        {:ok, %Slice{allocations: allocs} = slice} when 0 == map_size(allocs) ->
          {:ok, %Network{ref: "net-" <> netref} = network}
            = State.getbyref "net-" <> sliceref, state
          iface = slice.iface || network.iface || netref

          Iface.remove_bridge iface

          {:ok, %State{} = newstate} = State.putbyref slice.ref, nil, state
          newstate = Cluster.sync state.cluster, newstate

          {:reply,
           {:ok, %{slice | active: false}},
           newstate}

        {:ok, %Slice{} = slice} ->
          {:ok, %State{} = newstate} = State.putbyref slice.ref, %{slice | active: false}, state
          newstate = Cluster.sync state.cluster, newstate

          {:reply,
           {:ok, %{slice | active: false}},
           newstate}
      end
    end


    def handle_call({:getslice, sliceref},
                    _from,
                    %State{} = state) do

      case State.getbyref "slice-" <> sliceref, state do
        {:ok, %Slice{} = slice} ->
          {:reply,
           {:ok, slice},
           state}

        {:error, _} = err ->
          {:reply,
           err,
           state}
      end
    end


    def handle_call({:slices, netref},
                    _from,
                    %State{networks: networks} = state) do

      case networks[netref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> netref}},
           state}

        %Network{slices: slices} ->
          {:reply,
           {:ok, Map.values(slices)},
           state}
      end
    end


    def handle_call({:allocate, sliceref, owner},
                    _from,
                    %State{} = state) do

      alias Spew.Utils.Net.Iface
      case State.getbyref "slice-" <> sliceref, state do
        {:ok, %Slice{} = slice} ->
          case Allocation.allocate slice, owner do
            {:ok, allocation} ->
              {:ok, %Network{ref: "net-" <> netref} = network}
                = State.getbyref "net-" <> sliceref, state

              iface = slice.iface || network.iface || netref
              case Iface.ensure_bridge iface, slice.ranges do
                :ok ->
                  {:ok, newstate} = State.putbyref allocation.ref, allocation, state
                  newstate = Cluster.sync state.cluster, newstate

                  {:reply,
                   {:ok, allocation},
                   newstate}

                {:error, {{:cmdexit, n}, cmd, buf}} ->
                  Logger.error """
                  network[#{netref}]: failed to setup bridge
                    iface: #{iface}
                    exec: #{Enum.join(cmd, " ")}
                    exit-status: #{n}
                    output:
                      #{String.replace(buf, ~r/\n/, "\n\t")}
                  """

                  {:reply,
                   {:error, {:netbridge, network.ref}},
                   state}

                {:error, _} = err ->
                  {:reply,
                   err,
                   state}
              end

            {:error, _} = err ->
              {:reply,
               err,
               state}
          end

        {:error, _} = err ->
          {:reply,
           err,
           state}
      end
    end


    def handle_call({:deallocate, allocref},
                    _from,
                    %State{} = state) do

      alias Spew.Utils.Net.Iface

      case State.getbyref "allocation-" <> allocref, state do
        {:ok, %Allocation{} = alloc} ->
          {:ok, newstate} = State.putbyref "allocation-" <> allocref, nil, state

          # check if we should unprovision slice
          {:ok, %Slice{} = slice} = State.getbyref "slice-" <> allocref, newstate
          {:ok, %Network{ref: "net-" <> netref} = network}
            = State.getbyref "net-" <> allocref, newstate

          iface = slice.iface || network.iface || netref
          case {map_size(slice.allocations), slice.active} do
            {0, true} ->
              Iface.remove_addrs iface, slice.ranges

            {0, false} ->
              Iface.remove_bridge iface

            _ ->
              :ok
          end

          newstate = Cluster.sync state.cluster, newstate

          {:reply,
           {:ok, Allocation.disable(alloc)},
           newstate}

        {:error, _} = err ->
          {:reply,
           err,
           state}
      end
    end

    def handle_call({:get_allocation, allocation},
                    _from,
                    %State{} = state) do

      case State.getbyref "allocation-" <> allocation, state do
        {:ok, %Allocation{} = alloc} ->
          {:reply,
           {:ok, alloc},
           state}

        {:error, _} = err ->
          {:reply,
           err,
           state}
      end
    end

    def handle_call({:allocations, :network, netref},
                    _from,
                    %State{networks: networks} = state) do

      case networks[netref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> netref}},
           state}

        %Network{slices: slices} ->
          allocations = Enum.flat_map slices, fn({_sref, %Slice{} = slice}) ->
                          Map.values slice.allocations
                        end
          {:reply,
           {:ok, Enum.sort(allocations)},
           state}
      end
    end

    def handle_call({:allocations, :slice, sliceref},
                    _from,
                    %State{} = state) do

      case State.getbyref "slice-" <> sliceref, state do
        {:ok, %Slice{} = slice} ->
          {:reply,
           {:ok, Enum.sort(Map.values(slice.allocations))},
           state}

        {:error, _} = err ->
          {:reply,
           err,
           state}
      end
    end
  end
end
