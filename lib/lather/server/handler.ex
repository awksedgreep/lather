defmodule Lather.Server.Handler do
  @moduledoc """
  Generic HTTP handler for SOAP server endpoints.

  This module provides SOAP server functionality without requiring Plug.
  It can be used with any HTTP server (Phoenix, Bandit, Cowboy, etc.).

  ## Usage

  In Phoenix controller:

      defmodule MyAppWeb.SOAPController do
        use MyAppWeb, :controller

        def handle_soap(conn, _params) do
          case Lather.Server.Handler.handle_request(conn.method, conn.request_path, conn.req_headers, conn.assigns.raw_body, MyApp.UserService) do
            {:ok, status, headers, body} ->
              conn
              |> put_status(status)
              |> put_headers(headers)
              |> text(body)
            {:error, status, headers, body} ->
              conn
              |> put_status(status)
              |> put_headers(headers)
              |> text(body)
          end
        end
      end

  With any HTTP server:

      body = read_request_body(request)
      headers = get_request_headers(request)

      case Lather.Server.Handler.handle_request("POST", "/soap", headers, body, MyApp.UserService) do
        {:ok, status, response_headers, response_body} ->
          send_response(status, response_headers, response_body)
        {:error, status, response_headers, response_body} ->
          send_response(status, response_headers, response_body)
      end
  """

  require Logger
  alias Lather.Server.{RequestParser, ResponseBuilder, WSDLGenerator}

  @doc """
  Handles a SOAP HTTP request.

  Returns `{:ok, status, headers, body}` or `{:error, status, headers, body}`.

  ## Options

  * `:validate_params` - Enable parameter validation (default: true)
  * `:generate_wsdl` - Enable WSDL generation (default: true)
  * `:base_url` - Base URL for WSDL generation (default: "http://localhost:4000")
  * `:max_body_size` - Maximum request body size in bytes (default: 10MB).
    Bodies exceeding this limit are rejected with HTTP 413.

  Any `GET` serves the WSDL (when `:generate_wsdl` is enabled) and any
  `POST` is treated as a SOAP call, regardless of path — matching
  `Lather.Server.Plug`. Other methods get a 405 fault.
  """
  def handle_request(method, _path, _headers, body, service, opts \\ []) do
    unless function_exported?(service, :__soap_service__, 0) do
      raise ArgumentError,
            "#{service} is not a valid SOAP service module. Did you forget to `use Lather.Server`?"
    end

    config = %{
      service: service,
      validate_params: Keyword.get(opts, :validate_params, true),
      generate_wsdl: Keyword.get(opts, :generate_wsdl, true),
      base_url: Keyword.get(opts, :base_url, "http://localhost:4000"),
      max_body_size: Keyword.get(opts, :max_body_size, 10 * 1024 * 1024)
    }

    case method do
      "GET" when config.generate_wsdl ->
        handle_wsdl_request(config)

      "POST" ->
        handle_soap_request(body, config)

      _ ->
        {:error, 405, [{"content-type", "text/xml"}], fault_xml("Client", "Method not allowed")}
    end
  end

  # Handle WSDL generation requests
  defp handle_wsdl_request(%{service: service, base_url: base_url}) do
    try do
      service_info = service.__soap_service__()
      wsdl_content = WSDLGenerator.generate(service_info, base_url)

      {:ok, 200, [{"content-type", "text/xml"}], wsdl_content}
    rescue
      error ->
        Logger.error("WSDL generation failed: #{inspect(error)}")

        {:error, 500, [{"content-type", "text/xml"}],
         fault_xml("Server", "WSDL generation failed")}
    end
  end

  # Handle SOAP operation requests
  defp handle_soap_request(body, config) do
    body_size = if is_binary(body), do: byte_size(body), else: 0

    if body_size > config.max_body_size do
      {:error, 413, [{"content-type", "text/xml"}], fault_xml("Client", "Request body too large")}
    else
      with {:ok, parsed_request} <- RequestParser.parse(body),
           {:ok, result, operation} <- dispatch_operation(parsed_request, config) do
        # Pass the operation *definition* so ResponseBuilder recognises the
        # "<Op>Response" wrapper format_response/2 already applied (#13).
        response_xml = ResponseBuilder.build_response(result, operation)
        {:ok, 200, [{"content-type", "text/xml"}], response_xml}
      else
        {:error, {:soap_fault, fault}} ->
          fault_xml = ResponseBuilder.build_fault(fault)
          {:error, 500, [{"content-type", "text/xml"}], fault_xml}

        {:error, {:parse_error, reason}} ->
          # `reason` is a string for structural problems and a nested
          # tuple/exception for malformed XML; never interpolate it (#12).
          Logger.warning("SOAP parse error: #{inspect(reason)}")

          {:error, 400, [{"content-type", "text/xml"}],
           fault_xml("Client", parse_error_message(reason))}
      end
    end
  end

  defp parse_error_message(reason) when is_binary(reason), do: "Invalid SOAP request: #{reason}"
  defp parse_error_message(_reason), do: "Invalid SOAP request: malformed XML"

  # Dispatch the operation to the service module
  defp dispatch_operation(request, %{service: service, validate_params: validate?}) do
    operation = service.__soap_operation__(request.operation)

    if operation do
      with {:ok, params} <- validate_operation_params(request.params, operation, validate?),
           {:ok, result} <- call_operation_function(service, operation, params),
           {:ok, formatted} <- Lather.Server.format_response(result, operation) do
        {:ok, formatted, operation}
      end
    else
      {:error,
       {:soap_fault,
        %{
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
        {:error,
         {:soap_fault,
          %{
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
        {:ok, result} ->
          {:ok, result}

        {:soap_fault, fault} ->
          {:error, {:soap_fault, fault}}

        {:error, reason} ->
          {:error,
           {:soap_fault,
            %{
              fault_code: "Server",
              fault_string: to_string(reason)
            }}}

        result ->
          {:ok, result}
      end
    rescue
      UndefinedFunctionError ->
        {:error,
         {:soap_fault,
          %{
            fault_code: "Server",
            fault_string: "Operation function #{function_name}/1 not implemented"
          }}}

      error ->
        Logger.error("Operation #{operation.name} failed: #{inspect(error)}")

        {:error,
         {:soap_fault,
          %{
            fault_code: "Server",
            fault_string: "Internal server error"
          }}}
    end
  end

  # Fault XML for transport-level errors; goes through ResponseBuilder so
  # the fault string is escaped.
  defp fault_xml(fault_code, fault_string) do
    ResponseBuilder.build_fault(%{fault_code: fault_code, fault_string: fault_string})
  end
end
