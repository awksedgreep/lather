defmodule Lather.Server.EnhancedPlug do
  @moduledoc """
  Enhanced Plug implementation for SOAP server endpoints with web form interface.

  Provides comprehensive SOAP service endpoints with interactive web forms,
  multi-protocol support, and complete API documentation similar to .NET Web Services.

  ## Features

  - Interactive web forms for testing operations
  - SOAP 1.1, SOAP 1.2, and JSON protocol support
  - Enhanced WSDL generation with multi-protocol bindings
  - Service overview with complete operation documentation
  - Responsive web interface for operation testing

  ## Usage

  In Phoenix router:

      scope "/soap" do
        pipe_through :api
        match :*, "/users", Lather.Server.EnhancedPlug, service: MyApp.UserService
        match :*, "/users/*path", Lather.Server.EnhancedPlug, service: MyApp.UserService
      end

  As standalone Plug:

      plug Lather.Server.EnhancedPlug, service: MyApp.UserService

  ## URL Patterns

  - `GET /service` - Service overview with operations list
  - `GET /service?wsdl` - Standard WSDL download
  - `GET /service?wsdl&enhanced=true` - Multi-protocol WSDL
  - `GET /service?op=OperationName` - Interactive operation form
  - `POST /service` - SOAP 1.1 endpoint
  - `POST /service/v1.2` - SOAP 1.2 endpoint
  - `POST /service/api` - JSON/REST endpoint

  ## Options

  - `:service` - The SOAP service module (required)
  - `:base_path` - Base path for service (default: "/soap")
  - `:enable_forms` - Enable web form interface (default: true)
  - `:enable_json` - Enable JSON endpoints (default: true)
  - `:auth_handler` - Custom authentication handler
  - `:validate_params` - Enable parameter validation (default: true)
  """

  # Check if Jason is available for JSON support
  @jason_available Code.ensure_loaded?(Jason)

  import Plug.Conn
  require Logger

  alias Lather.Server.{
    RequestParser,
    ResponseBuilder,
    WSDLGenerator,
    EnhancedWSDLGenerator,
    FormGenerator
  }

  @behaviour Plug

  @impl Plug
  def init(opts) do
    service = Keyword.fetch!(opts, :service)

    unless function_exported?(service, :__soap_service__, 0) do
      raise ArgumentError,
            "#{service} is not a valid SOAP service module. Did you forget to `use Lather.Server`?"
    end

    %{
      service: service,
      base_path: Keyword.get(opts, :base_path, "/soap"),
      enable_forms: Keyword.get(opts, :enable_forms, true),
      enable_json: Keyword.get(opts, :enable_json, true),
      auth_handler: Keyword.get(opts, :auth_handler),
      validate_params: Keyword.get(opts, :validate_params, true)
    }
  end

  @impl Plug
  def call(conn, config) do
    # Ensure query params are fetched for URL pattern detection
    conn = Plug.Conn.fetch_query_params(conn)

    case {conn.method, get_request_type(conn)} do
      # WSDL requests
      {"GET", :wsdl} ->
        handle_wsdl_request(conn, config)

      # Operation form requests
      {"GET", {:operation_form, operation_name}} ->
        handle_operation_form_request(conn, config, operation_name)

      # Service overview
      {"GET", :service_overview} ->
        handle_service_overview_request(conn, config)

      # SOAP 1.1 requests (default POST)
      {"POST", :soap_1_1} ->
        handle_soap_request(conn, config, :v1_1)

      # SOAP 1.2 requests
      {"POST", :soap_1_2} ->
        handle_soap_request(conn, config, :v1_2)

      # JSON/REST requests
      {"POST", :json} when config.enable_json ->
        handle_json_request(conn, config)

      # Unsupported methods
      _ ->
        handle_unsupported_request(conn)
    end
  rescue
    error ->
      Logger.error("Enhanced SOAP server error: #{inspect(error)}")

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, soap_fault_xml("Server", "Internal server error"))
  end

  # Determine request type from URL and query parameters
  defp get_request_type(conn) do
    cond do
      # WSDL request
      Map.has_key?(conn.query_params, "wsdl") ->
        :wsdl

      # Operation form request
      Map.has_key?(conn.query_params, "op") ->
        {:operation_form, conn.query_params["op"]}

      # Check path for protocol version
      String.contains?(conn.request_path, "/v1.2") ->
        :soap_1_2

      String.contains?(conn.request_path, "/api") ->
        :json

      # Default cases
      conn.method == "GET" ->
        :service_overview

      conn.method == "POST" ->
        :soap_1_1

      true ->
        :unsupported
    end
  end

  # Handle WSDL generation requests
  defp handle_wsdl_request(conn, %{service: service} = config) do
    try do
      service_info = service.__soap_service__()
      base_url = get_base_url(conn, config)

      wsdl_content =
        if Map.has_key?(conn.query_params, "enhanced") do
          # Generate enhanced multi-protocol WSDL
          EnhancedWSDLGenerator.generate(service_info, base_url,
            protocols: [:soap_1_1, :soap_1_2, :http],
            include_json: config.enable_json
          )
        else
          # Generate standard WSDL
          WSDLGenerator.generate(service_info, base_url)
        end

      conn
      |> put_resp_content_type("text/xml; charset=utf-8")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"#{service_info.name}.wsdl\""
      )
      |> send_resp(200, wsdl_content)
    rescue
      error ->
        Logger.error("WSDL generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(500, soap_fault_xml("Server", "WSDL generation failed"))
    end
  end

  # Handle operation form requests
  defp handle_operation_form_request(
         conn,
         %{service: service, enable_forms: true} = config,
         operation_name
       ) do
    try do
      service_info = service.__soap_service__()
      base_url = get_base_url(conn, config)

      case find_operation(service_info, operation_name) do
        nil ->
          conn
          |> put_resp_content_type("text/html")
          |> send_resp(404, generate_error_page("Operation '#{operation_name}' not found"))

        operation ->
          html_content =
            FormGenerator.generate_operation_page(service_info, operation, base_url)

          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> send_resp(200, html_content)
      end
    rescue
      error ->
        Logger.error("Operation form generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(500, generate_error_page("Form generation failed"))
    end
  end

  defp handle_operation_form_request(conn, _config, _operation_name) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, generate_error_page("Form interface disabled"))
  end

  # Handle service overview requests
  defp handle_service_overview_request(conn, %{service: service, enable_forms: true} = config) do
    try do
      service_info = service.__soap_service__()
      base_url = get_base_url(conn, config)

      html_content = FormGenerator.generate_service_overview(service_info, base_url)

      conn
      |> put_resp_content_type("text/html; charset=utf-8")
      |> send_resp(200, html_content)
    rescue
      error ->
        Logger.error("Service overview generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(500, generate_error_page("Service overview generation failed"))
    end
  end

  defp handle_service_overview_request(conn, _config) do
    # If forms are disabled, redirect to WSDL
    redirect_to_wsdl(conn)
  end

  # Handle SOAP requests (1.1 and 1.2)
  defp handle_soap_request(conn, config, soap_version) do
    with {:ok, body} <- read_full_body(conn),
         {:ok, parsed_request} <- RequestParser.parse(body),
         {:ok, operation_name} <- extract_operation_name(parsed_request),
         {:ok, operation_info} <- get_operation_info(config.service, operation_name),
         {:ok, validated_params} <-
           validate_and_extract_params(parsed_request, operation_info, config),
         {:ok, result} <- call_operation(config.service, operation_name, validated_params) do
      # Format and send SOAP response
      response_xml = ResponseBuilder.build_response(result, operation_info)

      content_type =
        case soap_version do
          :v1_1 -> "text/xml; charset=utf-8"
          :v1_2 -> "application/soap+xml; charset=utf-8"
        end

      conn
      |> put_resp_content_type(content_type)
      |> send_resp(200, response_xml)
    else
      {:error, {:soap_fault, fault}} ->
        fault_xml = ResponseBuilder.build_fault(fault)

        conn
        |> put_resp_content_type("text/xml; charset=utf-8")
        |> send_resp(500, fault_xml)

      {:error, reason} ->
        Logger.warning("SOAP request failed: #{inspect(reason)}")

        fault_xml = soap_fault_xml("Client", "Invalid SOAP request")

        conn
        |> put_resp_content_type("text/xml; charset=utf-8")
        |> send_resp(400, fault_xml)
    end
  end

  # Handle JSON/REST requests
  defp handle_json_request(conn, config) do
    # Extract operation from path or query parameters
    operation_name = extract_json_operation_name(conn)

    with {:ok, body} <- read_full_body(conn),
         {:ok, json_params} <- decode_json_body(body),
         {:ok, operation_info} <- get_operation_info(config.service, operation_name),
         {:ok, validated_params} <- validate_json_params(json_params, operation_info, config),
         {:ok, result} <- call_operation(config.service, operation_name, validated_params) do
      # Format JSON response
      json_response = format_json_response(result, operation_info)

      conn
      |> put_resp_content_type("application/json; charset=utf-8")
      |> send_resp(200, encode_json(json_response))
    else
      {:error, {:soap_fault, fault}} ->
        error_response = %{
          error: %{
            code: fault.fault_code || "ServerError",
            message: fault.fault_string || "Operation failed",
            detail: fault.detail
          }
        }

        conn
        |> put_resp_content_type("application/json; charset=utf-8")
        |> send_resp(500, encode_json(error_response))

      {:error, reason} ->
        Logger.warning("JSON request failed: #{inspect(reason)}")

        error_response = %{
          error: %{
            code: "InvalidRequest",
            message: "Invalid JSON request",
            detail: inspect(reason)
          }
        }

        conn
        |> put_resp_content_type("application/json; charset=utf-8")
        |> send_resp(400, encode_json(error_response))
    end
  end

  # Handle unsupported requests
  defp handle_unsupported_request(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(405, generate_error_page("Method not allowed"))
  end

  # Helper functions

  defp get_base_url(conn, config) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = conn.host
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{scheme}://#{host}#{port}#{config.base_path}/"
  end

  defp find_operation(service_info, operation_name) do
    Enum.find(service_info.operations, &(&1.name == operation_name))
  end

  defp read_full_body(conn, body \\ "") do
    case Plug.Conn.read_body(conn) do
      {:ok, chunk, _conn} -> {:ok, body <> chunk}
      {:more, chunk, conn} -> read_full_body(conn, body <> chunk)
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_operation_name(parsed_request) do
    # Implementation depends on RequestParser format
    # This is a simplified version
    case get_in(parsed_request, ["soap:Envelope", "soap:Body"]) do
      body when is_map(body) ->
        operation_key =
          body
          |> Map.keys()
          |> Enum.find(&(not String.starts_with?(&1, "soap:")))

        if operation_key do
          {:ok, operation_key}
        else
          {:error, :operation_not_found}
        end

      _ ->
        {:error, :invalid_soap_body}
    end
  end

  defp extract_json_operation_name(conn) do
    # Extract from path like /api/getUserInfo or from query params
    case String.split(conn.request_path, "/") do
      segments when segments != [] ->
        segments |> List.last() |> String.replace(~r/[^a-zA-Z0-9]/, "")

      _ ->
        "UnknownOperation"
    end
  end

  defp get_operation_info(service_module, operation_name) do
    case service_module.__soap_operation__(operation_name) do
      nil ->
        {:error,
         {:soap_fault,
          %{fault_code: "Client", fault_string: "Operation '#{operation_name}' not found"}}}

      operation_info ->
        {:ok, operation_info}
    end
  end

  defp validate_and_extract_params(parsed_request, operation_info, config) do
    # Extract parameters from SOAP body
    case extract_soap_parameters(parsed_request) do
      {:ok, params} ->
        if config.validate_params do
          validate_operation_params(params, operation_info)
        else
          {:ok, params}
        end

      error ->
        error
    end
  end

  defp extract_soap_parameters(parsed_request) do
    # Simplified parameter extraction
    case get_in(parsed_request, ["soap:Envelope", "soap:Body"]) do
      body when is_map(body) ->
        operation_key =
          body
          |> Map.keys()
          |> Enum.find(&(not String.starts_with?(&1, "soap:")))

        if operation_key do
          params = get_in(body, [operation_key])
          {:ok, params || %{}}
        else
          {:ok, %{}}
        end

      _ ->
        {:error, :invalid_soap_body}
    end
  end

  defp validate_operation_params(params, operation_info) do
    # Use the service module's validation if available
    case Lather.Server.validate_required_params(params, operation_info) do
      :ok -> {:ok, params}
      {:error, reason} -> {:error, {:soap_fault, %{fault_code: "Client", fault_string: reason}}}
    end
  end

  # Decode JSON body
  defp decode_json_body(body) do
    case decode_json(body) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  # JSON encoding with graceful fallback
  defp encode_json(data) do
    if @jason_available do
      Jason.encode!(data)
    else
      # Fallback to basic JSON-like string representation
      inspect(data, pretty: true)
    end
  end

  # JSON decoding with graceful fallback
  defp decode_json(body) do
    if @jason_available do
      Jason.decode(body)
    else
      {:error, :jason_not_available}
    end
  end

  defp validate_json_params(params, operation_info, config) do
    if config.validate_params do
      validate_operation_params(params, operation_info)
    else
      {:ok, params}
    end
  end

  defp call_operation(service_module, operation_name, params) do
    function_name = String.to_atom(Macro.underscore(operation_name))

    if function_exported?(service_module, function_name, 1) do
      try do
        result = apply(service_module, function_name, [params])
        {:ok, result}
      rescue
        error ->
          {:error,
           {:soap_fault,
            %{fault_code: "Server", fault_string: "Operation failed: #{inspect(error)}"}}}
      end
    else
      {:error,
       {:soap_fault,
        %{fault_code: "Client", fault_string: "Operation '#{operation_name}' not implemented"}}}
    end
  end

  defp format_json_response(result, _operation_info) do
    case result do
      {:ok, data} -> %{success: true, data: data}
      {:error, reason} -> %{success: false, error: reason}
      data -> %{success: true, data: data}
    end
  end

  defp soap_fault_xml(fault_code, fault_string) do
    """
    <?xml version="1.0" encoding="utf-8"?>
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

  defp generate_error_page(message) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Error</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 50px; }
            .error { background: #ffebee; border: 1px solid #f44336; padding: 20px; border-radius: 4px; }
        </style>
    </head>
    <body>
        <div class="error">
            <h2>Error</h2>
            <p>#{message}</p>
            <p><a href="?wsdl">View WSDL</a></p>
        </div>
    </body>
    </html>
    """
  end

  defp redirect_to_wsdl(conn) do
    conn
    |> put_resp_header("location", "?wsdl")
    |> send_resp(302, "")
  end
end
