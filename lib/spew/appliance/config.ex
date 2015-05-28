defmodule Spew.Appliance.Config do
  @moduledoc """
  Appliance Configuration management

  The module exposes a interface to read configuration options.
  The state is contained within `Spew.Appliance.Config.Server` which
  allows reading the configuration or adding new temporary appliances
  not defined in the `appliances.config`
  """


  alias Spew.Appliance.Config.Item

  defmodule Item do
    @derive [Access]
    defstruct name: "",
              handler: nil,
              type: :invalid,
              appliance: nil,
              runneropts: nil,
              depends: [],
              hooks: %{},
              restart: false
  end


  @name __MODULE__.Server

  @doc """
  Loads a configuration file, if none are specified all the
  currently loaded configuration files are loaded
  """
  def load, do: GenServer.call(@name, :load_cfg)
  def load(file, opts), do: GenServer.call(@name, {:load_cfg, file, opts})

  @doc """
  Unloads a configuration file.

  Removes all the unused items defined by that configuration file.

  File can be a config file name or `:all` to do a complete reset

  It takes the following options:
    - :kill - just kill the process without waiting for a clean shutdown
    - :stop_all - stop all the running appliances related to this config
  """
  def unload(file, opts \\ []), do: GenServer.call(@name, {:unload_cfg, file, opts})

  @doc """
  List all the available configuration files
  """
  def files, do: GenServer.call(@name, :files)

  @doc """
  Store a new appliance config

  if not ref is given one is generated for you by hashing vals.
  if a ref is given than that ref will be replaced by the new vals -
  this will generate a new ref
  """
  def store(vals), do: GenServer.call(@name, {:store, vals})
  def store(cfgref, %Item{} = vals), do: GenServer.call(@name, {:store, cfgref, vals})

  @doc """
  Fetches a appliance config, or if no arguments given fetch whole config
  """
  def fetch, do: GenServer.call(@name, :fetch)
  def fetch(cfgref_or_name), do: GenServer.call(@name, {:fetch, cfgref_or_name})

  @doc """
  Delete a appliance config by it's ref
  """
  def delete(cfgref), do: GenServer.call(@name, {:delete, cfgref})


  defmodule Server do
    use GenServer

    require Logger

    @name __MODULE__

    defstruct files: [],
              appliances: %{}

    alias __MODULE__, as: Self
    alias Spew.Appliance.Config.Item

    def start_link do
      GenServer.start_link __MODULE__, [], name: @name
    end

    def init([]) do
      load_files [], %Self{
        files: Application.get_env(:spew, :appliance)[:config]
      }
    end

    def handle_call(:load_cfg, _from, state) do
      {:ok, state} = load_files [], state
      {:reply, :ok, state}
    end

    def handle_call({:load_cfg, file, opts}, _from, state) do
      {:ok, state} = load_files [file], opts, state
      {:reply, :ok, state}
    end

    def handle_call({:unload_cfg, :all, opts},
                    _from,
                    %Self{} = state) do

      {:reply, :ok, %Self{}}
    end

    def handle_call({:unload_cfg, file, opts},
                    _from,
                    %Self{files: files, appliances: apps} = state) do
      files = files -- [file]
      apps = Enum.reduce apps, apps, fn
        ({k, %{file: fileref}}, acc) when file === fileref ->
          Dict.delete acc, k

        (_, acc) ->
          acc
      end

      {:reply, :ok, %{state | :appliances => apps, :files => files}}
    end

    def handle_call(:files, _from, %Self{files: files} = state), do:
      {:reply, {:ok, files}, state}

    def handle_call({:store, %Item{} = vals}, _from, %Self{appliances: apps} = state) do
      vals = Map.put vals, :ref, cfgref = gen_ref(vals)

      apps = insert_apps [{cfgref, vals}], apps

      {:reply, {:ok, cfgref}, %{state | :appliances => apps}}
    rescue e in ArgumentError ->
      {:reply, {:error, :argument_error}, state}
    end
    def handle_call({:store, oldcfgref, %Item{} = vals}, _from, %Self{appliances: apps} = state) do
      vals = Map.put vals, :cfgref, newcfgref = gen_ref(vals)

      apps = Map.delete apps, oldcfgref
      apps = insert_apps [{newcfgref, vals}], apps
      {:reply, {:ok, newcfgref}, %{state | :appliances => apps}}
    end

    def handle_call(:fetch, _from, %Self{appliances: apps} = state) do
      {:reply, {:ok, apps}, state}
    end

    def handle_call({:fetch, nil}, _from, %Self{appliances: apps} = state) do
      {:reply, {:ok, {nil, %Item{}}}, state}
    end
    def handle_call({:fetch, cfgref_or_name}, _from, %Self{appliances: apps} = state) do
      case apps[cfgref_or_name] do
        nil ->
          # search for name
          case Enum.filter apps, fn({cfgref, vals}) -> vals.name === cfgref_or_name end do
            [{cfgref, vals}] ->
              {:reply, {:ok, {cfgref, vals}}, state}

            [_vals | _ ] = vals ->
              {:reply, {:error, {:ambiguous, Dict.keys(vals)}}, state}

            [] ->
              {:reply, {:error, {:not_found, cfgref_or_name}}, state}
          end

        vals ->
          {:reply, {:ok, {cfgref_or_name, vals}}, state}
      end
    end

    def handle_call({:delete, cfgref}, _from, %Self{appliances: apps} = state) do
      # @todo - should this only allow deletion of transient configs?
      state = %{state | :appliances => Dict.delete(apps, cfgref)}
      {:reply, :ok, state}
    end


    defp insert_apps(new, old) do
      Enum.reduce new, old, fn({k, v}, acc) ->
        # remove old items with the same name
        acc = case Enum.find acc, fn({_, x}) -> x.name === v.name end do
          {oldcfgref, _vals} ->
            Dict.delete acc, oldcfgref

          nil ->
            acc
        end
        Map.put acc, k, v
      end
    end

    # Loads config files
    # The config is layed out as `cfgref -> cfg` where cfgref is the hash of
    # the `cfg`. When files are reloaded all existing cfgrefs for that
    # file is removed unless they have a running appliance using that
    # config
    # @todo ensure that running appliances does not get removed
    defp load_files(opts, %Self{files: files} = state), do: load_files(files, opts, state)
    defp load_files(files, opts, %Self{files: oldfiles, appliances: apps} = state) do
      # remove old config
      # @todo ensure that nothing is running with this config
      apps = Enum.reduce apps, apps, fn({cfgref, vals}, acc) ->
        if Enum.member? files, Map.get(vals, :file) do
          Dict.delete acc, cfgref
        else
          acc
        end
      end

      {parser, txt} = case opts[:parser] do
        nil -> {&proc_file/1, "exs"}
        mod -> {&mod.parse/1, "#{mod}"}
      end

      apps = Enum.reduce files, apps, fn(file, acc) ->
        {file, parser, txt} = case file do
          {file, mod} ->
            {file, &mod.parse/1, "#{mod}"}

          file ->
            {file, parser, txt}
        end

        case parser.(file) do
          {:ok, newacc} ->
            acc = insert_apps newacc, acc

          {:error, e} ->
            Logger.warn "failed to process config: #{file}, #{inspect e}"
            acc
        end
      end

      files = Enum.map files, fn
        ({f, p}) -> "#{p}##{f}"
        (f) -> "#{txt}##{f}"
      end

      files = Enum.sort (files ++ oldfiles) |> Enum.uniq
      {:ok, %Self{state | :appliances => apps, :files => files}}
    end

    defp proc_file(file) do
      vals = Mix.Config.read!(file)
      vals = Enum.into(vals, %{}, fn({app, opts}) ->
        {app, appopts} = case String.split app, "#" do
          [app] ->
            {app, []}

          [app, appopts] ->
            # @todo parse applianceOpts
            {app, appopts}
        end

        opts = Dict.merge(opts, :proplists.get_value("_", vals, []) |> Enum.into(%{}))
        opts = Enum.reduce opts, %Item{}, fn({k, v}, acc) ->
          Map.put acc, k, v
        end

        # merge defaults
        opts = Map.put opts, :appliance, [app, appopts]

        opts = Map.put opts, :file, file

        cfgref = gen_ref opts
        opts = Map.put opts, :cfgref, cfgref

        {cfgref, opts}
      end) |> Dict.delete :_

      {:ok, vals}
    rescue e in [Mix.Config.LoadError] ->
      {:error, e.error}
    end

    defp gen_ref(%Item{} = vals) do
      :crypto.hash(:sha256, :erlang.term_to_binary(vals)) |> Base.encode64
    end
  end
end

