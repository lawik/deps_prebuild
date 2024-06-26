defmodule DepsPrebuild.MixProject do
  use Mix.Project

  def project do
    [
      app: :deps_prebuild,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :crypto, :public_key, :ssl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:stream_gzip, "~> 0.4.2"},
      # {:hex, github: "hexpm/hex", tag: "v2.1.1"},
      {:hex_core, "~> 0.10.2"}
      # {:libzstd, "~> 1.3.7", github: "facebook/zstd", app: false},
      # {:ex_zstd, "~> 0.1.0"}
    ]
  end
end
