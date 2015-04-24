defmodule RTFA.Appliance do

  alias RTFA.Appliance.Config
  alias RTFA.Appliance.Manager

  @doc """
  Creates a appliance
  """
  def create(name, appopts), do:
    create(name, appopts, [])
  def create(name, appopts = %Config.Item{}, opts) do
    case Config.fetch name do
      {:ok, {cfgref, _}} ->
        {:error, {:appliance_exists, cfgref}}

      {:error, {:not_found, _}} ->
        Config.store Map.put(appopts, :name, name)
    end
  end
  def create(_appref_or_name, _, _opts), do:
    {:error, {:argument_error, "appopts must be of type RTFA.Appliance.Config.Item"}}


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
        appopts = Map.merge cfgappopts, appopts
        module = atom_to_module appopts.type

        appopts = %{appopts | :handler => module}
        case module.run appopts, opts do
          {:ok, state} ->
            Manager.run [appopts, opts], state

          {:ok, state, monitor} ->
            Manager.run [appopts, opts], state, monitor

          {:error, _err} = error ->
            error
        end
    end
  end

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
      {:ok, {appref, appcfg}} ->
        {:ok, appcfg[:handler].status appcfg}
    end
  end


  defp get_cfg_by_name_or_ref!(name_or_ref) do
    Config.fetch name_or_ref
  end

  defp atom_to_module(atom), do:
    :"#{__MODULE__}s.#{atom |> Atom.to_string |> String.capitalize}"
end
