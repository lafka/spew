defmodule Spew.Discovery do
  use GenServer

  require Logger

  @name {:global, __MODULE__.Server}

  @states ["running", "waiting", "stopped", "crashed", "unknown"]

  def add(appref, %{state: state} = app) when false === (state in @states), do:
    {:error, {:invalid_state, state}}
  def add(appref, app), do: GenServer.call(@name, {:add, appref, app})

  def delete(appref), do: GenServer.call(@name, {:delete, appref})

  def update(appref, %{state: state} = app) when false === state in @states, do:
    {:error, {:invalid_state, state}}
  def update(appref, %{} = app), do:
    GenServer.call(@name, {:update, appref, app})

  def get(appspec), do: GenServer.call(@name, {:query, appspec})

  def subscribe(appspec), do: GenServer.call(@name, {:subscribe, appspec})

  def unsubscribe(ref), do: GenServer.call(@name, {:unsubscribe, ref})

  if :test === Mix.env do
    def flush, do: GenServer.call(@name, :flush)
  end

  defmodule Server do
    alias __MODULE__, as: Self

    @name {:global, __MODULE__}

    defstruct apps: %{},
              subscriptions: %{}

    defmodule Item do
      defstruct state: "invalid",
                appref: nil,
                tags: []
    end

    def init(_opts), do: {:ok, %Self{}}

    def start_link do
      GenServer.start_link Self, [], name: @name
    end

    def handle_call({:add, appref, app}, _from, %Self{apps: apps} = state) do
      case apps[appref] do
        nil ->
          app = Map.merge %Item{}, Map.put(app, :appref, appref)
          apps = Dict.put_new apps, appref, app

          publish state, app, {:add, appref, app}

          {:reply, :ok, %{state | :apps => apps}}

        _ ->
          {:reply, {:error, {:app_exists, appref}}, state}
      end
   end

    def handle_call({:delete, appref}, _from, %Self{apps: apps} = state) do
      case apps[appref] do
        nil ->
          {:reply, {:error, {:not_found, appref}}, state}

        %Item{} = app ->
          apps = Dict.delete apps, appref

          publish state, app, {:delete, appref, app}

          {:reply, :ok, %{state | :apps => apps}}
      end
    end

    def handle_call({:update, appref, app}, _from, %Self{apps: apps} = state) do
      case apps[appref] do
        nil ->
          {:reply, {:error, {:not_found, appref}}, state}

        %Item{} = oldapp ->
          app = Map.merge oldapp, Map.put(app, :appref, appref)
          apps = Dict.put apps, appref, app

          pushed = publish state, oldapp, {:update, appref, oldapp, app}
          publish state, app, {:update, appref, oldapp, app}, pushed

          {:reply, {:ok, app}, %{state | :apps => apps}}
      end
    end

    def handle_call({:query, appspec}, _from, %Self{apps: apps} = state) when is_binary(appspec) do
      case apps[appspec] do
        nil ->
          {:reply, {:error, {:not_found, appspec}}, state}

        app ->
          {:reply, {:ok, [app]}, state}
      end
    end
    def handle_call({:query, appspec}, _from, %Self{apps: apps} = state) do
      apps = Enum.reduce apps, [], fn({appref, app}, acc) ->
        query_validate appspec, app, acc
      end
      {:reply, {:ok, apps}, state}
    end

    defp query_validate([], app, acc), do: [app | acc]
    defp query_validate([{_k, _v} = filter | rest], app, acc) do
      if query_validate2 filter, app do
        query_validate(rest, app, acc)
      else
        acc
      end
    end
    defp query_validate2({:tags, tags}, app) do
      Enum.any? tags, &tagvalidator(&1, app.tags)
    end
    #defp query_validate2({:tags, ["!" <> tag | rest]}, app) do
    #  if Enum.member? app.tags, tag do
    #    false
    #  else
    #    query_validate2 {:tags, rest}, app
    #  end
    #end
    #defp query_validate2({:tags, [tag | rest]}, app) do
    #  if Enum.member? app.tags, tag do
    #    query_validate2 {:tags, rest}, app
    #  else
    #    false
    #  end
    #end
    defp query_validate2({k, [v]}, app), do:
      query_validate2({k, v}, app)
    defp query_validate2({k, v}, app), do:
      v === Map.get(app, k)

    defp tagvalidator("!" <> tag, match), do: ! Enum.member?(match, tag)
    defp tagvalidator([_|_] = andtags, match), do: Enum.all?(andtags, &tagvalidator(&1, match))
    defp tagvalidator(tag, match), do: Enum.member?(match, tag)

    def handle_call({:subscribe, appspec}, {from, _ref}, %Self{subscriptions: sub} = state) do
      ref = :crypto.hash(:sha256, :erlang.term_to_binary(make_ref))
        |> Base.encode16
        |> String.downcase
        |> String.slice 0, 10

      Process.monitor from

      sub = Dict.put sub, ref, %{match: appspec, target: from}
      {:reply, {:ok, ref}, %{state | subscriptions: sub}}
    end

    def handle_call({:unsubscribe, ref}, _from, %Self{subscriptions: sub} = state) do
      if sub[ref] do
        sub = Dict.delete sub, ref
        {:reply, :ok, %{state | subscriptions: sub}}
      else
        {:reply, {:error, {:not_found, ref}}, state}
      end
    end

    if :test === Mix.env do
      def handle_call(flush, _from, %Self{} = state) do
        {:reply, :ok, %Self{}}
      end
    end

    def handle_info({:DOWN, monref, :process, pid, reason},
                    %Self{subscriptions: sub} = state) do
      sub = Enum.reduce sub, sub, fn({k, v}, sub) ->
        if pid === v[:target] do
          Map.delete sub, k
        else
          sub
        end
      end
      {:noreply, %{state | subscriptions: sub}}
    end

    def terminate(_reason, _state), do: :ok

    defp publish(%Self{subscriptions: sub}, appstate, ev, ignore \\ []) do
      Enum.reduce sub, [], fn
        ({k, %{target: target, match: spec}}, acc) when is_binary(spec) ->
          skip?  = Enum.member? ignore, k

          if spec === appstate.appref and ! skip? do
            send target, ev
            [k|acc]
          else
            acc
          end
        ({k, %{target: target, match: spec}}, acc) ->
          skip?  = Enum.member? ignore, k

          if [] !== query_validate(spec, appstate, []) and ! skip? do
            send target, ev
            [k|acc]
          else
            acc
          end
      end
    end
  end
end

