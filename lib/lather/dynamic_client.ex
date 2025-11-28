defmodule Lather.DynamicClient do
  @moduledoc """
  Dynamic SOAP client that can work with any SOAP service.

  This client uses WSDL analysis to understand service operations and
  dynamically builds SOAP requests without requiring service-specific code.
  """

  alias Lather.Client
  alias Lather.Wsdl.Analyzer
  alias Lather.Operation.Builder
  alias Lather.Error

  defstruct [:base_client, :service_info, :default_options]

  @type t :: %__MODULE__{
          base_client: Client.t(),
          service_info: map(),
          default_options: keyword()
        }

  @doc """
  Creates a new dynamic client from a WSDL URL or file path.

  ## Parameters

    * `wsdl_source` - URL or file path to the WSDL
    * `options` - Client configuration options

  ## Options

    * `:service_name` - Specific service name if WSDL contains multiple services
    * `:endpoint_override` - Override the endpoint URL from WSDL
    * `:default_headers` - Default headers to include in all requests
    * `:authentication` - Authentication configuration
    * `:timeout` - Default request timeout
    * `:soap_version` - SOAP protocol version (`:v1_1` or `:v1_2`, auto-detected if not specified)

  ## Examples

      {:ok, client} = Lather.DynamicClient.new("http://example.com/service?wsdl")

      {:ok, client} = Lather.DynamicClient.new(
        "http://example.com/service?wsdl",
        authentication: {:basic, "user", "pass"},
        timeout: 60_000
      )
  """
  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(wsdl_source, options \\ []) do
    with {:ok, service_info} <- Analyzer.load_and_analyze(wsdl_source, options),
         {:ok, base_client} <-
           create_base_client(service_info, options ++ [wsdl_source: wsdl_source]) do
      # Determine SOAP version - use explicit option or detect from WSDL
      soap_version =
        Keyword.get(options, :soap_version) ||
          Map.get(service_info, :soap_version, :v1_1)

      # Add soap_version to default options
      enhanced_options = Keyword.put(options, :soap_version, soap_version)

      dynamic_client = %__MODULE__{
        base_client: base_client,
        service_info: service_info,
        default_options: enhanced_options
      }

      {:ok, dynamic_client}
    end
  end

  @doc """
  Lists all available operations for the service.

  ## Examples

      operations = Lather.DynamicClient.list_operations(client)
      # [
      #   %{name: "GetUser", required_parameters: ["userId"], ...},
      #   %{name: "CreateUser", required_parameters: ["userData"], ...}
      # ]
  """
  @spec list_operations(t()) :: [map()]
  def list_operations(%__MODULE__{service_info: service_info}) do
    Enum.map(service_info.operations, &Builder.get_operation_metadata/1)
  end

  @doc """
  Gets detailed information about a specific operation.

  ## Parameters

    * `client` - The dynamic client
    * `operation_name` - Name of the operation to inspect

  ## Examples

      {:ok, operation_info} = Lather.DynamicClient.get_operation_info(client, "GetUser")
      # %{
      #   name: "GetUser",
      #   required_parameters: ["userId"],
      #   optional_parameters: [],
      #   return_type: "User",
      #   soap_action: "http://example.com/GetUser"
      # }
  """
  @spec get_operation_info(t(), String.t()) :: {:ok, map()} | {:error, :operation_not_found}
  def get_operation_info(%__MODULE__{service_info: service_info}, operation_name) do
    case Enum.find(service_info.operations, fn op -> op.name == operation_name end) do
      nil ->
        error =
          Error.validation_error(operation_name, :operation_not_found, %{
            message: "Operation '#{operation_name}' not found in WSDL",
            available_operations: Enum.map(service_info.operations, & &1.name)
          })

        {:error, error}

      operation ->
        {:ok, Builder.get_operation_metadata(operation)}
    end
  end

  @doc """
  Calls a SOAP operation dynamically.

  ## Parameters

    * `client` - The dynamic client
    * `operation_name` - Name of the operation to call
    * `parameters` - Map of parameters for the operation
    * `options` - Additional call options

  ## Options

    * `:headers` - Additional SOAP headers
    * `:timeout` - Request timeout override
    * `:validate` - Whether to validate parameters (default: true)

  ## Examples

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "GetUser",
        %{"userId" => "12345"}
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "CreateUser",
        %{"userData" => %{"name" => "John", "email" => "john@example.com"}},
        headers: [%{"Authentication" => "Bearer token123"}]
      )
  """
  @spec call(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def call(%__MODULE__{} = dynamic_client, operation_name, parameters, options \\ []) do
    %{service_info: service_info, base_client: base_client, default_options: default_opts} =
      dynamic_client

    with {:ok, operation_info} <- find_operation(service_info, operation_name),
         :ok <- maybe_validate_parameters(operation_info, parameters, options),
         {:ok, soap_envelope} <-
           build_request(operation_info, parameters, service_info, default_opts ++ options),
         {:ok, response} <-
           send_request(base_client, soap_envelope, operation_info, default_opts, options),
         {:ok, parsed_response} <- parse_response(operation_info, response, options) do
      {:ok, parsed_response}
    end
  end

  @doc """
  Validates parameters for a specific operation without making the call.

  ## Parameters

    * `client` - The dynamic client
    * `operation_name` - Name of the operation
    * `parameters` - Parameters to validate

  ## Examples

      :ok = Lather.DynamicClient.validate_parameters(client, "GetUser", %{"userId" => "123"})

      {:error, {:missing_required_parameter, "userId"}} =
        Lather.DynamicClient.validate_parameters(client, "GetUser", %{})
  """
  @spec validate_parameters(t(), String.t(), map()) :: :ok | {:error, term()}
  def validate_parameters(%__MODULE__{service_info: service_info}, operation_name, parameters) do
    with {:ok, operation_info} <- find_operation(service_info, operation_name) do
      Builder.validate_parameters(operation_info, parameters)
    end
  end

  @doc """
  Generates a report of the service capabilities.

  ## Examples

      report = Lather.DynamicClient.generate_service_report(client)
      IO.puts(report)
  """
  @spec generate_service_report(t()) :: String.t()
  def generate_service_report(%__MODULE__{service_info: service_info}) do
    Analyzer.generate_report(service_info)
  end

  @doc """
  Gets service information including endpoints, namespaces, and types.

  ## Examples

      service_info = Lather.DynamicClient.get_service_info(client)
      # %{
      #   service_name: "MyService",
      #   target_namespace: "http://example.com/service",
      #   endpoints: [...],
      #   operations: [...],
      #   types: [...]
      # }
  """
  @spec get_service_info(t()) :: map()
  def get_service_info(%__MODULE__{service_info: service_info}) do
    service_info
  end

  # Private helper functions

  defp create_base_client(service_info, options) do
    endpoint = determine_endpoint(service_info, options)
    _service_name = Keyword.get(options, :service_name, service_info.service_name)

    base_client = Client.new(endpoint, options)

    # Apply authentication if specified
    client_with_auth = apply_authentication(base_client, options)

    {:ok, client_with_auth}
  end

  defp determine_endpoint(service_info, options) do
    case Keyword.get(options, :endpoint_override) do
      nil ->
        # Use first available endpoint from WSDL
        extracted_endpoint =
          case service_info.endpoints do
            [first_endpoint | _] -> first_endpoint.address.location
            [] -> ""
          end

        # Check if extracted endpoint is localhost or invalid, use WSDL source as fallback
        if is_localhost_or_invalid?(extracted_endpoint) do
          derive_endpoint_from_wsdl_source(options)
        else
          extracted_endpoint
        end

      override_endpoint ->
        override_endpoint
    end
  end

  defp is_localhost_or_invalid?(endpoint) do
    endpoint == "" or
      String.contains?(endpoint, "localhost") or
      String.contains?(endpoint, "127.0.0.1") or
      String.contains?(endpoint, "http://localhost")
  end

  defp derive_endpoint_from_wsdl_source(options) do
    case Keyword.get(options, :wsdl_source) do
      nil ->
        ""

      wsdl_url when is_binary(wsdl_url) ->
        # Remove ?wsdl or ?WSDL from the URL to get the service endpoint
        wsdl_url
        |> String.replace(~r/\?wsdl$/i, "")

      _ ->
        ""
    end
  end

  defp apply_authentication(client, options) do
    case Keyword.get(options, :authentication) do
      {:basic, username, password} ->
        # Add basic auth header to default headers
        auth_header = {"Authorization", "Basic " <> Base.encode64("#{username}:#{password}")}
        %{client | headers: [auth_header | client.headers]}

      {:wssecurity, username, password} ->
        # WS-Security will be handled in SOAP headers during request building
        Map.put(client, :ws_security, {username, password})

      _ ->
        client
    end
  end

  defp find_operation(service_info, operation_name) do
    case Enum.find(service_info.operations, fn op -> op.name == operation_name end) do
      nil ->
        error =
          Error.validation_error(operation_name, :operation_not_found, %{
            message: "Operation '#{operation_name}' not found in WSDL",
            available_operations: Enum.map(service_info.operations, & &1.name)
          })

        {:error, error}

      operation ->
        {:ok, operation}
    end
  end

  defp maybe_validate_parameters(operation_info, parameters, options) do
    should_validate = Keyword.get(options, :validate, true)

    if should_validate do
      Builder.validate_parameters(operation_info, parameters)
    else
      :ok
    end
  end

  defp build_request(operation_info, parameters, service_info, options) do
    headers = Keyword.get(options, :headers, [])
    soap_version = Keyword.get(options, :soap_version, :v1_1)

    request_options = [
      namespace: service_info.target_namespace,
      headers: headers,
      style: get_operation_style(operation_info),
      use: get_operation_use(operation_info),
      version: soap_version
    ]

    Builder.build_request(operation_info, parameters, request_options)
  end

  defp send_request(base_client, soap_envelope, operation_info, default_opts, call_opts) do
    alias Lather.Http.Transport

    alias Lather.Xml.Parser

    soap_action = operation_info.soap_action || ""
    timeout = Keyword.get(call_opts, :timeout) || Keyword.get(default_opts, :timeout, 30_000)

    # Get SOAP version from default options
    soap_version = Keyword.get(default_opts, :soap_version, :v1_1)

    # Remove :headers from call_opts since those are SOAP headers (already consumed by build_request),
    # not HTTP headers. Transport.build_headers expects HTTP headers as tuples {name, value}.
    http_call_opts = Keyword.delete(call_opts, :headers)

    # Combine client options with call options, pass soap_action and version
    transport_options =
      base_client.options ++
        http_call_opts ++
        [
          timeout: timeout,
          soap_action: soap_action,
          soap_version: soap_version
        ]

    # Send the pre-built envelope directly
    case Transport.post(base_client.endpoint, soap_envelope, transport_options) do
      {:ok, response} ->
        # Parse XML from successful response
        case Parser.parse(response.body) do
          {:ok, parsed_xml} ->
            {:ok, parsed_xml}

          {:error, parse_error} ->
            {:error,
             %{
               type: :xml_parse_error,
               message: "Failed to parse response XML",
               details: parse_error
             }}
        end

      {:error, %{status: 500, type: :http_error, body: body}} when is_binary(body) ->
        # HTTP 500 might contain a SOAP fault - try to parse it
        case Parser.parse(body) do
          {:ok, parsed_response} ->
            # Check if this is a SOAP fault
            case extract_soap_fault(parsed_response) do
              {:ok, fault} -> {:error, {:soap_fault, fault}}
              :not_fault -> {:ok, parsed_response}
            end

          {:error, _parse_error} ->
            # If we can't parse the response, return the original HTTP error
            {:error, %{status: 500, type: :http_error, body: body}}
        end

      {:error, other_error} ->
        {:error, other_error}
    end
  end

  defp extract_soap_fault(parsed_response) do
    fault =
      get_in(parsed_response, ["Envelope", "Body", "Fault"]) ||
        get_in(parsed_response, ["soap:Envelope", "soap:Body", "soap:Fault"]) ||
        get_in(parsed_response, ["SOAP-ENV:Envelope", "SOAP-ENV:Body", "SOAP-ENV:Fault"])

    if fault do
      fault_info = %{
        fault_code: extract_text_content(fault["faultcode"] || fault["soap:faultcode"] || ""),
        fault_string:
          extract_text_content(fault["faultstring"] || fault["soap:faultstring"] || ""),
        fault_actor: extract_text_content(fault["faultactor"] || fault["soap:faultactor"] || ""),
        detail: extract_text_content(fault["detail"] || fault["soap:detail"] || "")
      }

      {:ok, fault_info}
    else
      :not_fault
    end
  end

  defp extract_text_content(value) when is_map(value) do
    Map.get(value, "#text", "")
  end

  defp extract_text_content(value) when is_binary(value) do
    value
  end

  defp extract_text_content(_) do
    ""
  end

  defp parse_response(operation_info, response, _options) do
    style = get_operation_style(operation_info)
    Builder.parse_response(operation_info, response, style: style)
  end

  defp get_operation_style(operation_info) do
    Map.get(operation_info, :style, :document)
  end

  defp get_operation_use(operation_info) do
    Map.get(operation_info.input, :use, :literal)
  end
end
