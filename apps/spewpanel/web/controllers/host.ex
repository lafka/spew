defmodule Spewpanel.HostController do
  use Spewpanel.Web, :controller

  plug :action

  def index(conn, _params) do
    hosts = Spew.Host.query []
    render conn, "index.html", hosts: hosts
  end

  def show(conn, %{"id" => id}) do
    case Spew.Host.get id do
      {:ok, host} ->
        render conn, "item.html", id: id

      {:error, {:notfound, {:host, id}}} ->
        hosts = Spew.Host.query []
        render conn, "404.html", id: id, hosts: hosts
    end
  end
end
