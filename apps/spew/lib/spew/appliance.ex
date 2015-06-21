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

    alias Spew.Appliance.Item

    defmodule State do
      defstruct appliances: %{}
    end

    def start_link do
      GenServer.start_link @name, %{}, name: @name
    end

    def init(_) do
      # todo load appliance config from disk
      {:ok, %State{}}
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

          ref = hash appliance
          appliance = %{appliance | ref: ref}

          {:reply,
            {:ok, appliance},
            %{state | appliances: Dict.put(state.appliances, ref, appliance)}}

        [{ref, _} | _] ->
          {:reply, {:error, {:conflict, {:appliance, ref}}}, state}
      end
    end

    def handle_call({:get, ref}, _from, state) do
      case state.appliances[ref] do
        nil ->
          {:reply, {:error, {:notfound, {:appliance, ref}}}, state}

        appliance ->
          {:reply, {:ok, appliance}, state}
      end
    end

    def handle_call(:list, _from, state) do
      {:reply, {:ok, Dict.values(state.appliances)}, state}
    end

    def handle_call({:delete, ref}, _from, %{appliances: appliances} = state) do
      {:reply, :ok, %{state | appliances: Dict.delete(appliances, ref)}}
    end

    defp hash(data) do
      :crypto.hash(:sha256, :erlang.term_to_binary(data))
        |> Base.encode32
        |> String.slice(0, 16)
        |> String.downcase
    end
  end
end
