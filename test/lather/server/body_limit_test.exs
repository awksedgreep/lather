defmodule Lather.Server.BodyLimitTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn, only: [put_req_header: 3]

  defmodule TestService do
    use Lather.Server

    @service_name "BodyLimitTestService"

    soap_operation "Echo" do
      description("Echoes a message")

      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end

      soap_action("Echo")
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  @small_limit 64

  describe "Lather.Server.Plug body limit" do
    test "init defaults max_body_size to 10MB" do
      config = Lather.Server.Plug.init(service: TestService)
      assert config.max_body_size == 10 * 1024 * 1024
    end

    test "init respects custom max_body_size" do
      config = Lather.Server.Plug.init(service: TestService, max_body_size: 1024)
      assert config.max_body_size == 1024
    end

    test "rejects oversized body with 413" do
      config = Lather.Server.Plug.init(service: TestService, max_body_size: @small_limit)
      big_body = String.duplicate("A", @small_limit + 100)

      conn =
        conn(:post, "/soap", big_body)
        |> put_req_header("content-type", "text/xml")
        |> Lather.Server.Plug.call(config)

      assert conn.status == 413
      assert conn.resp_body =~ "Request body too large"
    end

    test "accepts body within limit" do
      config = Lather.Server.Plug.init(service: TestService, max_body_size: 10 * 1024 * 1024)

      body = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <Echo><message>hi</message></Echo>
        </soap:Body>
      </soap:Envelope>
      """

      conn =
        conn(:post, "/soap", body)
        |> put_req_header("content-type", "text/xml")
        |> Lather.Server.Plug.call(config)

      assert conn.status == 200
    end
  end

  describe "Lather.Server.EnhancedPlug body limit" do
    test "init defaults max_body_size to 10MB" do
      config = Lather.Server.EnhancedPlug.init(service: TestService)
      assert config.max_body_size == 10 * 1024 * 1024
    end

    test "init respects custom max_body_size" do
      config = Lather.Server.EnhancedPlug.init(service: TestService, max_body_size: 1024)
      assert config.max_body_size == 1024
    end

    test "rejects oversized SOAP body with 413" do
      config =
        Lather.Server.EnhancedPlug.init(service: TestService, max_body_size: @small_limit)

      big_body = String.duplicate("B", @small_limit + 100)

      conn =
        conn(:post, "/soap", big_body)
        |> put_req_header("content-type", "text/xml")
        |> Lather.Server.EnhancedPlug.call(config)

      assert conn.status == 413
    end

    test "rejects oversized JSON body with 413" do
      config =
        Lather.Server.EnhancedPlug.init(service: TestService, max_body_size: @small_limit)

      big_body = String.duplicate("C", @small_limit + 100)

      conn =
        conn(:post, "/soap/api", big_body)
        |> put_req_header("content-type", "application/json")
        |> Lather.Server.EnhancedPlug.call(config)

      assert conn.status == 413
    end
  end

  describe "Lather.Server.Handler body limit" do
    test "rejects oversized body with 413 tuple" do
      big_body = String.duplicate("D", 200)

      assert {:error, 413, _, _} =
               Lather.Server.Handler.handle_request(
                 "POST",
                 "/soap",
                 [],
                 big_body,
                 TestService,
                 max_body_size: 64
               )
    end

    test "accepts body within limit" do
      body = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <Echo><message>hi</message></Echo>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, 200, _, _} =
               Lather.Server.Handler.handle_request("POST", "/soap", [], body, TestService)
    end
  end
end
