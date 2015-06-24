defmodule Spew.Build do
  @moduledoc """
  Provide information about available builds
  """

  defmodule Item do
    @moduledoc """
    The concrete build item
    """
    defstruct ref: nil,
              type: __MODULE__,
              target: "void/void",
              name: nil,
              vsn: nil,
              hosts: [], # This could be a hostagent process that
                         # monitors each node
              spec: %{}

    @doc """
    Parse all builds
    """
    def builds(pattern, searchpath \\ nil) do
      builds = Spewbuild.builds(pattern, searchpath)
                |> Enum.into %{}, fn({ref, spec}) ->
                    {ref, %Item{ref: ref,
                          target: spec["TARGET"] <> "/" <> spec["VSN"],
                          name: spec["TARGET"],
                          vsn: spec["VSN"],
                          spec: spec,
                          hosts: [node]
                          }}
                    end
    end

    @doc """
    Make a tree of the form `%{target => %{vsn => [build, ..]}}`
    """
    def tree(builds), do: tree(builds, true)
    def tree(builds, reference?), do: tree(builds, reference?, %{})
    def tree(builds, reference?, acc) do
      Enum.reduce builds, acc, fn({k, build}, acc) ->
        {name, vsn} = {build.name, build.vsn}
        val = reference? && k || build
        vsnval = Enum.sort([val | acc[name][vsn] || []])
        targetval = Map.put acc[name] || %{}, vsn, vsnval

        Map.put acc, name, targetval
      end
    end
  end



  alias __MODULE__.Item

  @name __MODULE__.Server

  @doc """
  Query builds

  Currently it will only return a tree `<target> => <vsn> => ref|build`
  """
  def query(q \\ [], reference? \\ true, server \\ @name), do:
    GenServer.call(server, {:query, q, reference?})

  @doc """
  List all builds
  """
  def list(server \\ @name), do:
    GenServer.call(server, :list)

  @doc """
  Get a single build
  """
  def get(build, server \\ @name), do:
    GenServer.call(server, {:get, build})

  @doc """
  Add a build
  """
  def add(%Item{} = build, host, server \\ @name), do:
    GenServer.call(server, {:add, build, host})

  @doc """
  Reloads builds according to `pattern`

  *Note:* If pattern is used, all builds not matching pattern will be removed
  """
  def reload(pattern \\ "*/*", server \\ @name), do:
    GenServer.call(server, {:reload, pattern})


  defmodule Server do
    @moduledoc """
    Build server
    """
    use GenServer

    require Logger

    alias Spew.Build.Item

    @name __MODULE__

    defmodule State do
      defstruct builds: %{},
                tree: %{}
    end

    def start_link(), do: start_link([])
    def start_link(opts) do
      name = opts[:name] || @name
      initopts = opts[:init] || []
      notify? = initopts[:notify_reload?]

      # rewrite notify_reload? to a pid
      initopts = if notify? do
        Dict.put initopts, :notify_reload?, self
      else
        initopts
      end

      res = GenServer.start_link(__MODULE__, initopts, [name: name])

      # if you demand sync!
      if notify? do
        receive do
          :loaded -> :ok
        end
      end

      res
    end

    def init(opts) do
      parent = self
      spawn_link fn ->
        notify = opts[:notify_reload?] && [opts[:notify_reload?]] || []
        builds = Item.builds opts[:pattern] || "*/*", opts[:searchpath]

        send parent, {:reloaded, node, builds, notify}
        Logger.debug "#{__MODULE__} found #{Map.size(builds)} builds on #{node}"
      end

      {:ok, %State{builds: %{},
                   tree: %{}}}
    end

    def handle_call({:query, _, true = reference?}, _from, state) do
      {:reply, {:ok, state.tree}, state}
    end
    def handle_call({:query, _, false = reference?}, _from, state) do
      {:reply, {:ok, Item.tree(state.builds, false)}, state}
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

    def handle_call({:add, %Item{} = build, host}, _from, state) do
      {builds, tree} = add_build build, host, state.builds, state.tree

      {:reply, {:ok, builds[build.ref]}, %{state | builds: builds, tree: tree}}
    end

    def handle_call({:reload, pattern}, from, state) do
      handle_call({:reload, pattern, nil}, from, state)
    end
    def handle_call({:reload, pattern, searchpath}, _from, state) do
      spawn_link fn ->
        builds = Item.builds pattern, searchpath

        {builds, tree} = Enum.reduce builds, {state.builds, state.tree},
          fn({_ref, build}, {builds, tree}) ->
            add_build build, node, builds, tree
          end

        send self, {:reloaded, node, builds}
        Logger.debug "#{__MODULE__} found #{Map.size(builds)} builds on #{node}"
      end
      {:reply, :ok, state}
    end

    # Add all builds
    # This is expected to be called with ALL builds found on a node
    # it will iterate through the set of existing builds, checking if
    # there is any builds that was previously defined by that node
    # and either remove the it's reference in `hosts` or remove the
    # build completely if it's the only host with that node
    def handle_info({:reloaded, host, builds}, state) do
      handle_info({:reloaded, host, builds, []}, state)
    end
    def handle_info({:reloaded, host, builds, notify}, state) do
      {builds, forremoval} = mergebuilds builds, state.builds, host

      tree = Enum.reduce forremoval, state.tree, &deletepath/2
      tree = Item.tree builds, true, tree

        # need a better way to ship to all connected servers
      Enum.each :erlang.nodes, &Kernel.send({Spew.Host.Server, &1}, {:update_builds, host, builds})
      Process.send Spew.Host.Server, {:update_builds, host, builds}, []

      Enum.each notify, fn(pid) -> send pid, :loaded end

      {:noreply, %{state | builds: builds, tree: tree}}
    end

    def deletepath([item], acc), do: Map.delete(acc, item)
    def deletepath([item | rest], acc) do
      case acc[item] do
        nil ->
          acc
        item ->
          deletepath rest, item
      end
    end

    defp mergebuilds(patches, allbuilds, host) do
      # remove builds that re now unreferenced by any host
      forremoval = Enum.filter allbuilds,
        fn({ref, %{hosts: hostslist}}) ->
          # If the host is referencing a build and it's not in
          # `patches` means the host previously had the build
          Enum.member?(hostslist, host) and ! Map.has_key?(patches, ref)
        end

      allbuilds = Enum.reduce patches, allbuilds, fn({ref, build}, acc) ->
        case acc[ref] do
          nil ->
            Map.put acc, ref, build

          %{hosts: hostslist} = build ->
            Map.put acc, ref, %{build | hosts: Enum.uniq([host | hostslist])}
        end
      end

      # Generate the removal operations
      Enum.reduce forremoval,
                  {allbuilds, []},
                  fn({ref, build}, {builds, rmops}) ->

        case build.hosts do
          [^host] ->
            { Map.delete(builds, ref),
              [[build.name, build.target, build.ref] | rmops]}

          _ ->
            { Map.put(builds, ref, %{build | hosts: build.hosts -- [host]}),
              rmops}
        end
      end
    end

    defp add_build(%Item{} = build, host, builds, tree) do
      build = case builds[build.ref] do
        nil ->
          build

        build ->
          %{build | hosts: Enum.uniq([node | build.hosts])}
      end

      builds = Map.put builds, build.ref, build
      tree = Item.tree [{build.ref, build}], true, tree
      {builds, tree}
    end

  end
end

