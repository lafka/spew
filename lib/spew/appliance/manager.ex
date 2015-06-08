defmodule Spew.Appliance.Manager do
  use GenServer

  require Logger

  alias __MODULE__, as: Self

  alias Spew.Discovery

  defmodule Supervision do
  end

  @name {:global, __MODULE__}

  defstruct apprefs: [],
    appliances: %{},
    supervision: %{},
    await: %{}

  def run([appcfg, runopts], runstate, monitor \\ nil), do:
      GenServer.call(@name, {:run, [appcfg, runopts], runstate, monitor})
  def delete(appref), do: GenServer.call(@name, {:delete, appref})
  def list, do: GenServer.call(@name, :list)
  def get(appref), do: GenServer.call(@name, {:get, appref})
  def get_by_name_or_ref(appref_or_name), do: GenServer.call(@name, {:get_by_name_or_ref, appref_or_name})
  def set(appref, k, v), do: GenServer.call(@name, {:set, appref, {k, v}})
  def await(appref, ev, timeout \\ :infinity) do
    {:ok, callbackref} = GenServer.call(@name, {:await, appref, ev})
    receive do
      {^callbackref, {:event, ^appref, ev}} ->
        {:ok, ev}
    after timeout ->
      {:error, :timeout}
    end
  end

  def add_monitor(appref, pid), do: GenServer.call(@name, {:add_monitor, appref, pid})


  def start_link do
    GenServer.start_link Self, [], name: @name
  end

  def init(_opts) do
    {:ok, %Self{}}
  end

  def handle_call({:add_monitor, appref, monitor},
                  _from,
                  %Self{apprefs: apprefs} = state) do

    monref = Process.monitor monitor
    apprefs = [{monitor, monref, appref} | apprefs]

    Logger.debug "manager: creating app w/monitor '#{inspect monitor}/#{inspect monref}' for #{appref}"

    {:reply, :ok, %{state | :apprefs => apprefs}}
  end

  def handle_call({:run, [appcfg, runopts], runstate, monitor},
                  {from, _ref},
                  state = %Self{
                                appliances: apps,
                                supervision: sups
                                }) do

    appref = appcfg[:appref] || gen_ref
    runstate = %{
      appref: appref,
      handler: appcfg[:handler],
      appcfg: appcfg,
      runopts: runopts,
      runstate: runstate,
      supstate: %{
        restarts: [],
        restartcount: 0,
        created: now
      },
      apploop: from,
      state: {now, :alive}
    }

    apps = Dict.put apps, appref, runstate

    # @todo this will override existing supervision which may be
    # inconvenient
    sups = case proc_strategy appcfg[:restart] || [] do
      %{} = m when map_size(m) === 0 ->
        sups

      newsups ->
        Dict.put sups, appref, newsups
    end

    send self, {:event, appref, {:start, 0}}

    :ok = Discovery.add appref, %{state: "waiting"}


    # we can't rely on the caller giving a pid to monitor in it's
    # opts. Therefore we store possible monitors in a searchable record
    if is_pid(monitor) do
      {:reply, :ok, state} = handle_call {:add_monitor, appref, monitor}, from, state
      {:reply, {:ok, appref}, %{state | :appliances => apps,
                                        :supervision => sups}}
    else
      Logger.debug "manager: creating app #{appref}"
      {:reply, {:ok, appref}, %{state | :appliances => apps,
                                        :supervision => sups}}
    end
  end

  def handle_call({:delete, appref},
                  _from,
                  state = %Self{appliances: apps, supervision: sup}) do

    Logger.debug "manager: removing app #{appref}"
    apps = Dict.delete apps, appref
    sup = Dict.delete sup, appref

    :ok = Discovery.delete appref

    {:reply, :ok, %{state | :appliances => apps, :supervision => sup}}
  end

  def handle_call(:list,
                  _from,
                  state = %Self{appliances: apps}) do

    {:reply, {:ok, apps}, state}
  end

  def handle_call({:get, appref},
                  _from,
                  state = %Self{appliances: apps}) do

    case apps[appref] do
      nil -> {:reply, {:error, :not_found}, state}
      appcfg -> {:reply, {:ok, {appref, appcfg}}, state}
    end
  end

  def handle_call({:get_by_name_or_ref, appref_or_name},
                  _from,
                  state = %Self{appliances: apps}) do

    case apps[appref_or_name] do
      nil when appref_or_name === nil ->
        {:reply, {:error, :not_found}, state}

      nil ->
        rest = Enum.filter apps, fn({_appref, appcfg}) -> appcfg[:appcfg][:name] === appref_or_name end
        case rest do
          [appref_and_appcfg] ->
            {:reply, {:ok, appref_and_appcfg}, state}
          [] ->
            {:reply, {:error, :not_found}, state}
        end

      appcfg ->
        {:reply, {:ok, {appref_or_name, appcfg}}, state}
    end
  end

  def handle_call({:set, appref, {k, v}},
                  _from,
                  state = %Self{appliances: apps}) do
    case apps[appref] do
      nil ->
        {:reply, {:error, :not_found}, state}

      opts ->
        # @todo - update discovery

        state = %{state | :appliances => Dict.put(apps, appref, Dict.put(opts, k, v))}
        {:reply, :ok, state}
    end
  end

  def handle_call({:await, appref, ev},
                  {from, _ref},
                  state = %Self{await: evs}) do
    callbackref = make_ref

    resolve = fn(e) ->
      send(from, {callbackref, {:event, appref, e}})
    end

    evs = Dict.put evs, appref, [{ev, resolve} | evs[appref] || []]
    Logger.debug "ev/await: #{appref} #{inspect ev}"

    {:reply, {:ok, callbackref}, %{state | :await => evs}}
  end

  # trigger crash/stop events
  def handle_info({:DOWN, monref, :process, pid, reason},
                  state = %Self{apprefs: apprefs, appliances: apps}) do

    case List.keyfind apprefs, monref, 1 do
      {^pid, ^monref, appref} ->
        case reason do
          :normal ->
            {:ok, _} = Discovery.update appref, %{state: "stopped"}
            send self, {:event, appref, :stop}

          {:owner_died, :normal} ->
            {:ok, _} = Discovery.update appref, %{state: "stopped"}
            send self, {:event, appref, :stop}

          reason ->
            {:ok, _} = Discovery.update appref, %{state: "crashed",
                                             exit_status: reason}
            send self, {:event, appref, {:crash, reason}}
        end

        apprefs = List.keydelete apprefs, monref, 1

        {:noreply, %{state | :apprefs => apprefs, :appliances => apps}}

      nil ->
        {:noreply, state}
    end
  end

  # The event stream contains:
  # {:event, appref, ev} where ev ->
  #  :stop
  #  {:crash, reason()}
  #  {:start, run_num :: int()}
  def handle_info({:event, appref, ev},
    %Self{await: waitfor, supervision: sups, appliances: apps} = state) do
    # check if there's anything todo externally
    Logger.debug "ev/recv: #{inspect {:event, appref, ev}}"

    waitfor = case waitfor[appref] do
      nil ->
        waitfor

      await ->
        Enum.filter(await, fn({match, resolve}) ->
          case match.(ev) do
            true ->
              Logger.debug "resolving task #{appref} -> #{inspect ev}"
              spawn fn -> resolve.(ev) end
              false

            false ->
              true
          end
        end) |> Enum.into %{}
    end

    # Set stop state, Appliance might have deleted it in case of stop
    # which means we must check if it actually exists before doing
    # setting it's state
    appexists? = Dict.has_key? apps, appref
    case ev do
      :stop when appexists? ->
        app = Dict.put apps[appref], :state, {now, :stopped}
        state = %{state | :appliances => Dict.put(apps, appref, app)}

      {:crash, reason} when appexists? ->
        app = Dict.put apps[appref], :state, {now, {:crashed, reason}}
        state = %{state | :appliances => Dict.put(apps, appref, app)}

      _ ->
        state
    end


    # Check if anything is required by supervision
    state = case sups[appref] do
      nil ->
        state

      supervision ->
        supervisor_action appref, ev, supervision, state
    end

    {:noreply, %{state | :await => waitfor}}
  end

  defp supervisor_action(appref, {:crash, _} = ev, %{crash: :restart}, state) do
    restart appref, :crashed, ev, state
  end
  defp supervisor_action(_, _, _, state), do: state

  defp restart(appref, appstate, reason, state) do
    app = state.appliances[appref]
    supstate = app[:supstate]
    restarts = Enum.slice [{now, appstate, reason} | app[:supstate][:restarts]], 0, 100
    supstate = supstate
      |> Dict.put(:restarts, restarts)
      |> Dict.put(:restartcount, num_restarts = supstate[:restartcount] + 1)

    app = %{app | :supstate => supstate}

    # Restart the worker in the background
    parent = self
    spawn fn ->
      # maybe update monitor
      case app[:handler].run app[:appcfg], app[:runopts] do
        {:ok, _state} ->
          nil

        {:ok, runstate, monitor} ->
          __MODULE__.add_monitor appref, monitor
          __MODULE__.set appref, :runstate, runstate
      end
      send parent, {:event, appref, {:start, num_restarts}}
    end

    %{state | :appliances => Dict.put(state.appliances, appref, app)}
  end

  defp proc_strategy(strategy), do: proc_strategy(strategy, %{})
  defp proc_strategy([], acc), do: acc
  defp proc_strategy([:crash | rest], acc), do:
    proc_strategy(rest, Dict.put(acc, :crash, :restart))
  defp proc_strategy([:always | rest], acc), do:
    proc_strategy(rest, Dict.put(acc, :crash, :restart))
  defp proc_strategy([:never | rest], acc), do:
    proc_strategy(rest, acc
      |> Dict.put(:crash, :ignore)
      |> Dict.put(:stop, :ignore))

  defp now do
    {mega, sec, ms} = :erlang.now
    mega * 1000000000 + (sec * 1000) + trunc(ms / 1000)
  end


  def gen_ref(term \\ make_ref) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
      |> Base.encode16
      |> String.downcase
      |> String.slice 0, 10
  end
end
