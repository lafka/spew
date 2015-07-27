defmodule Spew.Host do
  @moduledoc """
  Provide information about the connected spew hosts
  """

  alias Spew.Cluster

  defstruct hostname: "localhost",
            node: nil,
            up?: false

  @type hostname :: String.t
  @type t :: %__MODULE__{
    hostname: hostname,
    node: node
  }


  @name __MODULE__.Server
  @cluster "host"

  @doc """
  Query the host machines
  """
  @spec query(term, Cluster.t | pid | atom) :: {:ok, [t]} | {:error, term()}
  def query(q \\ nil, server \\ @cluster), do:
    Cluster.call(server, {:query, q})

  @doc """
  Get a host
  """
  @spec get(hostname, Cluster.t | pid | atom) :: {:ok, t} | {:error, term()}
  def get(hostname, server \\ @cluster), do:
    Cluster.call(server, {:get, hostname})

  @doc """
  Add a new host

  This only adds an expectancy that a new node will appear.
  `up?` will be set to active on nodeup/nodedown messages
  """
  @spec add(hostname, Cluster.t | pid | atom) :: {:ok, t} | {:error, term()}
  def add(hostname, server \\ @cluster), do:
    Cluster.call(server, {:add, hostname})


  @doc """
  Removes a down'ed host
  """
  @spec remove(hostname, Cluster.t | pid | atom) :: {:ok, t} | {:error, term()}
  def remove(hostname, server \\ @cluster), do:
    Cluster.call(server, {:remove, hostname})

  defmodule Server do
    use GenServer

    require Logger

    alias Spew.Host
    alias Spew.Cluster

    @name __MODULE__
    @cluster "host"

    defmodule State do
      defstruct hosts: %{},
                cluster: @cluster
    end

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
      :ok = :net_kernel.monitor_nodes true

      cluster = opts[:cluster] || @cluster
      state = Cluster.init(cluster) || %State{}

      {:ok, %{state | cluster: cluster}}
    end

    def handle_call({:query, nil}, _from, state) do
      {:reply, {:ok, Map.values(state.hosts)}, state}
    end

    def handle_call({:get, hostname}, _from, state) do
      case state.hosts[hostname] do
        nil ->
          {:reply, {:error, {:notfound, {:host, hostname}}}, state}

        host ->
          {:reply, {:ok, host}, state}
      end
    end

    def handle_call({:add, hostname}, _from, state) do
      case state.hosts[hostname] do
        nil ->
          host = %Host{hostname: hostname}
          newstate = Cluster.sync state.cluster, %{state | hosts: Map.put(state.hosts, hostname, host)}
          {:reply, {:ok, host}, newstate}

        _ ->
          {:reply, {:error, {:conflict, {:host, hostname}}}, state}
      end
    end

    def handle_call({:remove, hostname}, _from, state) do
      case state.hosts[hostname] do
        nil ->
          {:reply, {:error, {:notfound, {:host, hostname}}}, state}

        %Host{up?: false} ->
          newstate = Cluster.sync state.cluster, %{state | hosts: Map.delete(state.hosts, hostname)}
          {:reply, :ok, newstate}

        %Host{up?: false} ->
          {:reply, {:error, {:hostup, {:host, hostname}}}, state}
      end
    end

    def handle_info({:nodeup, node}, state) do
      [_, hostname] = String.split "#{node}", "@"
      Logger.debug "host[#{hostname}] nodeup : #{node}"
      hosts = Enum.into state.hosts, %{}, fn
        ({k, %{hostname: name, node: hostnode} = host})
            when name == hostname and nil === hostnode ->
          Logger.debug "host[#{hostname}]: claimed #{node}"
          {hostname, %{host | hostname: hostname, node: node, up?: true}}

        ({k, %{hostname: name, node: hostnode, up?: true} = host})
            when name == hostname ->
          Logger.debug "host[#{name}] node #{node} tried to replace active node #{hostnode}"
          {k, host}

        ({k, %{hostname: name, node: hostnode, up?: false} = host})
            when name == hostname ->
          Logger.debug "host[#{name}] node #{node} replacing inactive node #{hostnode}"
          {k, %{host | node: node, up?: true}}

        (pair) ->
          pair
      end

      # double check that the node exists, possibly auto-add it
      hosts = case hosts[hostname] do
        nil ->
          Logger.info "host[#{hostname}]: auto-joined"
          Map.put hosts, hostname, %Host{hostname: hostname, node: node, up?:  true}

        _host ->
          hosts
      end

      newstate = Cluster.sync state.cluster, state

      {:noreply, %{state | hosts: hosts}}
    end

    def handle_call(:cluster_state, _from, currentstate) do
      {:reply, {:ok, currentstate}, currentstate}
    end

    synckeys = [:hosts]
    def handle_cast({:cluster_update, newstate}, oldstate) do
      r = Enum.reduce unquote(synckeys), oldstate, fn(k, acc) ->
        Map.put acc, k, Map.get(newstate, k)
      end
      {:noreply, r}
    end

    def handle_info({:nodedown, node}, state) do
      Logger.warn "host: nodedown, #{node}"
      hosts = Enum.into state.hosts, %{}, fn
        ({k, %{node: hostnode} = host})
            when node == hostnode ->
          Logger.warn "host[#{host.hostname}] marked as down"
          {k, %{host | up?: false}}

        (pair) ->
          pair
      end

      newstate = Cluster.sync state.cluster, %{state | hosts: hosts}

      {:noreply, newstate}
    end
  end
end
