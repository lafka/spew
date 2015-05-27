defmodule Spew.Appliance do

  require Logger

  alias Spew.Appliance.Config
  alias Spew.Appliance.Manager

  @doc """
  Creates a appliance
  """
  def create(name, appopts), do:
    create(name, appopts, [])
  def create(name, appopts = %Config.Item{}, _opts) do
    case Config.fetch name do
      {:ok, {cfgref, _}} ->
        {:error, {:appliance_exists, cfgref}}

      {:error, {:not_found, _}} ->
        Config.store Map.put(appopts, :name, name)
    end
  end
  def create(_appref_or_name, _, _opts), do:
    {:error, {:argument_error, "appopts must be of type Spew.Appliance.Config.Item"}}


  @doc """
  Runs a appliance
  """
  def run(appref_or_name), do:
    run(appref_or_name, %{})
  def run(appref_or_name, appopts), do:
    run(appref_or_name, appopts, [])
  def run(appref_or_name, appopts = %{}, opts) do
    case get_cfg_by_name_or_ref! appref_or_name do
      {:error, {:not_found, _}} = e ->
        e

      {:ok, {cfgref, cfgappopts}} ->
        #appopts = Map.merge cfgappopts, appopts
        appopts = deepmerge appopts, cfgappopts
        appopts = Dict.put appopts, :cfgref, cfgref
        module = atom_to_module appopts.type


        appopts = %{appopts | :handler => module}
        {ref, parent} = {make_ref, self}

        {pid, monref} = spawn_monitor fn ->
          case module.run appopts, opts do
            {:ok, state} ->
              {:ok, appref} = res = Manager.run([appopts, opts], state)
              send parent, {ref, res}
              {:ok, {_, appstate}} = Manager.get appref

              subscribers = Enum.reduce opts[:subscribe], %{}, fn
                ({action, who}, acc) ->
                  Dict.put acc, action, [who]

                (action, acc) ->
                  Dict.put acc, action, [parent]
              end

              apploop appstate, subscribers

            {:ok, state, monitor} ->
              {:ok, appref} = res = Manager.run([appopts, opts], state, monitor)
              send parent, {ref, res}
              {:ok, {_, appstate}} = Manager.get appref
              Process.monitor monitor

              subscribers = Enum.reduce opts[:subscribe], %{}, fn
                ({action, who}, acc) ->
                  Dict.put acc, action, [who]

                (action, acc) ->
                  Dict.put acc, action, [parent]
              end

              apploop appstate, subscribers

            {:error, _err} = error ->
              send parent, {ref, error}
          end
        end

        exitstate = receive do
          {^ref, res} ->
            true = Process.demonitor monref
            res

          {:DOWN, _ref, :process, ^pid, res} ->
            {:error, res}
        after
          5000 ->
            Process.exit pid, :kill
            {:error, :timeout}
        end
    end
  end


  @doc """
  Message the app
  """
  def subscribe(appref, action, who \\ nil) do
    Logger.debug "subscribe #{appref} -> #{action}"
    case Manager.get appref do
      {:ok, {appref, appcfg}} ->
        send appcfg[:apploop], {:subscribe, appref, {action, who || self}}
        :ok

      {:error, _} = res ->
        res
    end
  end

  @doc """
  Unsubscribe from appliance event
  """
  def unsubscribe(appref, action, who \\ nil) do
    {:ok, {appref, appcfg}} = Manager.get appref
    send appcfg[:apploop], {:unsubscribe, appref, {action, who || self}}
    :ok
  end

  @doc """
  Notify appliance of something
  """
  def notify(appref, action) do
    {:ok, {appref, appcfg}} = Manager.get appref
    send appcfg[:apploop], {action, appref}
    :ok
  end

  def notify(appref, action, ev) do
    {:ok, {appref, appcfg}} = Manager.get appref
    send appcfg[:apploop], {action, appref, ev}

    :ok
  end

  defp apploop(appstate), do: apploop(appstate, %{})
  defp apploop(appstate, subscribers) do
    appref = appstate[:appref]
    apppid = appstate[:runstate][:pid]

    receive do
      {:subscribe, ^appref, {action, from}} ->
        Process.monitor from
        subscribers = Dict.put(subscribers,
                               action,
                               [from | subscribers[action] || []])
        apploop appstate, subscribers

      {:unsubscribe, ^appref, {:_, from}} ->
        subscribers = Enum.map subscribers, fn({_action, v}) ->
          v -- from
        end
        apploop appstate, subscribers

      {:unsubscribe, ^appref, {action, from}} ->
        subscribers = Dict.put(subscribers,
                               action,
                               (subscribers[action] || []) -- from)
        apploop appstate, subscribers

      {:DOWN, _ref, :process, ^apppid, _} = ev ->
        pids = Enum.reduce subscribers,
                           [],
                           fn({_, pids}, acc) -> Enum.uniq(pids ++ acc) end
        Enum.each pids, &(send &1, ev)
        :ok

      {:DOWN, _ref, :process, pid, _} ->
        subscribers = Enum.map subscribers, fn({action, pids}) ->
          if Enum.member? pids, pid do
            {action, Enum.filter(pids, &(pid !== &1))}
          else
            {action, pids}
          end
        end
        apploop appstate, subscribers

      {:input, ^appref, buf} ->
        :ok = :exec.send appstate[:runstate][:extpid], buf
        apploop appstate, subscribers

      {device, _pid, buf} when device in [:stderr, :stdout] ->
        loopaction appref, :log, {device, buf}, subscribers
        apploop appstate, subscribers
    end
  end

  defp loopaction(appref, action, term, subscribers) do
    push = cond do
      action == :_ ->
        Enum.reduce subscribers, [], fn({_k, v}, acc) ->
          Enum.merge acc, v
        end

      nil !== subscribers[action] ->
        subscribers[action]

      true ->
        []
    end

    for pid <- push || [], do:
      send(pid, {action, appref, term})
  end

  # merge a into b
  defp deepmerge(%{} = a, %{} = b) do
    Map.merge norm(b), norm(a), fn
      (_k, b1, a1) when is_map(a) and is_map(b) ->
        deepmerge(b1, a1)

      # default to overwrite value if not map/list
      (_k, _b1, a1) ->
        a1
    end
  end
  defp deepmerge(a, []), do: a
  defp deepmerge(a, [{_,_} | _] = b) when is_list(a) do
    Dict.merge a, b, fn
      (_k, b1, a1) when is_list(a) and is_list(b) ->
        deepmerge a1, b1

      # default to overwrite value if not map/list
      (_k, _b1, a1) ->
        a1
    end
  end
  defp deepmerge(_a, b), do: b

  defp norm(%{} = x), do: Map.delete(x, :__struct__)
  defp norm([]), do: %{}
  defp norm([{_,_}|_] = x), do: Enum.into(x, %{})

  @doc """
  Stops a running appliance
  """
  def stop(appref, opts \\ []) do
    case Manager.get appref do
      {:ok, {appref, appcfg}} ->
        :ok = appcfg[:handler].stop appcfg

        if true !== opts[:keep] do
          :ok = Manager.delete appref
        end
        :ok

      err ->
        err
    end
  end

  def delete(appref) do
    case Manager.get appref do
      {:ok, {appref, appcfg}} ->
        case appcfg[:state] do
          {_, :stopped} ->
            :ok = Manager.delete appref

          {_, {:crashed, _}} ->
            :ok = Manager.delete appref

          _ ->
            {:error, {:running, appref}}
        end

      err ->
        err
    end
  end


  @doc """
  Returns the status of a appliance, or all appliances if no argument is given
  """
  def status do
    {:ok, items} = Manager.list
    {:ok, Enum.into(items, %{}, fn({appref, appcfg}) ->
      {appref, appcfg[:handler].status(appcfg)}
    end)}
  end
  def status(appref) do
    case Manager.get appref do
      {:ok, {_appref, appcfg}} ->
        {:ok, appcfg[:handler].status appcfg}
    end
  end


  defp get_cfg_by_name_or_ref!(name_or_ref) do
    Config.fetch name_or_ref
  end

  defp atom_to_module(atom), do:
    :"#{__MODULE__}s.#{atom |> Atom.to_string |> String.capitalize}"
end
