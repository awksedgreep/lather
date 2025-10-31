defmodule Lather.Server.Plug do
  @moduledoc """
  Plug implementation for SOAP server endpoints.

  Handles incoming SOAP requests, routes them to appropriate operations,
  and formats responses according to SOAP standards.

  ## Usage

  In Phoenix router:

      scope "/soap" do
        pipe_through :api
        post "/users", Lather.Server.Plug, service: MyApp.UserService
      end

  As standalone Plug:

      plug Lather.Server.Plug, service: MyApp.UserService

  ## Options

  - `:service` - The SOAP service module (required)
  - `:path` - Base path for WSDL generation (default: "/")
  - `:auth_handler` - Custom authentication handler
  - `:validate_params` - Enable parameter validation (default: true)
  - `:generate_wsdl` - Enable WSDL generation endpoint (default: true)

  Note: This module requires the `:plug` dependency to be installed.
  Add `{:plug, "~> 1.14"}` to your mix.exs dependencies.
  """

  # Only define the Plug behavior if Plug is available
  if Code.ensure_loaded?(Plug) do
    import Plug.Conn
    require Logger

    alias Lather.Server.{RequestParser, ResponseBuilder, WSDLGenerator}

    @behaviour Plug

  @impl Plug
  def init(opts) do
    service = Keyword.fetch!(opts, :service)

    unless function_exported?(service, :__soap_service__, 0) do
      raise ArgumentError, "#{service} is not a valid SOAP service module. Did you forget to `use Lather.Server`?"
    end

    %{
      service: service,
      path: Keyword.get(opts, :path, "/"),
      auth_handler: Keyword.get(opts, :auth_handler),
      validate_params: Keyword.get(opts, :validate_params, true),
      generate_wsdl: Keyword.get(opts, :generate_wsdl, true)
    }
  end

  @impl Plug
  def call(%Plug.Conn{method: "GET"} = conn, %{generate_wsdl: true} = config) do
    case Map.get(conn.query_params, "wsdl") do
      val when val in [nil, "", "1", "true"] ->
        handle_wsdl_request(conn, config)
      _ ->
        handle_soap_request(conn, config)
    end
  end

  def call(%Plug.Conn{method: "POST"} = conn, config) do
    handle_soap_request(conn, config)
  end

  def call(conn, _config) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(405, soap_fault_xml("Client", "Method not allowed"))
  end

  # Handle WSDL generation requests
  defp handle_wsdl_request(conn, %{service: service, path: path}) do
    try do
      service_info = service.__soap_service__()
      wsdl_content = WSDLGenerator.generate(service_info, base_url(conn, path))

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(200, wsdl_content)
    rescue
      error ->
        Logger.error("WSDL generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(500, soap_fault_xml("Server", "WSDL generation failed"))
    end
  end

  # Handle SOAP operation requests
  defp handle_soap_request(conn, config) do
    with {:ok, body} <- read_full_body(conn),
         {:ok, parsed_request} <- RequestParser.parse(body),
         {:ok, authenticated_conn} <- authenticate(conn, config),
         {:ok, result} <- dispatch_operation(parsed_request, config) do

      response_xml = ResponseBuilder.build_response(result, parsed_request.operation)

      authenticated_conn
      |> put_resp_content_type("text/xml")
      |> send_resp(200, response_xml)
    else
      {:error, :authentication_failed} ->
        conn
        |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
        |> put_resp_content_type("text/xml")
        |> send_resp(401, soap_fault_xml("Client", "Authentication required"))

      {:error, {:soap_fault, fault}} ->
        fault_xml = ResponseBuilder.build_fault(fault)

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(500, fault_xml)

      {:error, {:parse_error, reason}} ->
        Logger.warning("SOAP parse error: #{reason}")

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(400, soap_fault_xml("Client", "Invalid SOAP request: #{reason}"))

      {:error, reason} ->
        Logger.error("SOAP request failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(500, soap_fault_xml("Server", "Internal server error"))
    end
  end

  # Read the complete request body
  defp read_full_body(conn, body \\ "") do
    case Plug.Conn.read_body(conn) do
      {:ok, chunk, _conn} -> {:ok, body <> chunk}
      {:more, chunk, conn} -> read_full_body(conn, body <> chunk)
      {:error, reason} -> {:error, reason}
    end
  end

  # Authenticate the request if auth is configured
  defp authenticate(conn, %{auth_handler: nil}), do: {:ok, conn}
  defp authenticate(conn, %{auth_handler: handler}) do
    case handler.authenticate(conn) do
      {:ok, conn} -> {:ok, conn}
      {:error, _reason} -> {:error, :authentication_failed}
    end
  end
  defp authenticate(conn, _config), do: {:ok, conn}

  # Dispatch the operation to the service module
  defp dispatch_operation(request, %{service: service, validate_params: validate?}) do
    operation = service.__soap_operation__(request.operation)

    if operation do
      with {:ok, params} <- validate_operation_params(request.params, operation, validate?),
           {:ok, result} <- call_operation_function(service, operation, params) do
        Lather.Server.format_response(result, operation)
      end
    else
      {:error, {:soap_fault, %{
        fault_code: "Client",
        fault_string: "Unknown operation: #{request.operation}",
        detail: %{available_operations: Enum.map(service.__soap_operations__(), & &1.name)}
      }}}
    end
  end

  # Validate operation parameters if enabled
  defp validate_operation_params(params, operation, true) do
    with :ok <- Lather.Server.validate_required_params(params, operation),
         :ok <- Lather.Server.validate_param_types(params, operation) do
      {:ok, params}
    else
      {:error, reason} ->
        {:error, {:soap_fault, %{
          fault_code: "Client",
          fault_string: reason
        }}}
    end
  end
  defp validate_operation_params(params, _operation, false), do: {:ok, params}

  # Call the actual operation function
  defp call_operation_function(service, operation, params) do
    function_name = String.to_atom(operation.function_name)

    try do
      case apply(service, function_name, [params]) do
        {:ok, result} -> {:ok, result}
        {:soap_fault, fault} -> {:error, {:soap_fault, fault}}
        {:error, reason} -> {:error, {:soap_fault, %{
          fault_code: "Server",
          fault_string: to_string(reason)
        }}}
        result -> {:ok, result}
      end
    rescue
      UndefinedFunctionError ->
        {:error, {:soap_fault, %{
          fault_code: "Server",
          fault_string: "Operation function #{function_name}/1 not implemented"
        }}}

      error ->
        Logger.error("Operation #{operation.name} failed: #{inspect(error)}")
        {:error, {:soap_fault, %{
          fault_code: "Server",
          fault_string: "Internal server error"
        }}}
    end
  end

  # Build base URL for WSDL generation
  defp base_url(%Plug.Conn{} = conn, path) do
    scheme = conn.scheme |> to_string()
    host = conn.host
    port = case {scheme, conn.port} do
      {"http", 80} -> ""
      {"https", 443} -> ""
      {_, port} -> ":#{port}"
    end

    "#{scheme}://#{host}#{port}#{path}"
  end

  # Generate a simple SOAP fault XML
  defp soap_fault_xml(fault_code, fault_string) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <soap:Fault>
          <faultcode>#{fault_code}</faultcode>
          <faultstring>#{fault_string}</faultstring>
        </soap:Fault>
      </soap:Body>
    </soap:Envelope>
    """
  end

  else
    @moduledoc """
    Plug implementation for SOAP server endpoints.

    This module requires the `:plug` dependency to be installed.
    Add `{:plug, "~> 1.14"}` to your mix.exs dependencies.
    """

    def init(_opts) do
      raise "Plug dependency not available. Add {:plug, \"~> 1.14\"} to your mix.exs dependencies."
    end

    def call(_conn, _opts) do
      raise "Plug dependency not available. Add {:plug, \"~> 1.14\"} to your mix.exs dependencies."
    end
  end
end
