defmodule RTFA.Mixfile do
  use Mix.Project

  def project do
    [
      app: :rtfa,
      version: "0.0.1",
      elixir: "~> 1.0",
      escript: escript,
      deps: deps]
  end

  def escript do
    [
      main_module: RTFACLI,
      name: "rtfa-cli",
      path: "bin/rtfa-cli",
      embed_elixir: true
    ]
  end

  def application do
    [
      mod: {RTFA, []},
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
