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
      Enum.reverse match?(app, appspec, [])
    rescue e in [ArgumentError] ->
      {:error, {:query, appspec}}
    end
    def match?(app, [], acc), do: acc
    def match?(app, [:or | rest], acc), do:
      match?(app, rest, acc)
    def match?(app, [spec, :or | rest], acc), do:
      match?(app, rest, match2(app, spec, rest, acc))
    def match?(app, [spec, :and | rest], acc) do
      case match2(app, spec, [], acc) do
        ^acc ->
          []
        newacc ->
          case match? app, rest, newacc do
            [] -> []
            ^newacc -> []
            newacc -> newacc
          end
      end
    end
    def match?(app, [spec | rest], acc), do: match2(app, spec, rest, acc)

    defp match2(app, spec, rest, acc) do
      cond do
        validate(app, spec) -> match? app, rest, [spec | acc]
        true -> match? app, rest, acc
      end
    end

    # match that app[k] matches values defined by v, `v` might 
    # be scalar in or a complex list [`v1`, :or, `v1`
    # so how do we match tags? 
    #defp validate(app, {k, v}) when is_list(v), do:
    #  validatelist(app[k], v)

    #defp validate(app, {k, "!" <> v}), do:
    #  v !== nil and app[k] !== v

    defp validate(src, [item, :and | rest]), do:
      validate(src, item) and validate(src, rest)
    defp validate(src, [item, :or | rest]),  do:
      validate(src, item) or validate(src, rest)
    defp validate(src, [item]), do:
      validate(src, item)

    defp validate(%{} = src, {k, v}) do
      srclist? = is_list src[k]
      srctarget? = is_list v

      case {srclist?, srctarget?} do
        {true, true} ->
          validate src[k], v

        {true, false} ->
          validate src[k], [v]

        {false, _} ->
          validate src[k], v
      end
    end
    defp validate(src, match) when is_list(src) and is_list(match) do
    end
    defp validate(src, "!" <> match) when is_list(src), do:
      ! Enum.member?(src, match)
    defp validate(src, match) when is_list(src), do:
      Enum.member?(src, match)

    defp validate(src, "!" <> match), do: src !== match
    defp validate(src, match), do: src == match


#    defp validate_item(app, {_k, _v}), do: false
#    defp validate_item(app, {k, "!" <> val}), do: app[k] !== val
#    defp validate_item(app, {k, val}), do: app[k] === val
#
#    defp validatelist_item(app, {k, "!" <> val}), do: !  Enum.member?(app[k], val)
#    defp validatelist_item(app, {k, val}), do: Enum.member?(app[k], val)
#
#    defp validate_item(val, ["!" <> match, :and | rest]), do:
#      val !== match and validate_item(val, rest)
#    defp validate_item(val, [match, :and | rest]), do:
#      val === match and validate_item(val, rest)
#
#    defp validate_item(val, ["!" <> match, :or| rest]), do:
#      val !== match or validate_item(val, rest)
#    defp validate_item(val, [match, :or| rest]), do:
#      val === match or validate_item(val, rest)
#
#    defp validate_item(val, "!" <> match), do: val !== match
#    defp validate_item(val, match), do: val === match

    # handle operators
    defp validatelist(source, [item, :and | rest]) do
      validatelist_item(source, item) and validatelist(source, rest)
    end
    defp validatelist(source, [item, :or | rest]) do
      validatelist_item(source, item) or validatelist(source, rest)
    end
    defp validatelist(source, [item]), do:
      validatelist_item(source, item)
    defp validatelist(source, item) when not is_list(item), do:
      validatelist_item(source, item)
    defp validatelist(_source, _items) do
        raise ArgumentError, message: "error in appspec"
    end




    # spec defined as this
    # <k> : <v>, <k> : <v>
    # where the `,` means its an OR query - literal seperatin in case of # `GET /await`.
    # the operators `OR`, `AND` may be used infix.
    # One can use () do group certain conditions.
    # The structure returned is a list :: q() where each element is
    # separated with `:and`/`:or`. If the element is another list that
    # list will also be of type `q()`

    def from_string(buf) do
      case from_string buf, {{"", nil}, []} do
        [condition| rest] when condition in [:or, :and] ->
          {:ok, Enum.reverse rest}

        conditions when is_list(conditions) ->
          {:ok, Enum.reverse conditions}

        {_rest, _acc} = res ->
          res
      end
    end

    # parse:
    #  `:` separates k/v pairs, if used in the value part (ie.  `tags:a:b`)
    #      it will be parsed as part of the value
    #  `,` in the context of a value means and OR expresion
    #  `~/r(?:[:,])?!/` in the context of a a values negates the value
    #                   and performs a non-equal match
    #  `AND` groups the previous expression and requires them both to
    #        be true. It can be used like `state:running AND tags:riak`
    #        or `tags:(riak AND production)
    #  `OR` groups with the previous expression and requires either of
    #       them to be true. Use like `AND`
    defp from_string("", {{"", _val} = buf, acc}), do: Enum.reverse(acc)
    defp from_string("", {{_key, _val} = buf, acc}), do: Enum.reverse(ins_kv(nil, buf, acc))

    defp from_string("," <> rest, {buf, acc}), do: from_string(rest, {{"", nil}, ins_kv(:or, buf, acc)})
    defp from_string(" OR " <> rest, {buf, acc}), do: from_string(rest, {{"", nil}, ins_kv(:or, buf, acc)})
    defp from_string(" AND " <> rest, {buf, acc}), do: from_string(rest, {{"", nil}, ins_kv(:and, buf, acc)})

    defp from_string("(" <> rest, {{key, nil}, acc}) do
      {rest, inner} = from_string rest
      from_string rest, {{"", nil}, ins_kv(nil, {key, Enum.reverse(inner)}, acc)}
    end
    defp from_string(":(" <> rest, {{key, nil}, acc}) do
      {rest, inner} = from_string rest
      from_string rest, {{"", nil}, ins_kv(nil, {key, Enum.reverse(inner)}, acc)}
    end
    defp from_string(")" <> rest, {{_key, _val} = buf, acc}) do
      {rest, ins_kv(nil, buf, acc)}
    end
    defp from_string(":" <> rest, {{key, nil}, acc}), do: from_string(rest, {{key, ""}, acc})

    defp from_string(" " <> rest, {{key, nil}, acc}), do:
      from_string(rest, {{key, nil}, acc})
    defp from_string(<<e :: binary-size(1), rest :: binary()>>, {{key, nil}, acc}) do
      from_string(rest, {{key <> e, nil}, acc})
    end
    defp from_string(<<e :: binary-size(1), rest :: binary()>>, {{key, val}, acc}), do:
      from_string(rest, {{key, val <> e}, acc})


    defp ins_kv(op, {nil, nil}, acc), do: raise(ArgumentError, message: "inserting empty item. parse error")
    defp ins_kv(_, {"", nil}, acc), do: acc
    defp ins_kv(_, {"", v}, acc), do: [v | acc]
    defp ins_kv(nil, {v, nil}, acc), do: [v | acc]
    defp ins_kv(op, {v, nil}, acc), do: [op, v | acc]
    defp ins_kv(nil, {k, v}, acc), do: [{String.to_existing_atom(k), v} | acc]
    defp ins_kv(op, {k, v}, acc), do: [op, {String.to_existing_atom(k), v} | acc]
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

