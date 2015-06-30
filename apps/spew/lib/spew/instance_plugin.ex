defmodule Spew.InstancePlugin do
  @moduledoc """
  Helper for keeping plugins in sync with the instance itself
  """

  require Logger

  alias Spew.Instance.Item

  defmodule PluginException do
    defexception message: nil,
                 term: nil,
                 plugin: nil
  end

  @doc """
  Handle a event

  There are a few default events, but plugins may emit their own
  (like Supervision which send restart state)

  The events emitted are those emitted by Spew.Instance.State.notify

  ## Events (IO related)
    * `{:input, instanceref, buf}` - input given to the instance
    * `{:output, instanceref, buf}` - output emitted from the instance

  ## Events (Instance related)
    * `{:instance, ^ref, :add}` - instance added
    * `{:instance, ^ref, :delete}` - instance deleted
    * `{:instance, ^ref, :start}` - instance started either by run or start
    * `{:instance, ^ref, {:stopping, signal :: sig() | nil}` - instance have been told to exit cleanly
    * `{:instance, ^ref, :killing` - killing the instance
    * `{:instance, ^ref, {:stop, reason}` - The instance actually stopped
  """

  def event(nil, _ev), do: :ok
  def event(%Item{ref: ref, plugin: plugins, plugin_opts: opts} = instance, :add) do
    # prep the plugin for startup
    # initiate all the plugins
    plugins = Enum.reduce opts, plugins, fn({plugin, opts}, plugins) ->
      try do
        case function_exported? plugin, :setup, 2 do
          true ->
            Map.put plugins, plugin, plugin.setup(instance, opts)

          false ->
            Map.put plugins, plugin, nil
        end
      catch e ->
        Logger.warn "instance/plugin[#{ref}] failed to setup plugin '#{plugin}': #{e.message}"
        plugins
      end
    end

    {:update, %{instance | plugin: plugins}}
  end
  def event(%Item{ref: ref, plugin: plugins, plugin_opts: opts} = instance, :start) do
    # initiate all the plugins
    plugins = Enum.reduce opts, plugins, fn({plugin, opts}, plugins) ->
      try do
        case function_exported? plugin, :start, 2 do
          true ->
            Map.put plugins, plugin, plugin.start(instance, opts)

          false ->
            Map.put plugins, plugin, instance.plugin[plugin]
        end
      catch e ->
        Logger.warn "instance/plugin[#{ref}] failed to initialize plugin '#{plugin}': #{e.message}"
        plugins
      end
    end

    {:update, %{instance | plugin: plugins}}
  end
  def event(%Item{ref: ref, plugin: plugins} = instance, ev) do
    # initiate all the plugins
    plugins = Enum.into plugins, %{}, fn({plugin, state}) ->
      try do
        {plugin, plugin.event(instance, state, ev)}
      catch e ->
        Logger.warn "instance/plugin[#{ref}] failed notify plugin '#{plugin}': #{e.message}"
        {plugin, state}
      end
    end

    {:update, %{instance | plugin: plugins}}
  end
end
