defmodule Lather.Regression.MediumPriorityFixesTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn, only: [put_req_header: 3]

  alias Lather.Http.SSLPoolManager
  alias Lather.Mtom.{Attachment, Mime}
  alias Lather.Server.EnhancedPlug
  alias Lather.Server.Plug, as: SOAPPlug
  alias Lather.Types.Mapper

  describe "service name default (issue #41)" do
    defmodule NamedSvc do
      use Lather.Server

      soap_operation "Ping" do
        description "ping"
      end

      def ping(_), do: {:ok, %{"pong" => "1"}}
    end

    test "the default service name is the defining module, not Lather.Server" do
      info = NamedSvc.__soap_service__()
      assert info.name == "Elixir.Lather.Regression.MediumPriorityFixesTest.NamedSvc"
    end
  end

  describe "enhanced WSDL flag (issue #40)" do
    defmodule EnhSvc do
      use Lather.Server
      @service_name "EnhSvc"
      soap_operation "Echo" do
        input do
          parameter("message", :string, required: true)
        end
      end
      def echo(%{"message" => m}), do: {:ok, %{"echo" => m}}
    end

    test "enhanced=false returns the standard (non-enhanced) WSDL" do
      config = EnhancedPlug.init(service: EnhSvc)

      response =
        conn(:get, "/soap?wsdl&enhanced=false")
        |> EnhancedPlug.call(config)

      assert response.status == 200
      refute response.resp_body =~ "soap12"
    end

    test "enhanced=true still returns the enhanced WSDL" do
      config = EnhancedPlug.init(service: EnhSvc)

      response =
        conn(:get, "/soap?wsdl&enhanced=true")
        |> EnhancedPlug.call(config)

      assert response.resp_body =~ "soap12"
    end
  end

  describe "query params are fetched (issue #43)" do
    defmodule PlugSvc do
      use Lather.Server
      @service_name "PlugSvc"
      soap_operation "Echo" do
        input do
          parameter("message", :string, required: true)
        end
      end
      def echo(%{"message" => m}), do: {:ok, %{"echo" => m}}
    end

    test "?wsdl=false does not return the WSDL" do
      config = SOAPPlug.init(service: PlugSvc, generate_wsdl: true)

      # Plug.Test conn leaves query_params unfetched (like a raw Bandit/Plug
      # connection without the fetch_query_params middleware).
      conn =
        conn(:get, "/soap?wsdl=false")
        |> put_req_header("content-type", "text/xml")
        |> SOAPPlug.call(config)

      # With query params fetched, wsdl=false takes the SOAP branch, which
      # rejects the empty body with a 400 rather than serving the WSDL.
      assert conn.status != 200
      refute conn.resp_body =~ "<definitions"
    end
  end

  describe "MTOM base64 transfer encoding (issue #42)" do
    test "base64 attachments round-trip to their original bytes" do
      payload = <<0, 1, 2, 255, 10, 13, 0>>
      attachment = Attachment.new(payload, "application/octet-stream", content_transfer_encoding: "base64")

      {_content_type, multipart} =
        Mime.build_multipart_message("<soap:Envelope/>", [attachment], boundary: "BOUNDARY")

      {:ok, {_soap, parts}} =
        Mime.parse_multipart_message("multipart/related; boundary=BOUNDARY", multipart)

      [decoded | _] = parts
      assert decoded.content == payload
    end
  end

  describe "SSL pool registry (issue #35)" do
    test "claim is serialized so the limit is never exceeded under load" do
      SSLPoolManager.reset()
      Application.put_env(:lather, :max_ssl_pools, 3)

      results =
        1..10
        |> Enum.map(fn i ->
          Task.async(fn -> SSLPoolManager.claim("https://pool#{i}.example.com/soap", verify: :verify_peer) end)
        end)
        |> Enum.map(&Task.await/1)

      ok_count = Enum.count(results, &(&1 == :ok))
      assert ok_count == 3
      assert SSLPoolManager.count() == 3

      Application.delete_env(:lather, :max_ssl_pools)
    end
  end

  describe "type mapper coercion (issue #44)" do
    test "truncated numeric values no longer silently become numbers" do
      context = %{
        type_registry: %{
          "Rec" => %{
            category: :complex_type,
            name: "Rec",
            elements: [
              %{name: "age", type: "xsd:int", min_occurs: "1", max_occurs: "1"},
              %{name: "active", type: "xsd:boolean", min_occurs: "1", max_occurs: "1"}
            ]
          }
        },
        namespaces: %{},
        options: []
      }

      xml = %{"age" => "1.5", "active" => "0"}
      {:ok, result} = Mapper.xml_to_elixir(xml, "Rec", context)

      assert result[:age] == 0
      assert result[:active] == false
    end

    test "boolean serializes to canonical XSD form" do
      context = %{
        type_registry: %{
          "BoolRec" => %{
            category: :complex_type,
            name: "BoolRec",
            elements: [%{name: "flag", type: "xsd:boolean", min_occurs: "1", max_occurs: "1"}]
          }
        },
        namespaces: %{},
        options: []
      }

      {:ok, xml} = Mapper.elixir_to_xml(%{flag: 0}, "BoolRec", context)
      assert xml["flag"] == "false"
    end
  end
end
