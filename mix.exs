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
        :exec
      ]
    ]
  end

  defp deps do
    [
      {:exrm, "== 0.15.3"},
      {:exec, github: "saleyn/erlexec"}
    ]
  end
end
