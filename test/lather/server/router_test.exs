defmodule Lather.Server.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  defmodule CalcService do
    use Lather.Server

    @service_name "CalcService"
    @api_version "1.1.1"

    soap_operation "Add" do
      description("Adds two numbers")

      input do
        parameter("a", :int, required: true)
        parameter("b", :int, required: true)
      end

      output do
        parameter("sum", :int)
      end
    end

    def add(%{"a" => a, "b" => b}) do
      {:ok, %{"sum" => String.to_integer(a) + String.to_integer(b)}}
    end
  end

  defmodule SoapRouter do
    use Lather.Server.Router

    soap_route("/calc", Lather.Server.RouterTest.CalcService)
  end

  @config SoapRouter.init([])

  defp request(method, path, body \\ "") do
    conn(method, path, body) |> SoapRouter.call(@config)
  end

  test "the service is mounted at the routed path with a full overview" do
    response = request(:get, "/calc")

    assert response.status == 200
    assert response.resp_body =~ "CalcService - Service Overview"
    assert response.resp_body =~ ~s(<strong>API Version:</strong> 1.1.1)
    assert response.resp_body =~ ~s(href="?openapi")
  end

  test "subpaths dispatch through the service" do
    response = request(:get, "/calc?openapi")

    assert response.status == 200
    document = Jason.decode!(response.resp_body)
    assert document["openapi"] == "3.1.0"
    assert document["info"]["version"] == "1.1.1"
    assert document["servers"] == [%{"url" => "http://www.example.com/calc"}]
  end

  test "the JSON endpoint works through the macro" do
    response =
      request(:post, "/calc/api/Add", Jason.encode!(%{"a" => "2", "b" => "3"}))

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["success"] == true
    assert body["data"]["sum"] == 5
  end

  test "the WSDL endpoint works through the macro" do
    response = request(:get, "/calc?wsdl")

    assert response.status == 200
    assert response.resp_body =~ "CalcService"
    assert response.resp_body =~ "Version: 1.1.1"
  end

  test "options pass through to the enhanced plug" do
    defmodule NoSwaggerRouter do
      use Lather.Server.Router

      soap_route("/noswagger", Lather.Server.RouterTest.CalcService, enable_swagger: false)
    end

    response = conn(:get, "/noswagger?swagger") |> NoSwaggerRouter.call(NoSwaggerRouter.init([]))
    assert response.status == 404
  end
end
