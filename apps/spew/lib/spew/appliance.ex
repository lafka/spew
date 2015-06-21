defmodule Spew.Appliance do
  @moduledoc """
  Provide interface to create, configure, run appliances
  """

  @name __MODULE__.Server

  @doc """
  Add a new appliance definition
  """
  def add(name, {_app_t, _app_spec} = app, instanceopts, enabled? \\ true), do:
    GenServer.call(@name, {:add, name, app, instanceopts, enabled?})

  def get(ref), do: GenServer.call(@name, {:get, ref})

  @doc """
  List all running appliances
  """
  def list, do: GenServer.call(@name, :list)

  @doc """
  Delete a appliance
  """
  def delete(ref), do: GenServer.call(@name, {:delete, ref})

  @doc """
  Reload configuration from disk
  """
  def reload, do: GenServer.call(@name, :reload)

  if Mix.env in [:dev, :test] do
    def reset, do: GenServer.call(@name, :reset)
  end

  defmodule Item do
    defstruct [
      ref: nil,                             # the actual id of the appliance
      name: nil,                            # string()
      appliance: {"spew-archive-1.0", nil}, # What type of appliance, second argument is the build spec
      instance: %Spew.Instance.Item{        # defaults is merged with instance cfg
        runner: Spew.Runner.Systemd,
        supervision: false,
        network: [],
        rootfs: {nil, nil},
        mounts: [],
        env: []
      },
      enabled?: true
    ]
  end

  defmodule Server do
    use GenServer

    @name __MODULE__

    require Logger

    alias Spew.Utils
    alias Spew.Appliance.Item

    defmodule State do
      defstruct appliances: %{},
                names: %{}
    end

    def start_link do
      GenServer.start_link @name, %{}, name: @name
    end

    def init(_) do
      {:reply, :ok, state} = handle_call :reload, {self, make_ref}, %State{}
      {:ok, state}
    end

    defp load_configs() do
      searchpath = [
        Path.join([Spew.root, "appliances", "*"])
        | Application.get_env(:spew, :appliancepaths) || []
      ]

      Enum.reduce searchpath, %{}, fn(path, acc) ->
        path = Path.join path, "*.exs"
        Path.expand(path)
          |> Path.wildcard
          |> Enum.reduce acc, fn(file, acc) ->

          {cfg, []} = Code.eval_file file
          ref = Utils.hash cfg
          val = Map.merge %Item{}, Map.put(cfg, :ref, ref)
          Map.put_new acc, ref, val
        end
      end
    end

    def handle_call(:reload, _from, state) do
      appliances = load_configs

      names = Enum.reduce appliances, %{}, fn({ref, %{name: name}}, acc) ->
        Map.put(acc, name, ref)
      end

      Logger.debug "found #{Map.size(appliances)} appliances"
      {:reply, :ok, %State{ appliances: appliances,
                            names: names}}
    end

    def handle_call({:add, name, {_t, _spec} = app, instance, enabled?}, _from, state) do
      case Enum.drop_while state.appliances,
                           fn({_ref, appliance}) -> appliance.name !== name end do
        [] ->
          appliance = %Item{
            name: name,
            appliance: app,
            instance: Map.merge(%Item{}.instance, instance),
            enabled?: enabled?
          }

          ref = Utils.hash appliance
          appliance = %{appliance | ref: ref}

          {:reply,
            {:ok, appliance},
            %{state |
              appliances: Map.put(state.appliances, ref, appliance),
              names: Map.put(state.names, name, ref)}}

        [{ref, _} | _] ->
          {:reply, {:error, {:conflict, {:appliance, ref}}}, state}
      end
    end

    def handle_call({:get, ref}, _from, state) do
      case state.appliances[ref] || state.appliances[ state.names[ref] ]do
        nil ->
          {:reply, {:error, {:notfound, {:appliance, ref}}}, state}

        appliance ->
          {:reply, {:ok, appliance}, state}
      end
    end

    def handle_call(:list, _from, state) do
      {:reply, {:ok, Dict.values(state.appliances)}, state}
    end

    def handle_call({:delete, ref}, _from, state) do
      case {state.appliances[ref], state.appliances[ state.names[ref] ]} do
        {nil, nil} ->
          {:error, {:notfound, {:appliance, ref}}}

        {app, nil} ->
          {:reply, :ok, %{state |
            appliances: Map.delete(state.appliances, ref),
            names: Map.delete(state.names, app.name)}}

        {_, appref} ->
          {:reply, :ok, %{state |
            appliances: Map.delete(state.appliances, appref),
            names: Map.delete(state.names, ref)}}
      end
    end

    if Mix.env in [:dev, :test] do
      def handle_call(:reset, _from, _) do
        {:reply, :ok, %State{}}
      end
    end
  end
end
