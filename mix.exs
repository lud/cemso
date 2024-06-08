defmodule Cemso.MixProject do
  use Mix.Project

  def project do
    [
      app: :cemso,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: true,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :observer, :wx],
      mod: {Cemso.Application, []}
    ]
  end

  defp deps do
    [
      # App
      {:req, "~> 0.5.0"},
      {:kota, "~> 0.1.0"},
      {:cli_mate, "~> 0.3.0"},
      {:nx, "~> 0.7.2"},

      # Test
      {:bypass, "~> 2.1", only: :test},
      {:briefly, "~> 0.5.1"},

      # QA
      {:credo, "~> 1.7"}
    ]
  end
end
