defmodule Spew.Appliance.Config.Server do
  @moduledoc """
  The server containing configuration state
  """

  use GenServer

  require Logger

  @name {:global, __MODULE__}

  defstruct files: [],
            appliances: %{}

  alias __MODULE__, as: Self
  alias Spew.Appliance.Config.Item

  def start_link do
    GenServer.start_link __MODULE__, [], name: @name
  end

  def init([]) do
    {:ok, state, apps} = load_files [], %Self{
      files: Application.get_env(:spew, :appliance)[:config]
    }

    # love race conditions, should ensure that both Config and Manager
    # is up and running before
    spawn fn ->
      :ok = initapps apps
    end

    {:ok, state}
  end

  defp initapps(apps) do
    Enum.each apps, fn({name, app}) ->
      {_name, refs} = app[:cfgrefs]
      IO.inspect Spew.Appliance.run Enum.at(refs, 0), app
    end
  end

  def handle_call(:load_cfg, _from, state) do
    {:ok, state, apps} = load_files [], state
    :ok = initapps apps
    {:reply, :ok, state}
  end

  def handle_call({:load_cfg, file, opts}, _from, state) do
    {:ok, state, apps} = load_files [file], opts, state
    :ok = initapps apps
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

    apps = insert_cfgs [{cfgref, vals}], apps

    {:reply, {:ok, cfgref}, %{state | :appliances => apps}}
  rescue e in ArgumentError ->
    {:reply, {:error, :argument_error}, state}
  end
  def handle_call({:store, oldcfgref, %Item{} = vals}, _from, %Self{appliances: apps} = state) do
    vals = Map.put vals, :cfgref, newcfgref = gen_ref(vals)

    apps = Map.delete apps, oldcfgref
    apps = insert_cfgs [{newcfgref, vals}], apps
    {:reply, {:ok, newcfgref}, %{state | :appliances => apps}}
  end

  def handle_call(:fetch, _from, %Self{appliances: apps} = state) do
    {:reply, {:ok, apps}, state}
  end

  # this is used for transient appliances with out any particular config
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


  defp insert_cfgs(new, old) do
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
  defp load_files(files, opts, %Self{files: oldfiles, appliances: cfgs} = state) do
    # remove old config
    # @todo ensure that nothing is running with this config
    cfgs = Enum.reduce cfgs, cfgs, fn({cfgref, vals}, acc) ->
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

    {cfgs, apps} = Enum.reduce files, {cfgs, %{}}, fn(file, {cfgs, apps} = acc) ->
      {file, parser, txt} = case file do
        {file, mod} ->
          {file, &mod.parse/1, "#{mod}"}

        file ->
          {file, parser, txt}
      end

      case parser.(file) do
        {:ok, newcfgs, newapps} ->
          {newcfgs |> insert_cfgs(cfgs), Map.merge(apps, newapps)}

        {:ok, newcfgs} ->
          {newcfgs |> insert_cfgs(cfgs), apps}

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
    {:ok, %Self{state | :appliances => cfgs, :files => files}, apps}
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

