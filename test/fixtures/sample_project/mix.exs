defmodule SampleProject.MixProject do
  use Mix.Project

  def project do
    [
      app: :sample_project,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Plain Elixir package
      jason: "~> 1.4.3",
      # Elixir package with C/C++ NIF, precompiled
      evision: "~> 0.2.7",
      # Elixir package with Rustler NIF, precompiled
      explorer: "~> 0.8.3",
      # Erlang with NIF
      jiffy: "~> 1.1.2",
      # Plain Erlang package
      telemetry: "~> 1.2.1",
      # Plain Erlang package, with plugins
      hex_core: "~> 0.10.3"
    ]
  end
end
