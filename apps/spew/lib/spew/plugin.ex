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

  defcallback init(caller, term) :: {:ok, state} | {:error, {plugin, term}}
  defcallback notify(caller, pluginstate, event) :: :ok | {:update, pluginstate} | {:error, term}
  defcallback cleanup(caller, pluginstate) :: :ok
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
  @spec init(caller, [plugin | {plugin, term}]) :: {:ok, state} | {:error, term}
  def init(caller, plugins) do
    case pluginorder caller, plugins do
      {:ok, plugins} ->
        init2 caller, plugins, %{}

      {:error, _} = res ->
        res
    end
  end

  defp init2(_caller, [], plugins), do: {:ok, plugins}

  defp init2(caller, [{plugin, opts} | rest], plugins) do
    case plugin.init caller, opts do
      {:ok, pluginstate} ->
        init2 caller, rest, Map.put(plugins, plugin, pluginstate)

      {:error, err} ->
        {:error, {plugin, err}}

      res ->
        {:error, {:invalid_return, res, {:plugin, plugin}}}
    end
  end

  defp init2(caller, [plugin | rest], plugins) when is_atom(plugin) do
    init2 caller, [{plugin, nil} | rest], plugins
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
  @spec cleanup(caller, state) :: :ok
  def cleanup(caller, plugins) do
    case pluginorder caller, plugins do
      {:ok, plugins} ->
        plugins = Enum.reverse plugins
        cleanup2 caller, plugins

      {:error, _} = res ->
        res
    end
  end

  defp cleanup2(_caller, []), do: :ok

  defp cleanup2(caller, [{plugin, state} | rest]) do
    plugin.cleanup caller, state
    cleanup2 caller, rest
  end



  defp pluginorder(caller, plugins) do
    specs = pluginspecs caller, Enum.to_list(plugins), [], %{}
    # Simple ordering, this will fuck up completely on complex stuff
    # but the plugins should check that the dependencies are ok
    order = Enum.reduce specs, [], fn({plugin, spec}, acc) ->
      case (spec[:after] || []) ++ [plugin | spec[:before] || []] do
        [item] ->
          if Enum.member? acc, item do
            acc
          else
            [item]
          end

        items ->
          case Enum.drop_while items, fn(item) -> ! Enum.member?(acc, item) end do
            [item | _] ->
              index = Enum.find_index acc, &(item == &1)
              List.flatten(List.replace_at acc, index, items)
            [] ->
              acc ++ items
          end
      end
    end

    if Enum.uniq(order) !== order do
      {:error, {:plugindeps, order}}
    else
      {:ok, Enum.map(order, fn(p) -> {p, plugins[p]} end)}
    end
  end

  defp loadorder({plugin, spec}, specs) do
  end

  defp pluginspecs(_caller, [], _loaded, acc), do: acc
  defp pluginspecs(caller, [{plugin, _}| rest], loaded, acc) do
    pluginspecs caller, [plugin | rest], loaded, acc
  end
  defp pluginspecs(caller, [plugin | rest], loaded, specs) when is_atom(plugin) do
    spec = plugin.spec caller

    # Check that the requirement is not loaded, and if so push make it load next
    rest = Enum.reduce spec[:require] || [], rest, fn(dep, rest) ->
      if Enum.member? loaded, dep do
        rest
      else
        [dep | rest]
      end
    end

    spec = Dict.delete spec, :require

    pluginspecs caller, rest, [plugin | loaded], Map.put_new(specs, plugin, spec)
  end
end
