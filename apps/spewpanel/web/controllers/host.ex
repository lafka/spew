defmodule Spewpanel.HostController do
  use Spewpanel.Web, :controller

  plug :action

  def index(conn, _params) do
    hosts = Spew.Host.query([]) |> Enum.map(&augment_host/1)
    render conn, "index.html", hosts: hosts
  end

  def show(conn, %{"host" => id}) do
    case Spew.Host.get id do
      {:ok, host} ->
        host = augment_host host
        render conn, "item.html", id: id, host: host

      {:error, {:notfound, {:host, id}}} ->
        hosts = Spew.Host.query []
        render conn, "404.html", id: id, hosts: hosts
    end
  end

  defp augment_host(host) do
    # use .query "#{node} in hosts"
    {:ok, builds} = Spew.Build.list
    {:ok, appliances} = Spew.Appliance.list

    builds = Enum.filter builds,
      fn({_ref, build}) ->
        Enum.member? build.hosts, host.name
      end

    appliances = Enum.filter appliances,
      fn(appliance) ->
        Enum.member? appliance.hosts, host.name
      end

    host
      |> Map.put(:builds, builds)
      |> Map.put(:appliances, appliances)
  end
end
