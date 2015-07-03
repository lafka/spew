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


  @doc """
  Create a new network
  """
  @spec create(%Network{}, GenServer.server) :: {:ok, %Network{}} | {:error, term}
  def create(%Network{} = network, server \\ @name) do
    GenServer.call server, {:create, network}
  end


  @doc """
  Get a network definition
  """
  @spec get(network, GenServer.server) :: {:ok, t} | {:error, term}
  def get("net-" <> network, server \\ @name) do
    GenServer.call server, {:get, network}
  end


  @doc """
  Delete a network

  If the network have any slices this function will fail
  """
  @spec delete(network, GenServer.server) :: :ok | {:error, term}
  def delete("net-" <> network, server \\ @name) do
    GenServer.call server, {:delete, network}
  end


  @doc """
  List networks
  """
  @spec networks(GenServer.server) :: {:ok, [t]} | {:error, term}
  def networks(server \\ @name) do
    GenServer.call server, :list
  end


  @doc """
  Join GenServer identified by `serverref` to `network`, if such network exists
  """
  @spec join(GenServer.server, network, GenServer.server) :: :ok | {:error, term}
  def join(remoteserver, "net-" <> network, server  \\ @name) do
    GenServer.call server, {:join, remoteserver, network}
  end


  @doc """
  Remove `serverref_or_pid` from `network`, if such network exists
  """
  @spec leave(String.t | GenServer.server, network, GenServer.server) :: :ok | {:error, term}
  def leave(serverref_or_pid, "net-" <> network, server  \\ @name) do
    GenServer.call server, {:leave, serverref_or_pid, network}
  end

  @doc """
  Show status of siblings server for `network`

  The returned map will show %{ serverref => :ok | :down } where :ok
  means no down message have been received yet.
  """
  @spec cluster(network,  GenServer.server) :: {:ok, %{}} | {:error, term}
  def cluster("net-" <> network, server \\ @name) do
    GenServer.call server, {:cluster, network}
  end




  @doc """
  Delegate a subnet in `network` to `host`
  """
  @spec delegate(network, term, GenServer.server) :: {:ok, Spew.Network.Slice.t} | {:error, term}
  def delegate("net-" <> network, forwho, server \\ @name) do
    GenServer.call server, {:delegate, network, forwho}
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
    GenServer.call server, {:undelegate, slice}
  end

  @doc """
  Get a network slice
  """
  @spec slice(Spew.Network.Slice.slice, GenServer.server) :: {:ok, [t]} | {:error, term}
  def slice("slice-" <> slice, server \\ @name) do
    GenServer.call server, {:getslice, slice}
  end

  @doc """
  List Network Slices
  """
  @spec slices(network, GenServer.server) :: {:ok, [t]} | {:error, term}
  def slices("net-" <> network, server \\ @name) do
    GenServer.call server, {:slices, network}
  end





  @doc """
  Allocate a IP for `owner` in `slice`

  If the allocation already exists AND it's state is inactive it will
  be reactivated
  """
  @spec allocate(Spew.Network.Slice.slice, Spew.Network.Allocation.owner, GenServer.server) :: {:ok, Spew.Network.Allocation.t} | {:error, term}
  def allocate("slice-" <> slice, owner, server \\ @name) do
    GenServer.call server, {:allocate, slice, owner}
  end


  @doc """
  Deallocate `ref`

  This is a async operation, the allocation is marked as inactive and
  should not be referenced by any services. Once the owner is dead
  it can safely be removed
  """
  @spec deallocate(Spew.Network.Allocation.allocation, GenServer.server) :: :ok | {:error, term}
  def deallocate("allocation-" <> allocation, server \\ @name) do
    GenServer.call server, {:deallocate, allocation}
  end

  @doc """
  Get a allocation
  """
  @spec allocation(Spew.Network.Allocation.allocation, GenServer.server) :: {:ok, Spew.Network.Allocation.t} | {:error, term}
  def allocation("allocation-" <> allocref, server \\ @name) do
    GenServer.call server, {:get_allocation, allocref}
  end

  @doc """
  List all allocations for either a
  """
  @spec allocations(Spew.Network.network | Spew.Network.Slice.slice, GenServer.server) :: {:ok, [Spew.Network.Allocation.t]} | {:error, term}
  def allocations(ref), do: allocations(ref, @name)
  def allocations("slice-" <> sliceref, server) do
    GenServer.call server, {:allocations, :slice, sliceref}
  end
  def allocations("net-" <> netref, server) do
    GenServer.call server, {:allocations, :network, netref }
  end




  defmodule Server do
    defmodule State do

      @doc """
      The Network server state

      ## Fields

        * `:networks :: %{ Spew.Network.network => Spew.Network.t}` - The network definitions
      """
      defstruct name: nil,
                networks: %{}

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
      """
      @spec getbyref(ref, t) :: {:ok, types} | {:error, term}
      def getbyref("slice-" <> ref,
                   %State{} = state) do

        [net, slice] = String.split ref, "/"
        dobyref ref, [{:network, net}, {:slice, slice}], state
      end


      def getbyref("net-" <> ref,
                   %State{} = state) do

        dobyref ref, [{:network, ref}], state
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

    alias Spew.Network
    alias Spew.Network.Slice
    alias Spew.Network.Allocation

    require Logger

    @name __MODULE__

    def start(opts \\ []) do
      name = opts[:name] || @name
      initopts = opts[:init] || []

      GenServer.start __MODULE__,  initopts, [name: name]
    end

    def start_link(opts \\ []) do
      name = opts[:name] || @name
      initopts = opts[:init] || []

      GenServer.start_link __MODULE__,  initopts, [name: name]
    end

    def init(opts) do
      networks = Enum.reduce opts[:networks] || [],
                             %State{}.networks, fn
                              (%Network{} = network, acc) ->
                                ref = Network.genref network.name, false
                                extref = Network.genref network.name, true

                                ranges = Enum.map network.ranges, &Slice.parserange/1

                                Map.put acc, ref, %{network | ref: extref, ranges: ranges}

                              (term, acc) ->
                                Logger.warn "network[]: invalid network spec: #{inspect term}"
                                acc
                              end

      {:ok, %State{name: opts[:name] || node,
                   networks: networks}}
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

          syncnet state.name, network

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

    def handle_call({:delete,  ref},
                    _from,
                    %State{networks: networks} = state) do

      case networks[ref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> ref}},
           state}

        %Network{slices: slices} when slices == %{} ->
          {:reply,
           :ok,
           %{state | networks: Map.delete(networks, ref)}}

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


    def handle_call({:join, remote, ref},
                    _from,
                    %State{networks: networks} = state) when remote === self do

      # we are joining ourselves, append and update the remote notes
      case networks[ref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> ref}},
           state}

        %Network{hosts: hosts} = network ->
          network = %{network | hosts: Map.put(hosts, state.name, {self, :ok})}
          syncnet state.name, network

          {:reply,
           :ok,
           %{state | networks: Map.put(networks, ref, network)}}
      end
    end

    def handle_call({:join, remote, netref},
                    _from,
                    %State{networks: networks} = state) do

      netcopy = networks[netref]

      case Network.get "net-" <> netref, remote do
        {:error, {:notfound, "net-" <> ^netref}} when nil === netcopy ->
          {:reply,
           {:error, {:notfound, "net-" <> netref}},
           state}

        {:error, {:notfound, "net-" <> ^netref}} ->
          Logger.debug "network[#{netcopy.ref}]: pushing to remote #{inspect remote}"
          {:error, {:notfound, name, _}} = Network.cluster "net-" <> netref, remote
          network = %{netcopy | hosts: Map.put(netcopy.hosts, name, {remote, :ok})}
          Process.monitor remote

          syncnet state.name, network

          {:reply,
           :ok,
           %{state | networks: Map.put(networks, netref, network)}}

        {:ok, %Network{} = network} when netcopy ->
          Logger.debug "network[#{network.ref}]: merging #{inspect self} with #{inspect remote}"
          {:ok, newnet} = mergenet network, netcopy

          Enum.each newnet.hosts, fn({name, {remote, remstate}}) ->
            :ok === remstate && nil === netcopy.networks[name] && Process.monitor remote
          end

          syncnet state.name, network

          {:reply,
           :ok,
           %{state | networks: Map.put(networks, netref, newnet)}}

        {:ok, %Network{hosts: hosts} = network} ->
          Logger.debug "network[#{network.ref}]: synced from remote #{inspect remote}"
          Enum.each hosts, fn({name, {remote, remstate}}) ->
            Logger.debug "network[#{network.ref}]: #{state.name} monitoring #{name}"
            :ok === remstate && Process.monitor remote
          end

          network = %{network | hosts: Map.put(hosts, state.name, {self, :ok})}

          syncnet state.name, network

          {:reply,
           :ok,
           %{state | networks: Map.put(networks, netref, network)}}
      end
    end


    def handle_call({:cluster, ref},
                    _from,
                    %State{networks: networks} = state) do

      case networks[ref] do
        nil ->
          {:reply,
           {:error, {:notfound, state.name, "net-" <> ref}},
           state}

        %Network{hosts: hosts} ->
          {:reply,
           {:ok, state.name, hosts},
           state}
      end
    end


    # @todo 2015-07-30 lafka; more options should be passed when
    # delegating subnet. for instance claim size - which will
    # significantly increase management work
    def handle_call({:delegate, netref, forwho},
                    _from,
                    %State{networks: networks} = state) do

      case networks[netref] do
        nil ->
          {:reply,
           {:error, {:notfound, "net-" <> netref}},
           state}

        %Network{} = network ->
          case Slice.delegate network, forwho do
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
                  syncnet state.name, network
                  {:reply,
                    {:ok, slice},
                    %{state | networks: Map.put(networks, netref, network)}}

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

      case State.getbyref "slice-" <> sliceref, state do
        {:ok, %Slice{allocations: allocs} = slice} when 0 == map_size(allocs) ->
          {:ok, %State{} = newstate} = State.putbyref slice.ref, nil, state
          {:reply,
           {:ok, %{slice | active: false}},
           newstate}

        {:ok, %Slice{} = slice} ->
          {:ok, %State{} = newstate} = State.putbyref slice.ref, %{slice | active: false}, state
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

      case State.getbyref "slice-" <> sliceref, state do
        {:ok, %Slice{allocations: allocs} = slice} ->
          case Allocation.allocate slice, owner do
            {:ok, allocation} ->
              {:ok, newstate} = State.putbyref allocation.ref, allocation, state
              {:reply,
               {:ok, allocation},
               newstate}

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

      case State.getbyref "allocation-" <> allocref, state do
        {:ok, %Allocation{} = alloc} ->
          {:ok, newstate} = State.putbyref "allocation-" <> allocref, nil, state
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


    def handle_cast({:update, :networks, ref, network},
                    %State{networks: networks} = state) do

      Logger.debug "network[#{network.ref}]: #{state.name} received sync request"

      hosts = networks[ref] && networks[ref].hosts || %{}
      Enum.each network.hosts, fn({name, {remote, remstate}}) ->
        if ! hosts[name] and name !== state.name do
          Logger.debug "network[#{network.ref}]: #{state.name} joined #{name} (state: #{remstate})"
          :ok === remstate && Process.monitor remote
        end
      end

      {:noreply, %{state | networks: Map.put(networks, ref, network)}}
    end


    def handle_info({:DOWN, _monref, :process, pid, _},
                    %State{networks: networks} = state) do

      networks = Enum.into networks, %{}, fn({ref, network}) ->
        hosts = Enum.into network.hosts, %{}, fn({name, {rempid, remstate}}) ->
          Logger.debug "checking if #{inspect pid} == #{inspect rempid}"
          if pid === rempid do
            Logger.warn "network[#{ref}]: server #{name} dropped out"
            {name, {rempid, :down}}
          else
            {name, {rempid, remstate}}
          end
        end

        {ref, %{network | hosts: hosts}}
      end

      {:noreply, %{state | networks: networks}}
    end


    defp syncnet(caller, %Network{ref: "net-" <> ref} = network) do
      Enum.each network.hosts, fn
        ({_name, {remote, _}}) when remote === self ->
          :ok

        ({name, {remote, :ok}}) ->
          Logger.debug "network[#{ref}]: #{name} joining #{caller}"
          GenServer.cast remote, {:update, :networks, ref, network}

        ({name, {_remote, :down}}) ->
          Logger.debug "network[#{ref}]: not pushing state to dead server #{name}"
      end
    end

    # try to do an intelligent merge
    # the only things we care about is that hosts and slices are updated
    # and if ranges don't add up we assume that `a` is correct since
    # it's from the existing network. If any slices fall out of the
    # potential new range we will ignore them for now.
    defp mergenet(a, b) do
      if a.ranges !== b.ranges do
        Logger.warn """
        network[#{a.ref}]: trying to merge divergent ranges:
          a: #{Enum.join(a.ranges, ",")}
          b: #{Enum.join(b.ranges, ",")}
        #> Chaos will occur
        """
      end

      newhosts = Enum.reduce b.hosts, a.hosts, fn({name, {remote, state}}, hosts) ->
        Map.put_new hosts, {name, {remote, state}}
      end

      newslices = Enum.reduce b.slices, a.slices, fn({ref, %Slice{} = slice}, slices) ->
        Map.put_new slices, ref, slice
      end

      %{a |
        hosts: newhosts,
        slices: newslices}
    end
  end
end
