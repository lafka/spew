defmodule SpewDiscover.Mixfile do
  use Mix.Project

  def project do
    [app: :spewdiscover,
     version: "0.0.1",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [#mod: {SpewDiscover, []},
     applications: [:phoenix, :cowboy, :logger]]
  end

  defp deps do
    [{:phoenix, "~> 0.13.1"},
     {:cowboy, "~> 1.0"}]
  end
end
