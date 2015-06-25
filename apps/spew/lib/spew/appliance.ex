defmodule Spew.Appliance do
  @moduledoc """
  Provide interface to create, configure, run appliances
  """

  @name __MODULE__.Server

  @doc """
  Add a new appliance definition
  """
  def add(name, runtime, instanceopts, enabled? \\ true), do:
    GenServer.call(@name, {:add, name, runtime, instanceopts, enabled?})

  @doc """
  Retrieve an appliance either by name or its reference
  """
  def get(ref), do: GenServer.call(@name, {:get, ref})

  @doc """
  List all running appliances
  """
  def list, do: GenServer.call(@name, :list)

  @doc """
  Delete a appliance
  """
  def delete(ref), do: GenServer.call(@name, {:delete, ref})

  @doc """
  Reload configuration from disk

  If `files` are not specified or `nil` then all already files will
  be reloaded
  """
  def reload(files \\ nil), do: GenServer.call(@name, {:reload, files})

  @doc """
  Load a set of files

  If any of the files contains definitions with the same name as an
  existing appliance AND they are not equal, the loading of all files
  will fail.

  The files loaded will be registered and can be reloaded by calling
  `Appliance.reload`
  """
  def loadfiles(files), do: GenServer.call(@name, {:loadfiles, files})

  @doc """
  Unload files

  All appliances defined in the files will be deleted as well, no
  checks are done to see if the configuration defined in those files
  are actually used or if the file is loaded.
  """
  def unloadfiles(files), do: GenServer.call(@name, {:unloadfiles, files})

  if Mix.env in [:dev, :test] do
    def reset, do: GenServer.call(@name, :reset)
  end

  defmodule NoRuntime do
    defexception message: "can't find runtime",
                 query: nil
  end

  defmodule ConfigError do
    defexception param: nil,
                 file: nil,
                 message: "setting read-only parameter"
  end

  defmodule Item do
    defstruct [
      ref: nil,                             # the actual id of the appliance
      name: nil,                            # string()
      runtime: {:query, ""},                # {:query, ""} | {:ref, _} | [ref()]
      builds: [],                           # list of possible builds
      instance: %Spew.Instance.Item{        # defaults is merged with instance cfg
        runner: Spew.Runner.Systemd,
        supervision: false,
        network: [],
        rootfs: {nil, nil},
        mounts: [],
        env: []
      },
      hosts: [],                            # list of hosts which have defined this appliance
      enabled?: true
    ]
  end

  defmodule Server do
    use GenServer

    @name __MODULE__

    require Logger

    alias Spew.Utils
    alias Spew.Appliance.Item
    alias Spew.Appliance.NoRuntime
    alias Spew.Appliance.ConfigError

    defmodule State do
      defstruct appliances: %{},
                names: %{},
                files: %{}
    end

    def start_link do
      GenServer.start_link @name, %{}, name: @name
    end

    def init(_) do
      files = appliancefiles
      {:reply, :ok, state} = handle_call {:reload, files}, {self, make_ref}, %State{}
      {:ok, state}
    end

    def handle_call({:reload, nil}, from, state) do
      files = Enum.flat_map state.files, fn({_, files}) -> files end
      handle_call({:reload, files}, from, state)
    end
    def handle_call({:reload, files}, _from, state) do
      {files, appliances} = load_configs files
      appliances = Map.merge appliances, state.appliances

      names = Enum.reduce appliances, state.names, fn({ref, %{name: name}}, acc) ->
        Map.put(acc, name, ref)
      end

      Logger.debug "found #{Map.size(appliances)} appliances"
      {:reply, :ok, %State{ appliances: appliances,
                            names: names}}
    rescue
      e in Code.LoadError ->
      {:reply, {:error, {:load, e.file}}, state}

      e in [TokenMissingError, SyntaxError] ->
        {:reply, {:error, {:syntax, e.file}}, state}
      e in ConfigError ->
        {:reply, {:error, e}, state}
    end

    def handle_call({:add, name, runtime, instance, enabled?}, _from, state) do
      case Enum.drop_while state.appliances,
                           fn({_ref, appliance}) -> appliance.name !== name end do
        [] ->
          appliance = %Item{
            name: name,
            runtime: runtime,
            instance: Map.merge(%Item{}.instance, instance),
            enabled?: enabled?,
            hosts: [node]
          }

          ref = Utils.hash appliance
          appliance = %{appliance | ref: ref,
                                    builds: normalize_runtime(runtime)}

          {:reply,
            {:ok, appliance},
            %{state |
              appliances: Map.put(state.appliances, ref, appliance),
              names: Map.put(state.names, name, ref)}}

        [{ref, _} | _] ->
          {:reply, {:error, {:conflict, {:appliance, :ref, ref}}}, state}
      end

    rescue e in NoRuntime ->
      {:reply, {:error, e}, state}
    end

    def handle_call({:get, ref}, _from, state) do
      case state.appliances[ref] || state.appliances[ state.names[ref] ]do
        nil ->
          {:reply, {:error, {:notfound, {:appliance, ref}}}, state}

        appliance ->
          {:reply, {:ok, appliance}, state}
      end
    end

    def handle_call(:list, _from, state) do
      {:reply, {:ok, Dict.values(state.appliances)}, state}
    end

    def handle_call({:delete, ref}, _from, state) do
      case {state.appliances[ref], state.appliances[ state.names[ref] ]} do
        {nil, nil} ->
          {:error, {:notfound, {:appliance, ref}}}

        {app, nil} ->
          {:reply, :ok, %{state |
            appliances: Map.delete(state.appliances, ref),
            names: Map.delete(state.names, app.name)}}

        {_, appref} ->
          {:reply, :ok, %{state |
            appliances: Map.delete(state.appliances, appref),
            names: Map.delete(state.names, ref)}}
      end
    end

    def handle_call({:loadfiles, files}, _from, state) do
      {files, appliances} = load_configs files

      case appliances |> Map.to_list |> insert_appliances(state) do
        {:ok, newstate} ->
          {:reply, :ok, %{newstate |
                          files: Utils.Collection.deepmerge(files, state.files)}}

        {:error, _} = err ->
          {:reply, err, state}
      end
    rescue
      e in Code.LoadError ->
        {:reply, {:error, {:load, e.file}}, state}

      e in [TokenMissingError, SyntaxError] ->
        {:reply, {:error, {:syntax, e.file}}, state}

      e in ConfigError ->
        {:reply, {:error, e}, state}
    end

    def handle_call({:unloadfiles, files}, _from, state) do
      state = Enum.reduce files, state, fn(file, state) ->
        file = Path.expand file
        case state.files[file] do
          nil ->
            state

          refs ->
            Enum.reduce refs, state, fn(ref, %{appliances: appliances,
                                               names: names,
                                               files: files}) ->

              %{state |
                appliances: Map.delete(appliances, ref),
                names: Map.delete(names, appliances[ref].name),
                files: Map.delete(files, file)}
            end
        end
      end

      {:reply, :ok, state}
    end

    if Mix.env in [:dev, :test] do
      def handle_call(:reset, _from, _) do
        {:reply, :ok, %State{}}
      end
    end

    defp insert_appliances([], state), do: {:ok, state}
    defp insert_appliances([{ref, appliance} | rest], state) do
      case state.names[appliance.name] do
        nil ->
          newstate = %{state |
              appliances: Map.put(state.appliances, ref, appliance),
              names: Map.put(state.names, appliance.name, ref)}

          insert_appliances rest, newstate

        ^ref ->
          insert_appliances rest, state

        _ ->
          {:error, {:conflict, {:appliance, :name, appliance.name}}}
      end
    end

    def appliancefiles do
      searchpath = [
        Path.join([Spew.root, "appliances", "*"])
        | Application.get_env(:spew, :appliancepaths) || []
      ]

      Enum.flat_map searchpath, fn(path) ->
        Path.join(path, "*.exs")
          |> Path.expand
          |> Path.wildcard
      end
    end
    defp load_configs(files) do

      Enum.reduce files, {%{}, %{}}, fn(file, {files, apps}) ->
        file = Path.expand file
        {cfg, []} = Code.eval_file file

        cfg[:ref] && raise ConfigError, file: file, param: :ref
        cfg[:appliance] && raise ConfigError, file: file, param: :appliance

        ref = Utils.hash cfg
        val = Map.merge %Item{}, cfg

        val = %{val | ref: ref,
                      hosts: [node],
                      builds: normalize_runtime(val.runtime)}

        files = Map.put files, file, [ref | files[file] || []]
        apps = Map.put_new apps, ref, val

        {files, apps}
      end
    end

    defp normalize_runtime(nil), do: fn -> nil end
    defp normalize_runtime({:ref, ref}) when not is_list(ref), do: fn -> [ref] end
    defp normalize_runtime({:ref, refs}), do: fn -> refs end
    defp normalize_runtime({:query, query}), do: fn ->
      {:ok, builds} = Spew.Build.list
      q = ExQuery.Query.from_string query, Spew.Build.Item
      Enum.filter builds, fn({_ref, spec}) -> q.(spec) end
    end
  end
end
