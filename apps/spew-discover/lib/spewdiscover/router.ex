defmodule SpewDiscover.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/discover", SpewDiscover do
    get "/await/:query", SpewDiscover.HTTP.AwaitController, :await

    get "/subscribe/:query", SpewDiscover.HTTP.SubscribeController, :subscribe

    post "/instance", SpewDiscover.HTTP.InstanceController, :create
    get  "/instance/:appref", SpewDiscover.HTTP.InstanceController, :read
    put  "/instance/:appref", SpewDiscover.HTTP.InstanceController, :update
  end
end
