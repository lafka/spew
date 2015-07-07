defmodule Spew.Instance do
  @moduledoc """
  Provides interface to create, start, stop, kill and communicate
  with instances
  """

  defmodule Item do
    alias __MODULE__, as: Item

    # state() :: :stopped | :stopping | :killed | :killing | :starting |
    #            :waiting | {:crashed, reason()} | :running | :restarting
    defstruct [
      ref: nil,                       # string()
      name: nil,                      # string()
      appliance: nil,                 # the appliance ref
      runner: Spew.Runner.Port,       # module()
      command: nil,                   # iolist()
      network: nil,                   # network() | nil
      runtime: nil,                   # {:build, build, target} | {:chroot,a dir}
      mounts: [],                     # ["bind(-ro)?/[hostdir/]<rundir>" | "tmpfs/<rundir>"]
      env: [],                        # environment to set on startup
      state: {:starting, 0},          # {state(), now()}
      plugin: %{},
      tags: [],                      # [tag, ..]
      hooks: %{
        start: [],
        stop: []
      }
    ]

    @doc """
    Verify that the runner can handle the given specs
    """
    def runnable?(%Item{runner: mod} = spec, optimistic? \\ false) do
      caps = mod.capabilities

      unsupported = Enum.filter_map Map.to_list(spec),
        fn({k, v}) ->
          true !== supports? k, v, Enum.member?(caps, k), caps
        end,
        fn({k, v}) ->
          support = supports? k, v, Enum.member?(caps, k), caps
          if false === support do
            {k, v}
          else
            support
          end
        end

      appliance? = appliance? spec.appliance
      build? = build? spec.runtime

      runnersupport = mod.supported?

      case unsupported do
        _ when not runnersupport ->
          {:error, {:runner, runnersupport}}

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


    defp supports?(k, v, hascap?, _allcaps), do: supports?(k, v, hascap?)
    defp supports?(:__struct__, _, _cap?), do: true
    defp supports?(:ref, _, _cap?), do: true
    defp supports?(:name, _, _cap?), do: true
    defp supports?(:appliance, _, _cap?), do: true
    defp supports?(:runner, _, _cap?), do: true
    defp supports?(:command, nil, _cap?), do: true
    defp supports?(:hooks, _opts, _cap?), do: true

    defp supports?(:network, nil, _cap?), do: true
    defp supports?(:runtime, nil, _cap?), do: true
    defp supports?(:mounts, [], _cap?), do: true
    defp supports?(:env, [], _cap?), do: true
    defp supports?(:state, _, _cap?), do: true
    defp supports?(:tags, _, _cap?), do: true
    defp supports?(:plugin, plugins, _cap?) do
      unsupported = Enum.filter Dict.keys(plugins), fn
        (plugin) ->
          ! match? {:module, _}, Code.ensure_loaded plugin
        end

      case unsupported do
        [] ->
          true
        plugins ->
          {:error, {:invalid_plugins, plugins}}
      end
    end
    defp supports?(_opt, _plugins, true), do: true
    defp supports?(opt, _plugins, _cap?), do: {:error, {:invalid_option, opt}}

    @doc """
    Runs the instance

    Does the following:
      1) Setup the overlayfs system to use for chroot (if runtime specified)
      2) Setup cleanup hooks to unmount he overlayfs
    """
    def run(%Item{} = spec), do: run(spec, [])
    def run(%Item{} = spec, opts) do
      spec.runner.run spec, opts
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
    Subscribe to the output process of the instance
    """
    def subscribe(spec) do
      spec.runner.subscribe spec, self
    end

    def write(spec, buf \\ []) do
      spec.runner.write spec, buf
    end
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
  def run(%Item{} = spec, opts \\ [], server \\ @name), do:
    GenServer.call(server, {:run, spec, opts})

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

      {:ok, _spec} ->
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
      {:ok, _spec} when waitforexit? ->
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
  Notify a instance of an event
  """
  def notify(ref, ev, server \\ @name) do
    GenServer.call server, {:notify, ref, ev}
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
      alias Spew.Plugin

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
      Notify some event to subscribers, and update plugins for any
      instances involved.

      Any errors in plugins are ignored unless `strict` is set to true
      """
      def notify(state, ref, event, strict \\ false) do
        instance = state.instances[ref]

        publish = fn(state) ->
          Enum.each state.subscriptions, fn({_ref, {who, match}}) ->
            if match.({:ev, ref, event}) do
              send who, {:ev, ref, event}
            end
          end
        end

        state = case Plugin.notify instance, instance.plugin, event do
          {:ok, plugins} ->
            instance = %{instance | plugin: plugins}
            state = %{state | instances: Map.put(state.instances, ref, instance)}

            publish.(state)
            {:ok, state}

          {:error, {plugin, err}, remaining, instance} when false == strict ->
            Logger.warn """
            instance[#{ref}]: plugin error #{plugin}:
              error: #{inspect err}
              remaining plugins: #{Enum.join remaining, ", "}"
            """
            state = %{state | instances: Map.put(state.instances, ref, instance)}

            publish.(state)
            {:ok, state}

          {:error, {plugin, err}, remaining, instance} when true == strict ->
            state = %{state | instances: Map.put(state.instances, ref, instance)}
            {:error, {err, {:plugin, plugin}}, state}
        end
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
          instance = %{spec | ref: ref = Spew.Utils.hash(spec)}

          plugins = Map.put spec.plugin, spec.runner, nil
          case Spew.Plugin.init spec, plugins do
            {:ok, plugins} ->
              instance = %{instance | plugin: plugins}
              instances = Map.put state.instances, instance.ref, instance

              {:ok, state} = State.notify %{state | instances: instances},
                                          instance.ref,
                                          :add

              {:reply, {:ok, state.instances[ref]}, state}

            {:error, {:invalid_return, err, {:plugin, p}}} ->
              Spew.Plugin.cleanup spec, spec.plugin
              {:error, {err, {:plugin, p}}}
          end

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
          {:ok, %{instances: instances} = state} = State.notify state, ref, :delete

          # tell plugins to cleanup
          case Spew.Plugin.cleanup instances[ref], instances[ref].plugin do
            :ok ->
              {:reply,
               {:ok, state.instances[ref]},
               %{state | instances: Map.delete(state.instances, ref)}}

            {:error, err} ->
              {:error, {:plugins, err, {:instance, ref}}}
          end
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

    def handle_call({:start, ref, opts}, from, state) do
      case state.instances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:instance, ref}}}, state}

        spec ->
          handle_call {:run, spec, opts}, from, state
      end
    end

    def handle_call({:run, instance, opts}, _from, state) do

      instance = if ! instance.ref do
        %{instance | ref: Spew.Utils.hash(instance)}
      else
        instance
      end

      # Don't break on bad hooks
      res = try do callbacks [instance], instance.hooks[:start] || []
            catch e -> {:error, e} end

      cleanup = fn(instance, reason) ->
        try do
          callbacks [instance, reason], instance.hooks[:stop] || [], false
          Spew.Plugin.cleanup instance, instance.plugin
        catch
          e -> {:error, e}
        end
      end

      # a spec might be given directly, if so plugins are not initialized
      {res, state, instance} = if :ok === res and ! Map.has_key?(state.instances, instance.ref) do
        plugins = Map.put instance.plugin, instance.runner, nil
        Logger.debug "instance[#{instance.ref}]: initializing plugins: #{Enum.join(Map.keys(plugins), ", ")}"

        case Spew.Plugin.init instance, plugins do
          {:ok, plugins} ->
            instance = %{instance | plugin: plugins}
            instances = Map.put state.instances, instance.ref, instance

            {:ok, %{state | instances: instances}, instance}

          {:error, {:invalid_return, err, {:plugin, p}}} ->
            Spew.Plugin.cleanup instance, instance.plugin
            {{:error, {err, {:plugin, p}}}, state, instance}
        end
      else
        {res, state, instance}
      end

      case res do
        :ok ->
          {err, state} = case State.notify(%{state | instances: instances},
                                           instance.ref,
                                           :start,
                                           true) do
            {:ok, state} -> {nil, state}
            {:error, err, state} -> {{:error, err}, state}
          end

          case err || Item.run(state.instances[instance.ref], opts) do
            {:ok, %Item{ref: ref} = instance} ->
              case instance.runner.pid instance do
                {:ok, pid} ->
                  instances = Map.put state.instances, instance.ref, instance

                  {:ok, state} = State.notify %{state | instances: instances},
                                              instance.ref,
                                              :started

                  instance = state.instances[ref]

                  monref = Process.monitor pid
                  monitors = Map.put state.monitors, {pid, monref}, instance.ref

                  {:reply, {:ok, instance}, %{state | monitors: monitors,
                                                      instances: state.instances}}

                err ->
                  cleanup.(instance, err)
                  {:reply, err, state}
              end

            {:error, _} = res ->
              cleanup.(state.instances[instance.ref], res)
              {:reply, res, state}
          end

        res ->
          cleanup.(res)
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
              {:ok, state} = State.notify %{state | instances: instances},
                                          spec.ref,
                                          {:stopping, signal}

              {:reply, {:ok, state.instances[ref]}, state}

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
              {:ok, state} = State.notify %{state | instances: instances},
                                          spec.ref,
                                          :killing

              {:reply, {:ok, state.instances[ref]}, state}

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

    def handle_call({:notify, ref, ev}, _from, state) do
      case state.instances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:instance, ref}}}, state}

        instance ->
          {:ok, state} = State.notify state,
                                      instance.ref,
                                      {:event, ev}
        {:reply, {:ok, state.instances[ref]}, state}
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
          spec = %{spec | state: {reason, Spew.Utils.Time.now(:milli_seconds)}}
          instances = Map.put state.instances, spec.ref, spec

          # we don't care about the result of the hooks, just don't crash
          try do
            callbacks [spec, reason], spec.hooks[:stop] || [], false
          catch
            e -> {:error, e}
          end

          {:ok, state} = State.notify %{state | instances: instances},
                                      spec.ref,
                                      {:stop, reason}

          monitors = Map.delete state.monitors, {pid, monref}

          {:noreply, %{state | monitors: monitors }}
      end
    end

    def handle_info(ev, state) do
      Logger.warn "instance: unexpected msg: #{inspect ev}"
      {:noreply, state}
    end

    defp map_down_reason(:normal), do: :normal
    defp map_down_reason(:killed), do: :killed
    defp map_down_reason(reason), do: {:crashed, reason}

    defp callbacks(args, funs), do: callbacks(args, funs, true)
    defp callbacks(_args, [], _strict?), do: :ok
    defp callbacks(args, [fun | rest], strict?) do
      case apply fun, args do
        :ok ->
          callbacks args, rest, strict?

        res ->
          res
      end
    rescue _e in BadArityError ->
      if true === strict? do
        {:error, {:callback, {:badarit, fun}}}
      else
        Logger.error "instance/callbacks: bad arity in #{inspect fun}"
        callbacks args, rest, strict?
      end
    end
  end
end
