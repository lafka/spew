defmodule Spewpanel.ApplianceController do
  use Spewpanel.Web, :controller

  plug :action

  def index(conn, params) do
    case params["create"] do
      nil ->
        {:ok, appliances} = Spew.Appliance.list
        render conn, "index.html", appliances: appliances, params: params

      "true" ->
        {:ok, builds} = Spew.Build.list
        render conn, "create.html", params: params, builds: builds
    end
  end

  def create(conn, params) do
    {:ok, builds} = Spew.Build.list
    render conn, "create.html", params: params, builds: builds
  end

  def show(conn, %{"ref" => ref}) do
    case Spew.Appliance.get ref do
      {:ok, appliance} ->
        render conn, "item.html", ref: ref, appliance: appliance

      {:error, {:notfound, {:appliance, ^ref}}} ->
        render conn, "404.html", ref: ref
    end
  end
end
