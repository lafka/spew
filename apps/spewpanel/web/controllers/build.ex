defmodule Spewpanel.BuildController do
  use Spewpanel.Web, :controller

  plug :action

  def index(conn, params) do
    query = params["query"] || ""

    {:ok, tree} = Spew.Build.query "", true
    {:ok, builds} = Spew.Build.list

    q = ExQuery.Query.from_string query, Spew.Build.Item
    builds = Enum.filter builds, fn({k, e}) -> match? = q.(e) end

    render conn, "index.html", builds: builds,
                               tree: tree,
                               params: params
  end

  def show(conn, %{"build" => id} = params) do
    case Spew.Build.get id do
      {:ok, build} ->
        render conn, "item.html", params: params, build: build

      {:error, {:notfound, {:build, id}}} ->
        {:ok, tree} = Spew.Build.query "", true
        {:ok, builds} = Spew.Build.list

        render conn, "404.html", builds: builds,
                                 tree: tree,
                                 params: params
    end
  end
end

