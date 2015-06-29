defmodule Spew.Instance do
  @moduledoc """
  Provides interface to create, start, stop, kill and communicate
  with instances
  """

  defmodule Item do
    alias Spew.Instance.Supervision
    alias Spew.Instance.Discovery
    alias Spew.Instance.Log
    alias Spew.Instance.Consol

    alias __MODULE__, as: Item

    # state() :: :stopped | :stopping | :killed | :killing | :starting |
    #            :waiting | {:crashed, reason()} | :running | :restarting
    defstruct [
      ref: nil,                       # string()
      name: nil,                      # string()
      appliance: nil,                 # the appliance ref
      runner: Spew.Runner.Systemd,    # module()
      command: nil,                   # string()
      network: [],                    # [{:bridge, :tm} | :veth]
      runtime: nil,                   # build used by instance
      mounts: [],                     # ["bind(-ro)?/[hostdir/]<rundir>" | "tmpfs/<rundir>"]
      env: [],                        # environment to set on startup
      state: {:starting, {0, 0, 0}, nil},   # {state(), now()}
      plugin_opts: [ # stores the initial plugin options the instance is called with
                # this is converted to a map where the options will be
                # stored in __init__
          Supervision: false,         # Disable supervision by default
          Discovery: [],              # Argument options to discovery
          Log: false,                 # Disable log by default
          Console: []                 # Enable console by default
      ],
      plugin: %{},
      tags: []                       # [tag, ..]
    ]

    @doc """
    Verify that the runner can handle the given specs
    """
    def runnable?(%Item{runner: mod} = spec, optimistic? \\ false) do
      caps = mod.capabilities
      unsupported = Enum.filter_map Map.to_list(spec),
        fn({k, v}) ->
          true !== supports? k, v, Enum.member?(caps, k)
        end,
        fn({k, v}) ->
          support = supports? k, v, Enum.member?(caps, k)
          if false === support do
            {k, v}
          else
            support
          end
        end

      appliance? = appliance? spec.appliance
      build? = build? spec.runtime

      case unsupported do
        [] when optimistic? or (true === appliance? and true === build?) ->
          case nil == spec.appliance || Spew.Appliance.get spec.appliance do
            true -> # in case spec.appliance := nil
              true

            {:ok, _} ->
              true

            {:error, _} = res ->
              res
          end

        unsupported ->
          unsupported = true === build? && unsupported || [elem(build?, 1) | unsupported]
          unsupported = true === appliance? && unsupported || [elem(appliance?, 1) | unsupported]
          {:error, unsupported}
      end
    end

    defp build?(nil), do: true
    defp appliance?(nil), do: true


    defp supports?(:__struct__, _, _cap?), do: true
    defp supports?(:ref, _, _cap?), do: true
    defp supports?(:name, _, _cap?), do: true
    defp supports?(:appliance, _, _cap?), do: true
    defp supports?(:runner, _, _cap?), do: true
    defp supports?(:command, nil, _cap?), do: true
    defp supports?(:plugin_opts, _opts, _cap?), do: true

    defp supports?(:network, [], _cap?), do: true
    defp supports?(:runtime, nil, _cap?), do: true
    defp supports?(:mounts, [], _cap?), do: true
    defp supports?(:env, [], _cap?), do: true
    defp supports?(:state, _, _cap?), do: true
    defp supports?(:tags, _, _cap?), do: true
    defp supports?(:plugin, plugins, _cap?) do
      unsupported = Enum.filter Dict.keys(plugins), fn
        (plugin) ->
          ! match? {:module, _}, Code.ensure_loaded :"Elixir.Spew.Instance.#{plugin}"
        end

      case unsupported do
        [] ->
          true
        plugins ->
          {:error, {:invalid_plugins, Enum.map(plugins, &(:"Elixir.Spew.Instance.#{&1}"))}}
      end
    end
    defp supports?(opt, _plugins, _cap?), do: {:error, {:invalid_option, opt}}

    @doc """
    Runs the instance
    """
    def run(spec) do
      spec.runner.run spec
    end

    @doc """
    Stop the instance

    If signal is given it will try to send the signal if supported
    by the runner
    """
    def stop(spec, signal \\ nil) do
      spec.runner.stop spec, signal
    end

    @doc """
    Kill a instance
    """
    def kill(spec) do
      spec.runner.kill spec
    end

    @doc """
    Subscribe to instance events

    Doing this should enable the caller to receive messages like
    `{:log, instancref, {:stdin | :stdout, buf}}` and `{:exit, instanceref, reason}`
    messags.
    """
    def subscribe, do: :ok = {:error, :notimplemented}
  end

  @name __MODULE__.Server

  @doc """
  Add a new instance
  """
  def add(name, %Item{} = spec, server \\ @name), do:
    GenServer.call(server, {:add, %{spec | name: name}})

  @doc """
  Retrieve a existing instance
  """
  def get(ref, server \\ @name), do:
    GenServer.call(server, {:get, ref})

  @doc """
  Delete a insert_appliances

  ## Options:
    - `kill? ::  bool()` - if the instance should be killed before deleted
    - `stop? :: bool() | signal = non_neg_integer()` - if the instance should be stoppted before deleted,
    - `exit_timeout :: timeout()` - the time to wait for instance to stop
    * `signal :: non_neg_integer()` - signal to send, if supported by runner

  If `kill?` or `stop?` options are given `wait_for_exit` is implied.
  the `exit_timeout` option may be given to tell how long to await.
  If `stop?` is given `signal` may be used.
  """
  def delete(ref, opts, server \\ @name) do
    cond do
      true === opts[:kill?] ->
        case kill ref, Dict.put(opts, :wait_for_exit, true), server do
          {:ok, _spec} ->
            GenServer.call(server, {:delete, ref})

          {:error, _} = res ->
            res
        end

      true === opts[:stop?] ->
        case stop ref, Dict.put(opts, :wait_for_exit, true), server do
          {:ok, _spec} ->
            GenServer.call(server, {:delete, ref})

          {:error, _} = res ->
            res
        end

      true ->
        GenServer.call(server, {:delete, ref})
    end
  end


  @doc """
  List all instances
  """
  def list(server \\ @name), do:
    GenServer.call(server, :list)

  @doc """
  Query all instances
  """
  def query(query \\ "", reference? \\ false, server \\ @name), do:
    GenServer.call(server, {:query, query, reference?})


  @doc """
  Start a instance
   """
  def start(ref, opts \\ [], server \\ @name), do:
    GenServer.call(server, {:start, ref, opts})

  @doc """
  Run a transient instance
  """
  def run(%Item{} = spec, server \\ @name), do:
    GenServer.call(server, {:run, spec})

  @doc """
  Stop a instance

  ## Options
    * `wait_for_exit :: bool()` - block until the instance is stopped
    * `exit_timeout :: timeout()` - the time to wait for exit
    * `signal :: non_neg_integer()` - signal to send, if supported by runner
  """
  def stop(ref, options \\ [], server \\ @name) do
    waitforexit? = options[:wait_for_exit]
    exit_timeout = options[:exit_timeout] || :infinity

    if waitforexit? do
      subscribe quote(do: {:ev, unquote(ref), {:stop, _}}), server
    end

    case GenServer.call(server, {:stop, ref, options[:signal]}) do
      {:ok, _spec} when waitforexit? ->
        receive do
          {:ev, ^ref, {:stop, _}} -> get ref, server
        after
          exit_timeout -> {:error, {:timeout, {:instance, {:stop, ref}}}}
        end

      {:ok, _spec} = res ->
        get ref, server

      {:error, _} = res ->
        res
    end
  end

  @doc """
  Kill a instance

  ## Options
    * `wait_for_exit :: bool()` - block until the instance is stopped
    * `exit_timeout :: timeout()` - the time to wait for exit
  """
  def kill(ref, options \\ [], server \\ @name) do
    waitforexit? = options[:wait_for_exit] || false
    exit_timeout = options[:exit_timeout] || :infinity

    if waitforexit? do
      subscribe quote(do: {:ev, unquote(ref), {:stop, _}}), server
    end

    case GenServer.call(server, {:kill, ref}) do
      {:ok, _spec} = res when waitforexit? ->
        receive do
          {:ev, ^ref, {:stop, _}} -> get ref, server
        after
          exit_timeout -> {:error, {:timeout, {:instance, {:kill, ref}}}}
        end

      {:ok, _spec} ->
        get ref, server

      {:error, _} = res ->
        res
    end
  end

  @doc """
  Subscribe calling process to events from instances
  """
  def subscribe(query, server \\ @name) do
    {parent, ref} = {self, make_ref}
    GenServer.call server, {:subscribe, {parent, ref}, query}
  end


  defmodule Server do
    use GenServer

    alias Spew.Instance.Item

    require Logger

    @name __MODULE__

    defmodule State do
      defstruct instances: %{},
                subscriptions: %{},
                monitors: %{}

      # parse the query here since the closure must be local to the node
      def add_subscriber(state, who, ref, query) do
        # generate a simple match function we can use later.
        # this should be local to the gen server as funs are generally
        # not distributable across Erlang nodes
        {fun, _} = Code.eval_quoted quote(do: fn(unquote(query)) -> true;
                                                (_) -> end)

        subscriptions = Map.put state.subscriptions, ref, {who, fun}
        {{:ok, ref}, %{state | subscriptions: subscriptions}}
      rescue e in ExQuery.Query.ParseException ->
        {{:error, e}, state}
      end

      def remove_subscriber(state,  ref) do
        {:ok, %{state | subscriptions: Map.delete(state.subscriptions, ref)}}
      end
      def remove_subscriber_by_pid(%{subscriptions: subscriptions = state}, pid) do
        subscriptions = Enum.filter subscriptions,
                                    fn({who, _}) -> who === pid end

        {:ok, %{state | subscriptions: subscriptions}}
      end

      @doc """
      Notify some event to subscribers
      """
      def notify(state, ref, event) do
        Enum.each state.subscriptions, fn({_ref, {who, match}}) ->
          if match.({:ev, ref, event}) do
            send who, {:ev, ref, event}
          end
        end

        {:ok, state}
      end
    end

    def start_link(opts \\ []) do
      name = opts[:name] || @name
      initopts = opts[:init] || []
      GenServer.start_link(__MODULE__, initopts, [name: name])
    end

    def init(_) do
      {:ok, %State{}}
    end

    def handle_call({:add, %{ref: ref}}, _from, state) when ref !== nil, do:
      {:reply, {:error, :ref_not_nil}, state}
    def handle_call({:add, spec}, _from, state) do
      hasinstance? = nil !== state.instances[spec.ref || Spew.Utils.hash(spec)]
      case Item.runnable? spec, true do
        true when not hasinstance? ->
          spec = %{spec | ref: ref = Spew.Utils.hash(spec)}
          instances = Map.put state.instances, ref, spec

          {:reply, {:ok, spec}, %{state | instances: instances}}

        true when hasinstance? ->
          {:reply, {:error, {:conflict, {:instance, spec.ref}}}, state}

        {:error, _} = res ->
          {:reply, res, state}
      end
    end

    def handle_call({:get, ref}, _from, state) do
      case state.instances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:instance, ref}}}, state}

        spec ->
          {:reply, {:ok, spec}, state}
      end
    end

    def handle_call({:delete, ref}, _from, state) do
      case state.instances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:instance, ref}}}, state}

        _ ->
          {:reply, :ok, %{state | instances: Map.delete(state.instances, ref)}}
      end
    end

    def handle_call(:list, _from, state), do:
      {:reply, {:ok, Map.values(state.instances)}, state}

    # @todo 2015-06-26 does not handle broken queries very well
    def handle_call({:query, q, reference?}, _from, state) do
      query = ExQuery.Query.from_string q, Item

      instances = Enum.filter_map state.instances,
        fn({_, instance}) ->
          query.(instance)
        end,
        fn
          ({ref, _instance}) when reference? -> ref
          ({ref, instance}) -> {ref, instance}
        end

      if reference? do
        {:reply, {:ok, Enum.sort(instances)}, state}
      else
        {:reply, {:ok, Enum.into(instances, %{})}, state}
      end
    rescue
      e in ExQuery.Query.Parser.ParseException ->
        {:reply, {:error, e}, state}
    end

    def handle_call({:start, ref, _opts}, from, state) do
      case state.instances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:instance, ref}}}, state}

        spec ->
          handle_call {:run, spec}, from, state
      end
    end

    def handle_call({:run, spec}, _from, state) do
      case Item.run(spec) do
        {:ok, newspec} ->
          case spec.runner.pid newspec do
            {:ok, pid} ->
              instances = Map.put state.instances, newspec.ref, newspec

              monref = Process.monitor pid
              monitors = Map.put state.monitors, {pid, monref}, spec.ref

              {:reply, {:ok, newspec}, %{state |
                                          monitors: monitors,
                                          instances: instances}}

            {:error, _err} = err  ->
              {:reply, err, state}
          end

          {:error, _} = res ->
            {:reply, res, state}
      end
    end

    def handle_call({:stop, ref, signal}, _from, state) do
      case state.instances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:instance, ref}}}, state}

        spec ->
          case Item.stop(spec) do
            {:ok, newspec} ->
              instances = Map.put state.instances, newspec.ref, newspec
              {:reply, {:ok, newspec}, %{state | instances: instances}}

            {:error, _} = res ->
              {:reply, res, state}
          end
      end
    end

    def handle_call({:kill, ref}, _from, state) do
      case state.instances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:instance, ref}}}, state}

        spec ->
          case Item.kill(spec) do
            {:ok, newspec} ->
              instances = Map.put state.instances, newspec.ref, newspec
              {:reply, {:ok, newspec}, %{state | instances: instances}}

            {:error, _} = res ->
              {:reply, res, state}
          end
      end
    end

    def handle_call({:subscribe, {who, ref}, query}, _from, state) do
      case State.add_subscriber state, who, ref, query do
        {{:ok, _ref} = res, state} ->
          Logger.debug "instance/subscribe: #{inspect who}"
          _monref = Process.monitor who
          {:reply, res, state}

        {{:error, _} = res, state} ->
          {:reply, res, state}
      end
    end

    def handle_info({:DOWN, monref, :process, pid, reason}, state) do
      case state.monitors[{pid, monref}] do
        nil ->
          {:noreply, state}

        instanceref ->
          reason = map_down_reason(reason)

          Logger.debug "instance[#{instanceref}]: exit -> #{inspect reason}"

          spec = state.instances[instanceref]
          spec = %{spec | state: {reason, :erlang.now}}

          {:ok, state} = State.notify state, spec.ref, {:stop, reason}

          instances = Map.put state.instances, spec.ref, spec
          monitors = Map.delete state.monitors, {pid, monref}

          {:noreply, %{state |
                        instances: instances,
                        monitors: monitors }}
      end
    end

    defp map_down_reason(:normal), do: :stopped
    defp map_down_reason(:killed), do: :killed
    defp map_down_reason(reason), do: {:crashed, reason}
  end
end
