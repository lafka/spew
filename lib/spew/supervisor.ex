defmodule Spew.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    serveropts = Application.get_env(:spew, :discovery)[:opts]
    serverschema = Application.get_env(:spew, :discovery)[:schema]

    children = [
      worker(Spew.Appliance.Manager, []),
      worker(Spew.Appliance.Config.Server, []),
      worker(Spew.Discovery.Server, []),
      Plug.Adapters.Cowboy.child_spec(serverschema, Spew.Discovery.HTTP, [], serveropts)
    ]

    supervise(children, strategy: :one_for_one)
  end

end
