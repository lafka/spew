defmodule RTFA do
  use Application

  def start(_type, _args) do
    RTFA.Supervisor.start_link
  end
end
