defmodule Spew.Cluster do
  @moduledoc """
  Provides simple interface to communicate with a cluster and sync data
  between nodes within the cluster.

  This module is extremely optimistic about how it syncs data. A update in
  state will send `{:cluster, newstate}` message to all items, the only
  handling of DOWN/nodedown messages are that they will leave the PG2 group
  and will not be used in subsequent calls.

  Additionally all state updates are last-write-wins but since all calls
  should in most cases be sent to the same process the negative consequences
  should be minimal.
  """

  require Logger

  @type t :: String.t

  def __using__(opts) do
    synckeys = opts[:synckeys] || false

    if false === synckeys do
      quote do
        def handle_cast({:cluster_update, newstate}, _oldstate) do
          Logger.debug "syncing state"
          {:noreply, newstate}
        end
      end
    else
      quote do
        def handle_cast({:cluster_update, newstate}, oldstate) do
          Logger.debug "syncing keys: #{inspect unquote(synckeys)}"
          Enum.reduce unquote(synckeys), oldstate, fn(k, acc) ->
            Map.put acc, k, Map.get(newstate, k)
          end
        end
      end
    end
  end

  @doc """
  Cast all servers in the cluster
  """
  def abcast(cluster, req) do
    case :pg2.get_members cluster do
      [] ->
        {:error, {:no_members, {:cluster, cluster}}}

      servers when is_list(servers) ->
        Enum.each servers, fn(pid) ->
          if pid !== self do
            GenServer.cast pid, req
          end
        end

      {:error, {:no_such_group, ^cluster}} ->
        {:error, {:notfound, {:cluster, cluster}}}
    end
  end

  @doc """
  Call a random server in the cluster
  """
  def call(server, req), do: call(server, req, 5000)
  def call(server, req, timeout) when is_pid(server) or is_atom(server) do
    GenServer.call server, req, timeout
  end
  def call(cluster, req, timeout) do
    case :pg2.get_members cluster do
      [] ->
        {:error, {:no_members, {:cluster, cluster}}}

      [server | _] ->
        GenServer.call server, req, timeout

      {:error, {:no_such_group, ^cluster}} ->
        {:error, {:notfound, {:cluster, cluster}}}
    end
  end

  @doc """
  Cast a random server in the cluster
  """
  def cast(server, req) when is_pid(server) or is_atom(server) do
    GenServer.cast server, req
  end
  def cast(cluster, req) do
    case :pg2.get_members cluster do
      [] ->
        {:error, {:no_members, {:cluster, cluster}}}

      [server | _] ->
        GenServer.cast server, req

      {:error, {:no_such_group, ^cluster}} ->
        {:error, {:notfound, {:cluster, cluster}}}
    end
  end


  @doc """
  Join a locally registered process to a cluster
  """
  def join(cluster, who) do
    case :pg2.get_members cluster do
      members when is_list(members) ->
        if Enum.member? members, who do
          :ok
        else
          Logger.info "cluster[#{cluster}]: join #{inspect who}"
          :pg2.join cluster, who
        end

      {:error, {:no_such_group, ^cluster}} ->
        :pg2.create cluster
        Logger.info "cluster[#{cluster}]: join #{inspect who}"
        :pg2.join cluster, who
    end
  end

  @doc """
  Remote a process from the cluster
  """
  def leave(cluster, who) do
    Logger.info "cluster[#{cluster}]: leave #{inspect who}"
    :timer.sleep 500
    _ = :pg2.leave cluster, who
    :ok
  end

  @doc """
  Show members of cluster
  """
  def members(cluster) do
    case :pg2.get_members cluster do
      members when is_list(members) ->
        {:ok, members}

      {:error, {:no_such_group, ^cluster}} ->
        {:error, {:notfound, {:cluster, cluster}}}
    end
  end

  @doc """
  Simple sync mechanism that syncs the state to all nodes in the cluster
  """
  def sync(cluster, newstate) do
    :ok = abcast cluster, {:cluster_update, newstate}
    newstate
  end

  def init(cluster) do
    state = case call cluster, :cluster_state do
      {:ok, currentstate} ->
        currentstate

      {:error, {:notfound, {:cluster, _}}} ->
        nil

      {:error, {:no_members, {:cluster, _}}} ->
        nil
    end

    :ok = join cluster, self

    state
  end
end
