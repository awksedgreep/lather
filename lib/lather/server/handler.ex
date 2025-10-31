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
  """
  def handle_request(method, path, headers, body, service, opts \\ []) do
    unless function_exported?(service, :__soap_service__, 0) do
      raise ArgumentError, "#{service} is not a valid SOAP service module. Did you forget to `use Lather.Server`?"
    end

    config = %{
      service: service,
      validate_params: Keyword.get(opts, :validate_params, true),
      generate_wsdl: Keyword.get(opts, :generate_wsdl, true),
      base_url: Keyword.get(opts, :base_url, "http://localhost:4000")
    }

    case {method, is_wsdl_request?(path, headers)} do
      {"GET", true} when config.generate_wsdl ->
        handle_wsdl_request(config)

      {"POST", false} ->
        handle_soap_request(body, config)

      _ ->
        {:error, 405, [{"content-type", "text/xml"}],
         soap_fault_xml("Client", "Method not allowed")}
    end
  end

  # Check if this is a WSDL request
  defp is_wsdl_request?(path, _headers) do
    String.contains?(path, "wsdl") or String.contains?(path, "WSDL")
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
         soap_fault_xml("Server", "WSDL generation failed")}
    end
  end

  # Handle SOAP operation requests
  defp handle_soap_request(body, config) do
    with {:ok, parsed_request} <- RequestParser.parse(body),
         {:ok, result} <- dispatch_operation(parsed_request, config) do

      response_xml = ResponseBuilder.build_response(result, parsed_request.operation)
      {:ok, 200, [{"content-type", "text/xml"}], response_xml}
    else
      {:error, {:soap_fault, fault}} ->
        fault_xml = ResponseBuilder.build_fault(fault)
        {:error, 500, [{"content-type", "text/xml"}], fault_xml}

      {:error, {:parse_error, reason}} ->
        Logger.warning("SOAP parse error: #{reason}")
        {:error, 400, [{"content-type", "text/xml"}],
         soap_fault_xml("Client", "Invalid SOAP request: #{reason}")}

      {:error, reason} ->
        Logger.error("SOAP request failed: #{inspect(reason)}")
        {:error, 500, [{"content-type", "text/xml"}],
         soap_fault_xml("Server", "Internal server error")}
    end
  end

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
end
