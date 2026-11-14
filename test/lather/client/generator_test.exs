defmodule Lather.Client.GeneratorTest do
  use ExUnit.Case, async: false

  alias Lather.Client.Generator
  alias Lather.TestUtils
  alias Lather.Wsdl.Analyzer

  defmodule OrderService do
    use Lather.Server

    @service_name "OrderService"

    soap_type "Order" do
      description("An order record")

      element("id", :string, required: true)
      element("total", :double)
    end

    soap_operation "GetOrder" do
      description("Fetch an order by id")

      input do
        parameter("orderId", :string, required: true)
        parameter("verbose", :boolean)
      end

      output do
        parameter("order", "Order")
      end
    end

    def get_order(%{"orderId" => order_id}) do
      {:ok, %{"order" => %{"id" => order_id, "total" => 42.5}}}
    end
  end

  defmodule Router do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Client.GeneratorTest.OrderService)
      )
    end
  end

  defp analyzed_source(wsdl) do
    {:ok, service_info} = Analyzer.analyze(wsdl)
    Generator.generate(service_info)
  end

  describe "generated source" do
    test "is valid Elixir" do
      wsdl =
        Lather.Server.WSDLGenerator.generate(
          OrderService.__soap_service__(),
          "http://localhost:4000/soap"
        )

      Code.string_to_quoted!(analyzed_source(wsdl))
    end

    test "defines one function per operation" do
      wsdl =
        Lather.Server.WSDLGenerator.generate(
          OrderService.__soap_service__(),
          "http://localhost:4000/soap"
        )

      source = analyzed_source(wsdl)

      assert source =~ "def get_order(client, order_id, verbose, opts \\\\ [])"
      assert source =~ "DynamicClient.call(client, \"GetOrder\""
      assert source =~ "defmodule OrderServiceClient do"
      assert source =~ "defmodule Order do"
      assert source =~ "defstruct [:id, :total]"
    end

    test "guards against Elixir keywords in parameter names" do
      service_info = %{
        service_name: "KeywordService",
        operations: [
          %{
            name: "DoFor",
            input: %{
              parts: [%{name: "for", type: "xsd:string"}, %{name: "and", type: "xsd:string"}]
            },
            output: %{parts: []}
          }
        ],
        types: []
      }

      source = Generator.generate(service_info, module: "KeywordClient")
      Code.string_to_quoted!(source)
      assert source =~ "param_for"
      assert source =~ "param_and"
    end
  end

  describe "round trip against a live service" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)
      {:ok, server_pid, port} = TestUtils.start_server(Router, 0)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, port: port, wsdl_url: "http://127.0.0.1:#{port}/soap?wsdl"}
    end

    test "the generated client calls the live service", %{wsdl_url: wsdl_url} do
      {:ok, service_info} = Analyzer.load_and_analyze(wsdl_url)

      source =
        Generator.generate(service_info,
          module: "Lather.GeneratedOrderClient",
          wsdl_url: wsdl_url
        )

      path =
        Path.join(
          System.tmp_dir!(),
          "generated_order_client_#{System.unique_integer([:positive])}.ex"
        )

      File.write(path, source)
      Code.require_file(path)

      client = Lather.GeneratedOrderClient.new()
      {:ok, result} = Lather.GeneratedOrderClient.get_order(client, "order-42", false)

      assert inspect(result) =~ "order-42"
    end
  end
end
