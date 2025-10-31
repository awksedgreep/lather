defmodule Lather.MixProject do
  use Mix.Project

  def project do
    [
      app: :lather,
      version: "0.9.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: "A comprehensive SOAP library for Elixir with client and server support, WSDL parsing, and Phoenix integration",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Lather.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.16"},
      {:sweet_xml, "~> 0.7"},
      {:xml_builder, "~> 2.2"},
      {:telemetry, "~> 1.2"},
      {:plug, "~> 1.14", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Mark Cotner"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/markcotner/lather",
        "Documentation" => "https://hexdocs.pm/lather"
      },
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md),
      keywords: ["soap", "wsdl", "xml", "web services", "client", "server", "phoenix"]
    ]
  end

  defp docs do
    [
      main: "Lather",
      extras: ["README.md"]
    ]
  end
end
