defmodule Spew.Mixfile do
  use Mix.Project

  def project do
    [
      app: :spew,
      version: "0.0.1",
      elixir: "~> 1.0",
      deps: deps]
  end

  def application do
    [
      mod: {Spew, []},
      applications: [
        :logger,
        :exec,
        :cowboy,
        :plug
      ]
    ]
  end

  defp deps do
    [
      {:exrm, "== 0.15.3"},
      {:exec, github: "saleyn/erlexec"},
      {:cowboy, "~> 1.0.0"},
      {:plug, "~> 0.12"},
      {:poison, "~> 1.4.0"}
    ]
  end
end
