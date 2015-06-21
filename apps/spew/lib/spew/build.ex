defmodule Spew.Build do
  @moduledoc """
  Provide information about available builds
  """

  @name __MODULE__.Server

  @doc """
  Query builds
  """
  def query(q \\ [], reference? \\ true), do: GenServer.call(@name, {:query, q, reference?})

  @doc """
  List all builds
  """
  def list, do: GenServer.call(@name, :list)

  @doc """
  Get a single build
  """
  def get(build), do: GenServer.call(@name, {:get, build})

  @doc """
  Reloads builds according to `pattern`

  *Note:* If pattern is used, all builds not matching pattern will be removed
  """
  def reload(pattern \\ "*/*"), do: GenServer.call(@name, {:reload, pattern})

  defmodule Server do
    use GenServer

    require Logger

    alias Spew.Host

    @name __MODULE__

    defmodule State do
      defstruct builds: %{},
                tree: %{}
    end

    def start_link() do
      GenServer.start_link(@name, %{}, [name: @name])
    end

    def init(_) do
      spawn_link fn ->
        builds = Spewbuild.builds "*/*"

        send @name, {:reloaded, builds}
        Logger.debug "#{__MODULE__} found #{Map.size(builds)} builds"
      end

      {:ok, %State{builds: %{}, tree: %{}}}
    end

    def handle_call({:query, _, true = reference?}, _from, state) do
      {:reply, {:ok, state.tree}, state}
    end
    def handle_call({:query, _, false = reference?}, _from, state) do
      {:reply, {:ok, Spewbuild.tree(state.builds, false)}, state}
    end

    def handle_call(:list, _from, state) do
      {:reply, {:ok, state.builds}, state}
    end

    def handle_call({:get, ref}, _from, state) do
      case state.builds[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:build, ref}}}, state}
        build ->
          {:reply, {:ok, build}, state}
      end
    end

    def handle_call({:reload, pattern}, _from, state) do
      spawn_link fn ->
        builds = Spewbuild.builds pattern

        send @name, {:reloaded, builds}
        Logger.debug "#{__MODULE__} found #{Map.size(builds)} builds"
      end
      {:reply, :ok, state}
    end

    def handle_info({:reloaded, builds}, state) do
      tree = Spewbuild.tree builds

        # need a better way to ship to all connected servers
      Enum.each :erlang.nodes, &Kernel.send({Spew.Host.Server, &1}, {:update_builds, node, builds})
      Process.send Spew.Host.Server, {:update_builds, node, builds}, []

      {:noreply, %State{builds: builds, tree: tree}}
    end
  end
end

