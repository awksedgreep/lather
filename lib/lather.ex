defmodule Lather do
  @moduledoc """
  Lather - A full-featured SOAP library for Elixir.

  Lather provides a comprehensive SOAP client implementation with support for:
  - SOAP 1.1 and 1.2 protocols
  - WSDL parsing and code generation
  - WS-Security authentication
  - Connection pooling via Finch
  - Telemetry integration

  ## Usage

  Basic SOAP client usage:

      iex> client = Lather.Client.new("http://example.com/soap")
      iex> Lather.Client.call(client, :operation_name, %{param: "value"})

  """

  @doc """
  Returns the version of the Lather library.
  """
  def version do
    Application.spec(:lather, :vsn) |> to_string()
  end
end
