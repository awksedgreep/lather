defmodule Lather.Integration.BasicAuthTest do
  @moduledoc """
  Integration tests for HTTP Basic Authentication.

  These tests verify the complete authentication flow including:
  1. Test service/plug that requires Basic Auth
  2. Successful authentication with correct credentials
  3. Authentication failure with wrong credentials
  4. Missing Authorization header (returns 401)
  5. Malformed Authorization header
  6. Authenticated requests can make SOAP calls successfully
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Lather.Auth.Basic
  alias Lather.DynamicClient

  # Test credentials
  @valid_username "admin"
  @valid_password "secret123"

  # Define a simple test service
  defmodule BasicAuthService do
    use Lather.Server

    @namespace "http://test.example.com/basicauth"
    @service_name "BasicAuthService"

    soap_operation "Greet" do
      description "Returns a greeting message"

      input do
        parameter "name", :string, required: true
      end

      output do
        parameter "greeting", :string
      end

      soap_action "Greet"
    end

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

    def greet(%{"name" => name}) do
      {:ok, %{"greeting" => "Hello, #{name}!"}}
    end

    def multiply(%{"x" => x, "y" => y}) do
      x_num = parse_number(x)
      y_num = parse_number(y)
      {:ok, %{"product" => x_num * y_num}}
    end

    defp parse_number(val) when is_number(val), do: val

    defp parse_number(val) when is_binary(val) do
      case Float.parse(val) do
        {num, _} -> num
        :error -> String.to_integer(val)
      end
    end
  end

  # Router that requires Basic Auth for SOAP operations
  defmodule BasicAuthRouter do
    use Plug.Router

    plug :fetch_query_params
    plug :match
    plug :dispatch

    # WSDL endpoint - no authentication required (allows service discovery)
    get "/soap" do
      if conn.query_params["wsdl"] != nil do
        Lather.Server.Plug.call(
          conn,
          Lather.Server.Plug.init(
            service: Lather.Integration.BasicAuthTest.BasicAuthService
          )
        )
      else
        send_resp(conn, 400, "Invalid request")
      end
    end

    # SOAP endpoint - requires Basic Auth
    post "/soap" do
      case authenticate_request(conn) do
        {:ok, conn} ->
          Lather.Server.Plug.call(
            conn,
            Lather.Server.Plug.init(
              service: Lather.Integration.BasicAuthTest.BasicAuthService
            )
          )

        {:error, reason} ->
          conn
          |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
          |> put_resp_content_type("text/xml")
          |> send_resp(401, build_fault_response(reason))
      end
    end

    defp authenticate_request(conn) do
      case Plug.Conn.get_req_header(conn, "authorization") do
        [] ->
          {:error, :missing_authorization}

        [auth_header | _] ->
          validate_credentials(conn, auth_header)
      end
    end

    defp validate_credentials(conn, auth_header) do
      validator = fn username, password ->
        username == "admin" && password == "secret123"
      end

      case Lather.Auth.Basic.validate(auth_header, validator) do
        {:ok, {username, _password}} ->
          {:ok, Plug.Conn.assign(conn, :authenticated_user, username)}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp build_fault_response(reason) do
      fault_message =
        case reason do
          :missing_authorization -> "Authorization header is required"
          :invalid_format -> "Invalid authorization header format"
          :invalid_encoding -> "Invalid Base64 encoding"
          :invalid_credentials -> "Invalid username or password"
          _ -> "Authentication failed"
        end

      """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Client</faultcode>
            <faultstring>#{fault_message}</faultstring>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """
    end
  end

  describe "test service with Basic Auth protection" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: BasicAuthRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(100)

      {:ok, port: port, base_url: "http://localhost:#{port}"}
    end

    test "WSDL is accessible without authentication", %{base_url: base_url} do
      request = Finch.build(:get, "#{base_url}/soap?wsdl", [], nil)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "definitions")
      assert String.contains?(response.body, "BasicAuthService")
    end

    test "SOAP endpoint requires authentication", %{port: port} do
      soap_request = build_greet_request("Test")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end
  end

  describe "successful authentication with correct credentials" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: BasicAuthRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(100)

      {:ok, port: port, base_url: "http://localhost:#{port}"}
    end

    test "valid credentials allow SOAP operation to succeed", %{port: port} do
      soap_request = build_greet_request("Alice")
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "greeting")
      assert String.contains?(response.body, "Hello, Alice!")
    end

    test "DynamicClient can discover operations (WSDL has no auth)", %{base_url: base_url} do
      {:ok, client} =
        DynamicClient.new(
          "#{base_url}/soap?wsdl",
          timeout: 5000
        )

      # Verify operations are discoverable even though calls require auth
      operations = DynamicClient.list_operations(client)
      operation_names = Enum.map(operations, & &1.name)
      assert "Greet" in operation_names
      assert "Multiply" in operation_names
    end

    test "multiple authenticated calls succeed", %{port: port} do
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      base_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      request1 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_greet_request("User1"))
      request2 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_greet_request("User2"))

      mult_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Multiply"},
        {auth_key, auth_value}
      ]
      request3 = Finch.build(:post, "http://localhost:#{port}/soap", mult_headers, build_multiply_request(6, 7))

      assert {:ok, r1} = Finch.request(request1, Lather.Finch)
      assert {:ok, r2} = Finch.request(request2, Lather.Finch)
      assert {:ok, r3} = Finch.request(request3, Lather.Finch)

      assert r1.status == 200
      assert r2.status == 200
      assert r3.status == 200

      assert String.contains?(r1.body, "Hello, User1!")
      assert String.contains?(r2.body, "Hello, User2!")
      assert String.contains?(r3.body, "42")
    end

    test "concurrent authenticated requests all succeed", %{port: port} do
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      base_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            request = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_greet_request("User#{i}"))
            Finch.request(request, Lather.Finch)
          end)
        end)

      results = Task.await_many(tasks, 10_000)

      assert Enum.all?(results, fn
               {:ok, %{status: 200}} -> true
               _ -> false
             end)
    end
  end

  describe "authentication failure with wrong credentials" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: BasicAuthRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(100)

      {:ok, port: port, base_url: "http://localhost:#{port}"}
    end

    test "wrong password returns 401", %{port: port} do
      soap_request = build_greet_request("Test")
      {auth_key, auth_value} = Basic.header(@valid_username, "wrongpassword")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert has_www_authenticate_header?(response)
      assert String.contains?(response.body, "Invalid username or password")
    end

    test "wrong username returns 401", %{port: port} do
      soap_request = build_greet_request("Test")
      {auth_key, auth_value} = Basic.header("wronguser", @valid_password)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert has_www_authenticate_header?(response)
    end

    test "both wrong username and password returns 401", %{port: port} do
      soap_request = build_greet_request("Test")
      {auth_key, auth_value} = Basic.header("baduser", "badpass")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "DynamicClient without auth fails on protected endpoint", %{base_url: base_url} do
      {:ok, client} =
        DynamicClient.new(
          "#{base_url}/soap?wsdl",
          timeout: 5000
        )

      # Should fail because no auth header is sent
      assert {:error, _} = DynamicClient.call(client, "Greet", %{"name" => "Test"})
    end
  end

  describe "missing Authorization header (returns 401)" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: BasicAuthRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(100)

      {:ok, port: port}
    end

    test "request without Authorization header returns 401", %{port: port} do
      soap_request = build_greet_request("Test")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert has_www_authenticate_header?(response)
      assert String.contains?(response.body, "Authorization header is required")
    end

    test "request with empty headers returns 401", %{port: port} do
      soap_request = build_greet_request("Test")

      # Only content-type, no auth
      headers = [{"content-type", "text/xml"}]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end
  end

  describe "malformed Authorization header" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: BasicAuthRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(100)

      {:ok, port: port}
    end

    test "Bearer token instead of Basic returns 401", %{port: port} do
      soap_request = build_greet_request("Test")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {"authorization", "Bearer some-jwt-token"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert String.contains?(response.body, "Invalid authorization header format")
    end

    test "invalid Base64 encoding returns 401", %{port: port} do
      soap_request = build_greet_request("Test")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {"authorization", "Basic !!!not-valid-base64!!!"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert String.contains?(response.body, "Invalid Base64 encoding")
    end

    test "empty Basic value returns 401", %{port: port} do
      soap_request = build_greet_request("Test")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {"authorization", "Basic "}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "credentials without colon separator returns 401", %{port: port} do
      soap_request = build_greet_request("Test")
      # Base64 encode a string without colon
      invalid_encoded = Base.encode64("usernamenopassword")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {"authorization", "Basic #{invalid_encoded}"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "just 'Basic' without encoded credentials returns 401", %{port: port} do
      soap_request = build_greet_request("Test")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {"authorization", "Basic"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "lowercase 'basic' prefix returns 401", %{port: port} do
      soap_request = build_greet_request("Test")
      # Use lowercase 'basic' - the implementation expects exact "Basic " prefix
      encoded = Base.encode64("#{@valid_username}:#{@valid_password}")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {"authorization", "basic #{encoded}"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "Digest auth scheme instead of Basic returns 401", %{port: port} do
      soap_request = build_greet_request("Test")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {"authorization", "Digest username=\"admin\", realm=\"test\""}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end
  end

  describe "authenticated requests can make SOAP calls successfully" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: BasicAuthRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(100)

      {:ok, port: port, base_url: "http://localhost:#{port}"}
    end

    test "Greet operation works with authentication", %{port: port} do
      soap_request = build_greet_request("World")
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "Hello, World!")
    end

    test "Multiply operation works with authentication", %{port: port} do
      soap_request = build_multiply_request(7, 8)
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Multiply"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "product")
      assert String.contains?(response.body, "56")
    end

    test "both Greet and Multiply operations work with auth via Finch", %{port: port} do
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      greet_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      greet_request = Finch.build(:post, "http://localhost:#{port}/soap", greet_headers, build_greet_request("Claude"))
      assert {:ok, greet_response} = Finch.request(greet_request, Lather.Finch)
      assert greet_response.status == 200
      assert String.contains?(greet_response.body, "Hello, Claude!")

      mult_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Multiply"},
        {auth_key, auth_value}
      ]

      mult_request = Finch.build(:post, "http://localhost:#{port}/soap", mult_headers, build_multiply_request(12, 5))
      assert {:ok, mult_response} = Finch.request(mult_request, Lather.Finch)
      assert mult_response.status == 200
      assert String.contains?(mult_response.body, "60")
    end

    test "authenticated client can handle various data types", %{port: port} do
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      # String with various characters
      greet_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Greet"},
        {auth_key, auth_value}
      ]

      request1 = Finch.build(:post, "http://localhost:#{port}/soap", greet_headers, build_greet_request("TestUser"))
      assert {:ok, r1} = Finch.request(request1, Lather.Finch)
      assert r1.status == 200
      assert String.contains?(r1.body, "TestUser")

      # Decimal numbers
      mult_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Multiply"},
        {auth_key, auth_value}
      ]

      request2 = Finch.build(:post, "http://localhost:#{port}/soap", mult_headers, build_multiply_request(3.14, 2.0))
      assert {:ok, r2} = Finch.request(request2, Lather.Finch)
      assert r2.status == 200

      # Integer values - result may be in scientific notation
      request3 = Finch.build(:post, "http://localhost:#{port}/soap", mult_headers, build_multiply_request(10, 20))
      assert {:ok, r3} = Finch.request(request3, Lather.Finch)
      assert r3.status == 200
      assert String.contains?(r3.body, "200")
    end

    test "authenticated requests maintain session across calls", %{port: port} do
      {auth_key, auth_value} = Basic.header(@valid_username, @valid_password)

      mult_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Multiply"},
        {auth_key, auth_value}
      ]

      # Make 10 sequential calls to verify auth persists
      results =
        Enum.map(1..10, fn i ->
          request = Finch.build(:post, "http://localhost:#{port}/soap", mult_headers, build_multiply_request(i, i))
          Finch.request(request, Lather.Finch)
        end)

      assert Enum.all?(results, fn
               {:ok, %{status: 200}} -> true
               _ -> false
             end)

      # Verify all requests succeeded
      assert length(results) == 10
    end
  end

  describe "Basic Auth header utilities" do
    test "Basic.header/2 creates correct header tuple" do
      {key, value} = Basic.header("user", "pass")

      assert key == "Authorization"
      assert String.starts_with?(value, "Basic ")

      # Decode and verify
      "Basic " <> encoded = value
      assert Base.decode64!(encoded) == "user:pass"
    end

    test "Basic.header_value/2 creates correct value" do
      value = Basic.header_value("testuser", "testpass")

      assert String.starts_with?(value, "Basic ")
      "Basic " <> encoded = value
      assert Base.decode64!(encoded) == "testuser:testpass"
    end

    test "Basic.decode/1 decodes valid header" do
      encoded = Base.encode64("admin:password123")
      assert {:ok, {"admin", "password123"}} = Basic.decode("Basic #{encoded}")
    end

    test "Basic.decode/1 handles password with colons" do
      encoded = Base.encode64("user:pass:with:colons")
      assert {:ok, {"user", "pass:with:colons"}} = Basic.decode("Basic #{encoded}")
    end

    test "Basic.decode/1 returns error for invalid format" do
      assert {:error, :invalid_format} = Basic.decode("Bearer token")
      assert {:error, :invalid_format} = Basic.decode("NotBasic value")
    end

    test "Basic.validate/2 validates against custom function" do
      validator = fn user, pass -> user == "admin" && pass == "secret" end

      valid_header = Basic.header_value("admin", "secret")
      invalid_header = Basic.header_value("admin", "wrong")

      assert {:ok, {"admin", "secret"}} = Basic.validate(valid_header, validator)
      assert {:error, :invalid_credentials} = Basic.validate(invalid_header, validator)
    end
  end

  # Helper functions

  defp build_greet_request(name) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                   xmlns:tns="http://test.example.com/basicauth">
      <soap:Body>
        <tns:Greet>
          <name>#{name}</name>
        </tns:Greet>
      </soap:Body>
    </soap:Envelope>
    """
  end

  defp build_multiply_request(x, y) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                   xmlns:tns="http://test.example.com/basicauth">
      <soap:Body>
        <tns:Multiply>
          <x>#{x}</x>
          <y>#{y}</y>
        </tns:Multiply>
      </soap:Body>
    </soap:Envelope>
    """
  end

  defp has_www_authenticate_header?(response) do
    Enum.any?(response.headers, fn {name, _value} ->
      String.downcase(name) == "www-authenticate"
    end)
  end
end
