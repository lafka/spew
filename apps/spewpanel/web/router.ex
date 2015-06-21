defmodule Spewpanel.Router do
  use Spewpanel.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Spewpanel do
    pipe_through :browser # Use the default browser stack

    get "/",          DashboardController, :index
    get "/dashboard", DashboardController, :index

    get "/appliance", ApplianceController, :index
    post "/appliance", ApplianceController, :create
    get "/appliance/:ref", ApplianceController, :show

    get "/instance",  InstanceController, :index

    get "/host",        HostController, :index
    get "/host/:host",  HostController, :show

    get "/build",            BuildController, :index
    get "/build/:build",     BuildController, :show
  end

  scope "/api", Spewpanel do
    pipe_through :api
  end
end
