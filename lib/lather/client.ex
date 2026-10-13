defmodule Lather.Client do
  @moduledoc """
  Main SOAP client interface.

  This module provides the primary API for making SOAP requests.
  """

  alias Lather.Http.Transport
  alias Lather.Soap.Envelope

  defstruct [:endpoint, :options]

  @type t :: %__MODULE__{
          endpoint: String.t(),
          options: keyword()
        }

  @doc """
  Creates a new SOAP client for the given endpoint.

  ## Options

  * `:timeout` - Request timeout in milliseconds (default: 30_000)
  * `:headers` - Additional HTTP headers to include with requests
  * `:ssl_options` - SSL options for HTTPS connections
  * `:soap_version` - SOAP version (`:v1_1` or `:v1_2`)
  * `:soap_headers` - SOAP envelope headers
  * `:namespace` - Target namespace for the operation
  * `:namespace_prefix` - Prefix for the operation namespace
  * `:raw_body` - Use parameters directly as the SOAP body

  ## Examples

      iex> _client = Lather.Client.new("https://example.com/soap")
      %Lather.Client{endpoint: "https://example.com/soap", options: []}

  """
  @spec new(String.t(), keyword()) :: t()
  def new(endpoint, options \\ []) do
    %__MODULE__{
      endpoint: endpoint,
      options: options
    }
  end

  @doc """
  Makes a SOAP request to the specified operation.

  ## Parameters

  * `client` - The SOAP client
  * `operation` - The SOAP operation name (atom or string)
  * `params` - Parameters for the operation
  * `options` - Request-specific options

  Call options override options passed to `new/2`. `:headers` contains HTTP
  headers; use `:soap_headers` for headers inside the SOAP envelope.

  ## Examples

      iex> _client = Lather.Client.new("https://example.com/soap")
      iex> # This would make an actual HTTP request:
      iex> # Lather.Client.call(client, :get_user, %{id: 123})

  """
  @spec call(t(), atom() | String.t(), map(), keyword()) :: {:ok, any()} | {:error, any()}
  def call(client, operation, params, options \\ []) do
    options = Keyword.merge(client.options, options)

    envelope_options =
      [
        version: Keyword.get(options, :soap_version, :v1_1),
        headers: Keyword.get(options, :soap_headers, [])
      ] ++ Keyword.take(options, [:namespace, :namespace_prefix, :raw_body])

    transport_options =
      Keyword.take(options, [
        :timeout,
        :pool_timeout,
        :headers,
        :soap_action,
        :soap_version,
        :ssl_options,
        :basic_auth
      ])

    with {:ok, envelope} <- Envelope.build(operation, params, envelope_options),
         {:ok, response} <- Transport.post(client.endpoint, envelope, transport_options),
         {:ok, result} <- Envelope.parse_response(response) do
      {:ok, result}
    end
  end
end
