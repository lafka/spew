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


  defmodule Spec do
    @moduledoc """
    Functions to work with discovery appspecs
    """

    # Either a list of lists separated by OR for matching multi entities
    # or a list of {k, v} pairs to denote matching against a single set
    # of entities.
    # if no specs are given behaviour is undefined and will change in
    # future.
    # or shortcuts the entire thing and returns first possible match

    # {:ok, matched_specs} || false
    @doc """
    Returns the specs that match `app`
    """
    def match?(app, appspec) do
      match?(app, appspec, [])
    rescue e in [ArgumentError] ->
      {:error, {:query, appspec}}
    end
    def match?(app, [], acc), do: acc
    def match?(app, [:and | rest], acc), do:
      {:error, {:query, "`and` not supported at top level, group condition"}}
    def match?(app, [:or | rest], acc), do:
      match?(app, rest, acc)
    def match?(app, [spec | rest], acc) do
      cond do
        validate(app, spec) -> match? app, rest, [spec | acc]
        true -> match? app, rest, acc
      end
    end

    # match that app[k] matches values defined by v, `v` might 
    # be scalar in or a complex list [`v1`, :or, `v1`
    defp validate(app, {k, v}) when is_list(v), do:
      validatelist(app[k], v)
    defp validate(app, {k, "!" <> v}), do:
      v !== nil and app[k] !== v
    defp validate(app, {k, v}), do:
      v !== nil and app[k] === v
    defp validate(app, [item, :and | rest]), do:
      validate(app, item) and validate(app, rest)
    defp validate(app, [item, :or | rest]), do:
      validate(app, item) or validate(app, rest)
    defp validate(app, [item]), do:
      validate(app, item)
    defp validate(_app, _items) do
      raise ArgumentError, message: "error in appspec"
    end

    defp validatelist(source, [item, :and | rest]), do:
      validatelist_item(source, item) and validatelist(source, rest)
    defp validatelist(source, [item, :or | rest]), do:
      validatelist_item(source, item) or validatelist(source, rest)
    defp validatelist(source, [item]), do:
      validatelist_item(source, item)
    defp validatelist(_source, _items) do
        raise ArgumentError, message: "error in appspec"
    end

    defp validatelist_item(source, items) when is_list(items), do:
      validatelist(source, items)
    defp validatelist_item(source, "!" <> item), do:
      ! Enum.member?(source, item)
    defp validatelist_item(source, item), do:
      Enum.member?(source, item)



    # spec defined as this
    # <k> : <v>, <k> : <v>
    # where the `,` means its an OR query - literal seperatin in case of # `GET /await`.
    # the operators `OR`, `AND` may be used infix.
    # One can use () do group certain conditions.
    # The structure returned is a list :: q() where each element is
    # separated with `:and`/`:or`. If the element is another list that
    # list will also be of type `q()`

    def from_string(buf) do
      case from_string buf, {"", []} do
        [condition| rest] when condition in [:or, :and] ->
          rest |> expand

        conditions when is_list(conditions) ->
          conditions |> expand

        {_rest, _acc} = res ->
          res
      end
    end

    defp from_string("", {"", group}), do: group
    defp from_string("", {acc, group}), do: [acc | group]

    defp from_string("," <> rest, {"", group}),    do: from_string(rest, {"", group})
    defp from_string("," <> rest, {k, group}),     do: from_string(rest, {"", [:or, k | group]})
    defp from_string(" OR " <> rest, {k, group}),  do: from_string(rest, {"", [:or, k | group]})
    defp from_string(" AND " <> rest, {k, group}), do: from_string(rest, {"", [:and, k | group]})

    defp from_string("(" <> rest, {"", group}) do
      {rest, innergroup} = from_string rest
      from_string rest, {"", [:or, innergroup | group]}
    end
    defp from_string("(" <> rest, {_acc, group}) do
      {rest, innergroup} = from_string rest
      from_string rest, {"", [:or, innergroup | group]}
    end
    defp from_string(")" <> rest, {acc, group}), do: {rest, [acc|group]}

    defp from_string(<<k :: binary-size(1), rest :: binary()>>, {acc, group}), do:
      from_string(rest, {acc <> k, group})


    defp expand(appspec), do: Enum.map(appspec, &expand2/1)
    #defp expand([spec, :and | rest], {group, acc}), do:
    #    expand(rest, {[spec, :and | group || []], acc})
    #defp expand([item | rest], {nil, acc}), do:
    #    expand(rest, [item | acc])
    #defp expand([item | rest], {group, acc}), do:
    #  expand(rest, {nil, [[item | group] | acc]})

    defp expand2(operator) when is_atom(operator), do: operator
    defp expand2(group) when is_list(group), do: expand(group)
    defp expand2({_k, _v} = pair), do: pair
    defp expand2(buf) do
      case String.split buf, ":", parts: 2 do
        [k, v] ->
          {String.to_existing_atom(k), v}

          [buf] ->
            buf
      end
    end
  end

  if :test === Mix.env do
    def flush, do: GenServer.call(@name, :flush)
  end

  defmodule Server do
    alias __MODULE__, as: Self

    alias Spew.Discovery.Spec

    @name {:global, __MODULE__}

    defstruct apps: %{},
              subscriptions: %{}

    defmodule Item do
      @derive [Access]
      defstruct state: "invalid",
                exit_status: nil,
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
      apps = Enum.reduce apps, [], fn
        (_, {:error, _} = acc) ->
          acc

        ({appref, app}, acc) ->
          case Spec.match? app, appspec do
            {:error, {:query, _}} = err ->
              err

            [] ->
              acc

            _specs ->
              [app | acc]
          end
      end

      case apps do
        {:error, _} = err ->
          {:reply, err, state}

        apps ->
          {:reply, {:ok, apps}, state}
      end
    end

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

          matches? = spec === appstate.appref and ! skip?
          publish2 matches?, target, ev, k, acc

        ({k, %{target: target, match: true = matches?}}, acc) ->
          skip?  = Enum.member? ignore, k
          matches? = matches? and ! skip?
          publish2 matches?, target, ev, k, acc

        ({k, %{target: target, match: spec}}, acc) ->
          skip?  = Enum.member? ignore, k

          matches? = [] !== Spec.match?(appstate, spec) and ! skip?
          publish2 matches?, target, ev, k, acc
      end
    end
    defp publish2(true, target, ev, k, acc) do
        send target, ev
        [k | acc]
    end
    defp publish2(false, _target, _ev, _k, acc), do: acc
  end
end

