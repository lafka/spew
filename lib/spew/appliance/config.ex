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
              services: [],      # The names of services this appliance exports
              handler: nil,      # The handler responsible for running this appliance
              type: :invalid,    # the type of appliance, directly related to `:handler`
              appliance: nil,    # The information about appliance build, if such is available
              runneropts: nil,   # options specific to `:handler`
              depends: [],       # dependencies needed for this to run
              hooks: %{},        # hooks for appliance events
              restart: false,    # restart strategy
              cfgrefs: {nil, []} # list of configs used to create this
  end


  @name {:global, __MODULE__.Server}

  @doc """
  Loads a configuration file, if none are specified all the
  currently loaded configuration files are loaded
  """
  def load, do: GenServer.call(@name, :load_cfg)
  def load(file, opts \\ []), do: GenServer.call(@name, {:load_cfg, file, opts})

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
end

