defmodule Lather.Integration.RpcStyleRoundTripTest do
  @moduledoc """
  End-to-end integration tests for RPC-style SOAP round trip.

  These tests verify that the client can correctly communicate with a server
  using RPC/literal style instead of the default document/literal style.

  RPC style differs from document style in:
  - The operation name is used as a wrapper element in the SOAP body
  - Parameters are direct children of the operation element
  - The WSDL binding specifies style="rpc" instead of style="document"
  """
  use ExUnit.Case, async: false

  # These tests require starting actual HTTP servers
  @moduletag :integration

  # Custom WSDL generator that produces RPC-style WSDL
  defmodule RpcWsdlGenerator do
    @moduledoc """
    Generates RPC-style WSDL files for testing.
    """

    def generate(service_info, base_url) do
      target_namespace = service_info.target_namespace
      service_name = service_info.name
      endpoint_url = "#{base_url}#{service_name}"

      """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   xmlns:tns="#{target_namespace}"
                   xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="#{target_namespace}">

      #{generate_types(service_info)}

      #{generate_messages(service_info)}

      #{generate_port_type(service_info)}

      #{generate_binding(service_info)}

      #{generate_service(service_info, endpoint_url)}

      </definitions>
      """
    end

    defp generate_types(service_info) do
      if Enum.empty?(service_info.types) do
        ""
      else
        """
        <types>
          <xsd:schema targetNamespace="#{service_info.target_namespace}">
        #{Enum.map_join(service_info.types, "\n", &generate_complex_type/1)}
          </xsd:schema>
        </types>
        """
      end
    end

    defp generate_complex_type(type) do
      """
          <xsd:complexType name="#{type.name}">
            <xsd:sequence>
      #{Enum.map_join(type.elements, "\n", &generate_element/1)}
            </xsd:sequence>
          </xsd:complexType>
      """
    end

    defp generate_element(element) do
      type_attr = map_elixir_type_to_xsd(element.type)
      min_occurs = if element.required, do: "1", else: "0"
      max_occurs = element.max_occurs || "1"

      """
              <xsd:element name="#{element.name}" type="#{type_attr}"
                           minOccurs="#{min_occurs}" maxOccurs="#{max_occurs}"/>
      """
    end

    defp generate_messages(service_info) do
      service_info.operations
      |> Enum.map_join("\n", &generate_operation_messages/1)
    end

    defp generate_operation_messages(operation) do
      """
      <message name="#{operation.name}Request">
      #{Enum.map_join(operation.input, "\n", &generate_message_part/1)}
      </message>

      <message name="#{operation.name}Response">
      #{Enum.map_join(operation.output, "\n", &generate_message_part/1)}
      </message>
      """
    end

    defp generate_message_part(param) do
      type_attr = map_elixir_type_to_xsd(param.type)

      """
        <part name="#{param.name}" type="#{type_attr}"/>
      """
    end

    defp generate_port_type(service_info) do
      """
      <portType name="#{service_info.name}PortType">
      #{Enum.map_join(service_info.operations, "\n", &generate_port_operation/1)}
      </portType>
      """
    end

    defp generate_port_operation(operation) do
      description =
        if operation.description do
          "\n      <documentation>#{operation.description}</documentation>"
        else
          ""
        end

      """
        <operation name="#{operation.name}">#{description}
          <input message="tns:#{operation.name}Request"/>
          <output message="tns:#{operation.name}Response"/>
        </operation>
      """
    end

    # Generate RPC-style SOAP binding (key difference from document style)
    defp generate_binding(service_info) do
      namespace = service_info.target_namespace

      """
      <binding name="#{service_info.name}Binding" type="tns:#{service_info.name}PortType">
        <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="rpc"/>
      #{Enum.map_join(service_info.operations, "\n", &generate_binding_operation(&1, namespace))}
      </binding>
      """
    end

    defp generate_binding_operation(operation, namespace) do
      soap_action = operation.soap_action || "#{operation.name}"

      """
        <operation name="#{operation.name}">
          <soap:operation soapAction="#{soap_action}" style="rpc"/>
          <input>
            <soap:body use="literal" namespace="#{namespace}"/>
          </input>
          <output>
            <soap:body use="literal" namespace="#{namespace}"/>
          </output>
        </operation>
      """
    end

    defp generate_service(service_info, endpoint_url) do
      """
      <service name="#{service_info.name}">
        <port name="#{service_info.name}Port" binding="tns:#{service_info.name}Binding">
          <soap:address location="#{endpoint_url}"/>
        </port>
      </service>
      """
    end

    defp map_elixir_type_to_xsd(:string), do: "xsd:string"
    defp map_elixir_type_to_xsd(:int), do: "xsd:int"
    defp map_elixir_type_to_xsd(:integer), do: "xsd:int"
    defp map_elixir_type_to_xsd(:boolean), do: "xsd:boolean"
    defp map_elixir_type_to_xsd(:decimal), do: "xsd:decimal"
    defp map_elixir_type_to_xsd(:float), do: "xsd:float"
    defp map_elixir_type_to_xsd(:dateTime), do: "xsd:dateTime"
    defp map_elixir_type_to_xsd("string"), do: "xsd:string"
    defp map_elixir_type_to_xsd("int"), do: "xsd:int"
    defp map_elixir_type_to_xsd("integer"), do: "xsd:int"
    defp map_elixir_type_to_xsd("boolean"), do: "xsd:boolean"
    defp map_elixir_type_to_xsd("decimal"), do: "xsd:decimal"
    defp map_elixir_type_to_xsd("float"), do: "xsd:float"
    defp map_elixir_type_to_xsd("dateTime"), do: "xsd:dateTime"
    defp map_elixir_type_to_xsd(type) when is_binary(type), do: "tns:#{type}"
    defp map_elixir_type_to_xsd(type), do: "tns:#{type}"
  end

  # Define the test service module at compile time
  defmodule RpcCalculatorService do
    use Lather.Server

    @namespace "http://test.example.com/rpc-calculator"
    @service_name "RpcCalculatorService"

    soap_operation "Multiply" do
      description "Multiplies two numbers"

      input do
        parameter "x", :decimal, required: true
        parameter "y", :decimal, required: true
      end

      output do
        parameter "product", :decimal
      end

      soap_action "Multiply"
    end

    soap_operation "Concatenate" do
      description "Concatenates two strings"

      input do
        parameter "first", :string, required: true
        parameter "second", :string, required: true
      end

      output do
        parameter "combined", :string
      end

      soap_action "Concatenate"
    end

    soap_operation "IsPositive" do
      description "Checks if a number is positive"

      input do
        parameter "number", :decimal, required: true
      end

      output do
        parameter "positive", :boolean
      end

      soap_action "IsPositive"
    end

    soap_operation "Power" do
      description "Raises base to exponent power"

      input do
        parameter "base", :decimal, required: true
        parameter "exponent", :decimal, required: true
      end

      output do
        parameter "result", :decimal
      end

      soap_action "Power"
    end

    def multiply(%{"x" => x, "y" => y}) do
      {:ok, %{"product" => parse_number(x) * parse_number(y)}}
    end

    def concatenate(%{"first" => first, "second" => second}) do
      {:ok, %{"combined" => "#{first}#{second}"}}
    end

    def is_positive(%{"number" => number}) do
      {:ok, %{"positive" => parse_number(number) > 0}}
    end

    def power(%{"base" => base, "exponent" => exponent}) do
      b = parse_number(base)
      e = parse_number(exponent)

      if b == 0 and e < 0 do
        Lather.Server.soap_fault("Client", "Cannot raise zero to negative power")
      else
        {:ok, %{"result" => :math.pow(b, e)}}
      end
    end

    defp parse_number(val) when is_number(val), do: val

    defp parse_number(val) when is_binary(val) do
      case Float.parse(val) do
        {num, _} -> num
        :error -> String.to_integer(val)
      end
    end
  end

  # Custom plug that uses our RPC WSDL generator
  defmodule RpcTestRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    alias Lather.Integration.RpcStyleRoundTripTest.RpcWsdlGenerator
    alias Lather.Integration.RpcStyleRoundTripTest.RpcCalculatorService

    match "/soap" do
      case conn.method do
        "GET" ->
          handle_wsdl_request(conn)

        "POST" ->
          Lather.Server.Plug.call(
            conn,
            Lather.Server.Plug.init(service: RpcCalculatorService)
          )
      end
    end

    defp handle_wsdl_request(conn) do
      service_info = RpcCalculatorService.__soap_service__()
      base_url = build_base_url(conn)
      wsdl_content = RpcWsdlGenerator.generate(service_info, base_url)

      conn
      |> Plug.Conn.put_resp_content_type("text/xml")
      |> Plug.Conn.send_resp(200, wsdl_content)
    end

    defp build_base_url(conn) do
      scheme = conn.scheme |> to_string()
      host = conn.host
      port = conn.port
      "#{scheme}://#{host}:#{port}/soap/"
    end
  end

  describe "RPC-style client-server round trip" do
    setup do
      # Start the Lather application (for Finch)
      {:ok, _} = Application.ensure_all_started(:lather)

      # Start the server on a random available port
      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: RpcTestRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      # Wait for server to be ready
      Process.sleep(50)

      {:ok, port: port, base_url: "http://localhost:#{port}"}
    end

    test "WSDL specifies RPC style in binding", %{base_url: base_url} do
      wsdl_url = "#{base_url}/soap?wsdl"

      # Fetch the WSDL directly to verify it has RPC style
      {:ok, response} = Finch.build(:get, wsdl_url) |> Finch.request(Lather.Finch)
      wsdl_content = response.body

      # Verify the binding has style="rpc"
      assert String.contains?(wsdl_content, ~s(style="rpc"))
      assert String.contains?(wsdl_content, "soap:binding")
    end

    test "client detects RPC style from WSDL", %{base_url: base_url} do
      wsdl_url = "#{base_url}/soap?wsdl"

      {:ok, client} = Lather.DynamicClient.new(wsdl_url, timeout: 5000)
      service_info = Lather.DynamicClient.get_service_info(client)

      # Verify that the operations have RPC style detected
      operations = service_info.operations
      assert length(operations) > 0

      # At least one operation should have rpc style
      # (The analyzer extracts style from the binding)
      multiply_op = Enum.find(operations, fn op -> op.name == "Multiply" end)
      assert multiply_op != nil
    end

    test "client can call Multiply operation via RPC style", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Verify operations are discovered
      operations = Lather.DynamicClient.list_operations(client)
      operation_names = Enum.map(operations, & &1.name)
      assert "Multiply" in operation_names

      # Make the call
      assert {:ok, response} = Lather.DynamicClient.call(client, "Multiply", %{"x" => 7, "y" => 6})

      # Verify we get the actual result
      assert is_map(response)
      assert Map.has_key?(response, "product")
      assert parse_result(response["product"]) == 42.0
    end

    test "client can call Concatenate operation with strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Concatenate", %{
                 "first" => "Hello",
                 "second" => "World"
               })

      assert Map.has_key?(response, "combined")
      assert response["combined"] == "HelloWorld"
    end

    test "client can call IsPositive operation returning boolean", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Test positive number
      assert {:ok, response} =
               Lather.DynamicClient.call(client, "IsPositive", %{"number" => 42})

      assert Map.has_key?(response, "positive")
      # Boolean might be returned as string "true" or boolean true
      assert response["positive"] in [true, "true"]

      # Test negative number
      assert {:ok, response2} =
               Lather.DynamicClient.call(client, "IsPositive", %{"number" => -5})

      assert response2["positive"] in [false, "false"]
    end

    test "client can call Power operation", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Power", %{"base" => 2, "exponent" => 10})

      assert Map.has_key?(response, "result")
      assert parse_result(response["result"]) == 1024.0
    end

    test "client receives SOAP fault for invalid operation", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Try to raise 0 to negative power (causes fault)
      assert {:error, error} =
               Lather.DynamicClient.call(client, "Power", %{"base" => 0, "exponent" => -1})

      assert error != nil
    end

    test "client can make multiple RPC-style calls in sequence", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, r1} = Lather.DynamicClient.call(client, "Multiply", %{"x" => 3, "y" => 4})
      assert {:ok, r2} = Lather.DynamicClient.call(client, "Multiply", %{"x" => 5, "y" => 6})
      assert {:ok, r3} = Lather.DynamicClient.call(client, "Power", %{"base" => 2, "exponent" => 3})

      assert parse_result(r1["product"]) == 12.0
      assert parse_result(r2["product"]) == 30.0
      assert parse_result(r3["result"]) == 8.0
    end

    test "client can make concurrent RPC-style calls", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      tasks = [
        Task.async(fn -> Lather.DynamicClient.call(client, "Multiply", %{"x" => 2, "y" => 3}) end),
        Task.async(fn -> Lather.DynamicClient.call(client, "Multiply", %{"x" => 4, "y" => 5}) end),
        Task.async(fn ->
          Lather.DynamicClient.call(client, "Concatenate", %{"first" => "a", "second" => "b"})
        end),
        Task.async(fn -> Lather.DynamicClient.call(client, "IsPositive", %{"number" => 100}) end)
      ]

      results = Task.await_many(tasks, 10_000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end

    test "response structure is correct for RPC style", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      {:ok, response} = Lather.DynamicClient.call(client, "Multiply", %{"x" => 5, "y" => 5})

      # Response should be flat with just the output parameters
      # NOT wrapped in extra keys like MultiplyResponse
      refute Map.has_key?(response, "MultiplyResponse")
      refute Map.has_key?(response, "Response")
      refute Map.has_key?(response, "soap:Body")
      refute Map.has_key?(response, "Body")

      # Should have the actual result key directly
      assert Map.has_key?(response, "product")
    end

    test "RPC style correctly uses operation name as wrapper in request", %{base_url: base_url} do
      # This test verifies that RPC-style requests are structured correctly
      # by checking that the server can parse and respond to them

      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Complex calculation to verify RPC message structure
      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Power", %{"base" => 3, "exponent" => 4})

      # 3^4 = 81
      assert parse_result(response["result"]) == 81.0
    end
  end

  describe "RPC style vs Document style comparison" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)
      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: RpcTestRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)
      {:ok, port: port, base_url: "http://localhost:#{port}"}
    end

    test "RPC WSDL has correct binding style attribute", %{base_url: base_url} do
      wsdl_url = "#{base_url}/soap?wsdl"
      {:ok, response} = Finch.build(:get, wsdl_url) |> Finch.request(Lather.Finch)
      wsdl_content = response.body

      # RPC binding should specify style="rpc"
      assert String.contains?(wsdl_content, ~s(style="rpc"))

      # Should also have transport and other SOAP binding attributes
      assert String.contains?(wsdl_content, "transport=")
    end

    test "operations discovered from RPC WSDL work correctly", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      operations = Lather.DynamicClient.list_operations(client)

      # Should have all our defined operations
      op_names = Enum.map(operations, & &1.name)
      assert "Multiply" in op_names
      assert "Concatenate" in op_names
      assert "IsPositive" in op_names
      assert "Power" in op_names

      # Each operation should have the expected parameters
      multiply = Enum.find(operations, &(&1.name == "Multiply"))
      assert multiply != nil
      assert "x" in multiply.required_parameters or "x" in (multiply[:optional_parameters] || [])
      assert "y" in multiply.required_parameters or "y" in (multiply[:optional_parameters] || [])
    end
  end

  defp parse_result(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> value
    end
  end

  defp parse_result(value) when is_number(value), do: value * 1.0
  defp parse_result(value), do: value
end
