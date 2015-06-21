defmodule SpewDiscover.HTTP do
  use Phoenix.Endpoint, otp_app: :spewdiscover

  if code_reloading? do
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Poison

  plug Plug.MethodOverride
  plug Plug.Head

  plug :router, SpewDiscover.Router
end

