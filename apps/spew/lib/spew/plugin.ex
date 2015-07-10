defmodule Spew.Plugin do
  @moduledoc """
  Enables the different parts of Spew to have a pluggable interface.

  Plugins have 3 important calls:
    * `init/2` - takes a set of options and return the state
    * `notify/3` - takes a initial term and the event
    * `cleanup/2` - Takes the plugin state and does any cleaning up require

  Additionally the `spec/1` is required to specify the order of how
  to call plugins

  ## Example

  ```
  defmodule Pluggable do
    alias Spew.Plugin

    @plugins [PreloadTheInternet, WriteTheInternetBack]

    def start() do
      spawn fn ->
        plugins = Spew.Plugin.init @plugins
        waitforaction %{plugins: plugins}
      end
    end

    def waitforaction(state) do
      recv do
        {:criticalaction, action} ->
          # Demand that the plugins behave nicely!
          case Spew.Plugin.call state[:plugins], action do
            :ok ->
              waitforaction(state)

            {:error, _} = res ->
              res
          end

        {:action, action} ->
          # Notify without caring about the respon
          Spew.Plugin.notify state[:plugins], action
          waitforaction(state)
      end
    end
  end
  ```
  """

  @type plugin :: module
  @type state :: %{}
  @typep caller :: any
  @typep event :: any
  @typep pluginstate :: any

  use Behaviour

  defcallback init(caller, term, [term]) :: {:ok, state} | {:error, {plugin, term}}
  defcallback notify(caller, pluginstate, event) :: :ok | {:update, pluginstate} | {:error, term}
  defcallback cleanup(caller, pluginstate, [term]) :: :ok
  defcallback spec(caller) :: [{:before, [plugin]} | {:after, [plugin]} | {:require, [plugin]}]

  defmacro __using__(_) do
    quote do
      @behaviour Spew.Plugin
    end
  end

  @doc """
  Initialize plugin state for `caller`

  Plugins are ordered according to the return of the `spec/1` callback
  """
  @spec init(caller, [plugin | {plugin, term}], [term]) :: {:ok, state} | {:error, term}
  def init(caller, plugins, opts \\ []) do
    case pluginorder caller, plugins do
      {:ok, plugins} ->
        init2 caller, opts, plugins, %{}

      {:error, _} = res ->
        res
    end
  end

  defp init2(_caller, _opts, [], plugins), do: {:ok, plugins}

  defp init2(caller, opts, [{plugin, plugopts} | rest], plugins) do
    case plugin.init caller, plugopts, opts do
      {:ok, pluginstate} ->
        init2 caller, opts, rest, Map.put(plugins, plugin, pluginstate)

      {:error, err} ->
        {:error, {plugin, err}}

      res ->
        {:error, {:invalid_return, res, {:plugin, plugin}}}
    end
  end

  defp init2(caller, opts, [plugin | rest], plugins) when is_atom(plugin) do
    init2 caller, opts, [{plugin, nil} | rest], plugins
  end



  @doc """
  Notify all plugins of a new event

  For notify there are no specific order that plugins are called
  """
  @spec notify(caller, state, event) :: {:ok, state} | {:error, term}
  def notify(caller, plugins, ev) do
    notify2 caller, Enum.to_list(plugins), plugins, ev
  end

  defp notify2(_caller, [], plugins, _ev), do: {:ok, plugins}
  defp notify2(caller, [{plugin, state} | rest], plugins, ev) do
    case plugin.notify caller, state, ev do
      :ok ->
        notify2 caller, rest, plugins, ev

      {:update, newstate} ->
        notify2 caller, rest, Map.put(plugins, plugin, newstate), ev

      {:error, err} ->
        {:error, {plugin, err}, Dict.keys(rest), caller}
    end
  end



  @doc """
  Tell the plugins to cleanup after themselves

  Plugin cleanup is called in reverse order of their initialization
  """
  @spec cleanup(caller, state, [term]) :: :ok
  def cleanup(caller, plugins, opts \\ []) do
    case pluginorder caller, plugins do
      {:ok, plugins} ->
        plugins = Enum.reverse plugins
        cleanup2 caller, opts, plugins

      {:error, _} = res ->
        res
    end
  end

  defp cleanup2(_caller, _opts, []), do: :ok

  defp cleanup2(caller, opts, [{plugin, state} | rest]) do
    plugin.cleanup caller, state, opts
    cleanup2 caller, opts, rest
  end



  defp pluginorder(caller, plugins) do
    reqs = pluginspecs caller, Enum.to_list(plugins), [], []
    # Simple ordering, this will fuck up completely on complex stuff
    # but the plugins should check that the dependencies are ok


    reqmap = Enum.reduce reqs, %{}, fn
      ({p, :after, nil}, acc) ->
        Map.put acc, p, acc[p] || []

      ({p, :after, p2}, acc) ->
        acc
          |> Map.put(p, Enum.uniq [p2 | acc[p] || []])
          |> Map.put(p2, acc[p2] || [])

      ({p2, :before, p}, acc) ->
        acc
          |> Map.put(p, Enum.uniq [p2 | acc[p] || []])
          |> Map.put(p2, acc[p2] || [])
    end

    case resolvereqmap reqmap do
      {:ok, order} ->
        {:ok, Enum.map(order, fn(p) -> {p, plugins[p]} end)}

      {:error, _} = res ->
        res
    end
  end

  defp resolvereqmap(map), do: resolvereqmap(map, [])
  defp resolvereqmap(map, acc) when map == %{}, do: {:ok, Enum.reverse(acc)}
  defp resolvereqmap(map, acc) do
    {newmap, acc} = Enum.reduce map, {map, acc}, fn
      ({plugin, []}, {map, acc}) ->
        {Map.delete(map, plugin), [plugin | acc]}

      ({plugin, deps}, {map, acc}) ->
        case deps -- acc do
          [] ->
            {Map.delete(map, plugin), [plugin | acc]}
          deps ->
            {Map.put(map, plugin, deps), acc}
        end
    end

    case newmap do
      ^map ->
        {:error, {:deps, map}}

      newmap ->
        resolvereqmap newmap, acc
    end
  end

  defp pluginspecs(_caller, [], _loaded, reqs), do: reqs
  defp pluginspecs(caller, [{plugin, _}| rest], loaded, reqs) do
    pluginspecs caller, [plugin | rest], loaded, reqs
  end
  defp pluginspecs(caller, [plugin | rest], loaded, reqs) when is_atom(plugin) do
    require Logger
    spec = plugin.spec caller

    # Check that the requirement is not loaded, and if so push make it load next
    rest = Enum.reduce spec[:require] || [], rest, fn(dep, rest) ->
      if Enum.member? loaded, dep do
        rest
      else
        [dep | rest]
      end
    end

    appendreqs = Enum.map(spec[:after] || [], fn(dep) -> {plugin, :after, dep} end) ++
                 Enum.map(spec[:before] || [], fn(dep) -> {plugin, :before, dep} end)
    case appendreqs do
      [] ->
        pluginspecs caller, rest, [plugin | loaded], [{plugin, :after, nil} | reqs]

      appendreqs ->
        pluginspecs caller, rest, [plugin | loaded], appendreqs ++ reqs
    end
  end
end
