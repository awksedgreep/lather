defmodule Lather.MixProject do
  use Mix.Project

  def project do
    [
      app: :lather,
      version: "1.0.4",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description:
        "Production-ready SOAP library for Elixir featuring SOAP 1.1/1.2 support, dynamic WSDL parsing, " <>
          "interactive web forms, MTOM attachments, Phoenix integration, and multi-protocol API generation",
      source_url: "https://github.com/awksedgreep/lather",
      homepage_url: "https://github.com/awksedgreep/lather",
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
      {:jason, "~> 1.4", optional: true},
      {:plug, "~> 1.14", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Mark Cotner"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/awksedgreep/lather",
        "Documentation" => "https://hexdocs.pm/lather",
        "Changelog" => "https://github.com/awksedgreep/lather/blob/main/CHANGELOG.md"
      },
      files:
        ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md USAGE.md TESTING.md API.md RELEASE_NOTES_1.0.0.md TODO.md),
      keywords: [
        "soap",
        "soap12",
        "wsdl",
        "xml",
        "web-services",
        "client",
        "server",
        "phoenix",
        "mtom",
        "attachments",
        "elixir",
        "http",
        "rpc"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Lather SOAP Library",
      source_ref: "v1.0.4",
      source_url: "https://github.com/awksedgreep/lather",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "USAGE.md",
        "TESTING.md",
        "API.md",
        "RELEASE_NOTES_1.0.0.md",
        "TODO.md"
      ],
      groups_for_extras: [
        "Getting Started": ["README.md", "USAGE.md"],
        Reference: ["API.md", "TESTING.md"],
        "Release Info": ["CHANGELOG.md", "RELEASE_NOTES_1.0.0.md"],
        Development: ["TODO.md"]
      ],
      groups_for_modules: [
        Core: [Lather, Lather.Client, Lather.DynamicClient],
        Server: [
          Lather.Server,
          Lather.Server.Plug,
          Lather.Server.EnhancedPlug,
          Lather.Server.WsdlGenerator,
          Lather.Server.EnhancedWSDLGenerator,
          Lather.Server.FormGenerator
        ],
        "SOAP Processing": [
          Lather.Soap.Envelope,
          Lather.Operation.Builder,
          Lather.Wsdl.Parser
        ],
        "Transport & HTTP": [
          Lather.Http.Transport
        ],
        "XML Processing": [
          Lather.Xml.Builder,
          Lather.Xml.Parser
        ],
        "MTOM & Attachments": [
          Lather.Mtom.Builder,
          Lather.Mtom.Attachment,
          Lather.Mtom.Mime
        ]
      ],
      before_closing_head_tag: &docs_before_closing_head_tag/1,
      before_closing_body_tag: &docs_before_closing_body_tag/1
    ]
  end

  defp docs_before_closing_head_tag(:html) do
    """
    <meta name="keywords" content="elixir,soap,wsdl,xml,web-services,phoenix,soap12">
    <meta name="description" content="Production-ready SOAP library for Elixir with SOAP 1.2 support">
    """
  end

  defp docs_before_closing_head_tag(_), do: ""

  defp docs_before_closing_body_tag(:html) do
    """
    <!-- Analytics could go here -->
    """
  end

  defp docs_before_closing_body_tag(_), do: ""
end
