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
  * `:ssl` - SSL options for HTTPS connections

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

  ## Examples

      iex> _client = Lather.Client.new("https://example.com/soap")
      iex> # This would make an actual HTTP request:
      iex> # Lather.Client.call(client, :get_user, %{id: 123})

  """
  @spec call(t(), atom() | String.t(), map(), keyword()) :: {:ok, any()} | {:error, any()}
  def call(client, operation, params, options \\ []) do
    with {:ok, envelope} <- Envelope.build(operation, params),
         {:ok, response} <- Transport.post(client.endpoint, envelope, client.options ++ options),
         {:ok, result} <- Envelope.parse_response(response) do
      {:ok, result}
    end
  end
end
