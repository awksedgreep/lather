defmodule Lather.TestClient do
  @moduledoc """
  Lightweight helpers for testing Lather SOAP services without starting a
  real HTTP server.

  `Lather.Server.EnhancedPlug` is invoked directly with `Plug.Test`
  connections, so operation handlers, validation, WSDL/OpenAPI endpoints,
  and forms can all be exercised in unit tests.

  ## Example

      config = Lather.TestClient.new(MyApp.UserService)

      conn = Lather.TestClient.call_json(config, "GetUser", %{"id" => "42"})
      assert Lather.TestClient.status(conn) == 200
      assert Lather.TestClient.json_body(conn)["data"]["name"] == "Ada"

      conn = Lather.TestClient.call_soap(config, "Echo", %{"message" => "hi"})
      assert Lather.TestClient.body(conn) =~ "hi"
  """

  import Plug.Test

  alias Lather.Server.{EnhancedPlug, ResponseBuilder}

  @doc """
  Builds an EnhancedPlug configuration for a service module. Accepts the
  same options as `Lather.Server.EnhancedPlug.init/1`.
  """
  def new(service_module, options \\ []) do
    EnhancedPlug.init([service: service_module] ++ options)
  end

  @doc """
  Invokes a JSON/REST operation (`POST /api/OperationName`) with a params
  map and returns the resulting `Plug.Conn`.
  """
  def call_json(config, operation, params) do
    conn(:post, config.base_path <> "/api/" <> operation, Jason.encode!(params))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> EnhancedPlug.call(config)
  end

  @doc """
  Invokes an operation via SOAP. Builds a SOAP envelope from the params
  map and posts it to the service base path.

  ## Options

    * `:version` - `:v1_1` (default) or `:v1_2`
    * `:namespace` - Namespace for the operation element (defaults to the
      service's target namespace)
  """
  def call_soap(config, operation, params, options \\ []) do
    version = Keyword.get(options, :version, :v1_1)
    namespace = Keyword.get(options, :namespace, target_namespace(config.service))

    body_params =
      params
      |> Enum.map(fn {name, value} ->
        attrs = attribute_attrs(value)
        content = value_content(value)
        "<#{name}#{attrs}>#{escape_content(content)}</#{name}>"
      end)
      |> Enum.join("")

    envelope = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="#{soap_namespace(version)}">
      <soap:Body>
        <#{operation} xmlns="#{namespace}">#{body_params}</#{operation}>
      </soap:Body>
    </soap:Envelope>
    """

    conn(:post, config.base_path, envelope)
    |> Plug.Conn.put_req_header("content-type", ResponseBuilder.content_type(version))
    |> EnhancedPlug.call(config)
  end

  @doc """
  Requests the service WSDL. Set `enhanced: false` for the standard WSDL.
  """
  def wsdl(config, enhanced \\ true) do
    path =
      if enhanced do
        config.base_path <> "?wsdl&enhanced=true"
      else
        config.base_path <> "?wsdl&enhanced=false"
      end

    conn(:get, path) |> EnhancedPlug.call(config)
  end

  @doc "Requests the OpenAPI 3.1 document for the service."
  def openapi(config) do
    conn(:get, config.base_path <> "?openapi") |> EnhancedPlug.call(config)
  end

  @doc "Requests the service health check."
  def health(config) do
    conn(:get, config.base_path <> "?health") |> EnhancedPlug.call(config)
  end

  @doc "Returns the HTTP status of a response connection."
  def status(conn), do: conn.status

  @doc "Returns the raw response body."
  def body(conn), do: conn.resp_body

  @doc "Decodes the response body as JSON."
  def json_body(conn), do: Jason.decode!(conn.resp_body)

  defp target_namespace(service) do
    service.__soap_service__()[:namespace] || "urn:lather"
  end

  defp soap_namespace(:v1_2), do: "http://www.w3.org/2003/05/soap-envelope"
  defp soap_namespace(_), do: "http://schemas.xmlsoap.org/soap/envelope/"

  # Values given as %{"@attributes" => attrs, "@value" => text} become XML
  # attributes so nested structures stay easy to express in tests.
  defp attribute_attrs(%{"@attributes" => attrs}) when is_map(attrs) do
    attrs
    |> Enum.map(fn {name, value} -> " #{name}=\"#{escape_attribute(value)}\"" end)
    |> Enum.join("")
  end

  defp attribute_attrs(_), do: ""

  defp value_content(%{"@attributes" => _, "@value" => value}), do: value
  defp value_content(%{"@attributes" => _}), do: ""
  defp value_content(value), do: value

  defp escape_content(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_content(value), do: to_string(value)

  defp escape_attribute(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end
end
