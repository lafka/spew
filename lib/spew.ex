defmodule Spew do
  use Application

  def start(_type, _args) do
    Spew.Supervisor.start_link
  end
end
