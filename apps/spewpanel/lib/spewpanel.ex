defmodule Spewpanel do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Spewpanel.Endpoint, []),
    ]

    opts = [strategy: :one_for_one, name: Spewpanel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    Spewpanel.Endpoint.config_change(changed, removed)
    :ok
  end
end
