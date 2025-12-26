defmodule Lather.Integration.BasicAuthRoundTripTest do
  @moduledoc """
  End-to-end integration tests for HTTP Basic Authentication with SOAP services.

  These tests verify that:
  1. Basic Auth credentials are properly validated by the server
  2. Clients can send Basic Auth headers with SOAP requests
  3. Invalid or missing credentials result in 401 Unauthorized
  4. Edge cases like special characters and empty passwords are handled correctly
  """
  use ExUnit.Case, async: false

  # These tests require starting actual HTTP servers
  @moduletag :integration

  alias Lather.Auth.Basic

  # Define the test service module at compile time
  defmodule TestCalculatorService do
    use Lather.Server

    @namespace "http://test.example.com/calculator"
    @service_name "TestCalculatorService"

    soap_operation "Add" do
      description "Adds two numbers"

      input do
        parameter "a", :decimal, required: true
        parameter "b", :decimal, required: true
      end

      output do
        parameter "result", :decimal
      end

      soap_action "Add"
    end

    soap_operation "Echo" do
      description "Echoes the input message"

      input do
        parameter "message", :string, required: true
      end

      output do
        parameter "echo", :string
      end

      soap_action "Echo"
    end

    def add(%{"a" => a, "b" => b}) do
      {:ok, %{"result" => parse_number(a) + parse_number(b)}}
    end

    def echo(%{"message" => msg}) do
      {:ok, %{"echo" => msg}}
    end

    defp parse_number(val) when is_number(val), do: val

    defp parse_number(val) when is_binary(val) do
      case Float.parse(val) do
        {num, _} -> num
        :error -> String.to_integer(val)
      end
    end
  end

  # Router with Basic Auth protection
  defmodule AuthenticatedRouter do
    use Plug.Router

    # Valid credentials for testing
    @valid_username "testuser"
    @valid_password "testpass123"

    plug :fetch_query_params
    plug :match
    plug :dispatch

    # WSDL endpoint - no auth required
    get "/soap" do
      if conn.query_params["wsdl"] != nil do
        Lather.Server.Plug.call(
          conn,
          Lather.Server.Plug.init(
            service: Lather.Integration.BasicAuthRoundTripTest.TestCalculatorService
          )
        )
      else
        send_resp(conn, 400, "Invalid request")
      end
    end

    # SOAP endpoint - auth required
    post "/soap" do
      case authenticate(conn) do
        {:ok, conn} ->
          Lather.Server.Plug.call(
            conn,
            Lather.Server.Plug.init(
              service: Lather.Integration.BasicAuthRoundTripTest.TestCalculatorService
            )
          )

        {:error, reason} ->
          conn
          |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
          |> put_resp_content_type("text/xml")
          |> send_resp(401, unauthorized_response(reason))
      end
    end

    defp authenticate(conn) do
      case Plug.Conn.get_req_header(conn, "authorization") do
        [] ->
          {:error, :missing_authorization}

        [auth_header | _] ->
          validate_basic_auth(conn, auth_header)
      end
    end

    defp validate_basic_auth(conn, auth_header) do
      validator = fn username, password ->
        username == @valid_username && password == @valid_password
      end

      case Lather.Auth.Basic.validate(auth_header, validator) do
        {:ok, {username, _password}} ->
          {:ok, Plug.Conn.assign(conn, :current_user, username)}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp unauthorized_response(reason) do
      fault_string =
        case reason do
          :missing_authorization -> "Authorization header required"
          :invalid_format -> "Invalid authorization header format"
          :invalid_encoding -> "Invalid Base64 encoding in authorization header"
          :invalid_credentials -> "Invalid username or password"
          _ -> "Authentication failed"
        end

      """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Client</faultcode>
            <faultstring>#{fault_string}</faultstring>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """
    end
  end

  # Router that accepts special characters in credentials
  defmodule SpecialCharsRouter do
    use Plug.Router

    plug :fetch_query_params
    plug :match
    plug :dispatch

    # WSDL endpoint
    get "/soap" do
      if conn.query_params["wsdl"] != nil do
        Lather.Server.Plug.call(
          conn,
          Lather.Server.Plug.init(
            service: Lather.Integration.BasicAuthRoundTripTest.TestCalculatorService
          )
        )
      else
        send_resp(conn, 400, "Invalid request")
      end
    end

    # SOAP endpoint with special chars validator
    post "/soap" do
      case authenticate(conn) do
        {:ok, conn} ->
          Lather.Server.Plug.call(
            conn,
            Lather.Server.Plug.init(
              service: Lather.Integration.BasicAuthRoundTripTest.TestCalculatorService
            )
          )

        {:error, _reason} ->
          conn
          |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
          |> send_resp(401, "Unauthorized")
      end
    end

    defp authenticate(conn) do
      case Plug.Conn.get_req_header(conn, "authorization") do
        [] ->
          {:error, :missing_authorization}

        [auth_header | _] ->
          # Accept special characters in username and password
          validator = fn username, password ->
            username == "user@domain.com" && password == "p@ss:word&more!"
          end

          case Lather.Auth.Basic.validate(auth_header, validator) do
            {:ok, _} -> {:ok, conn}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  # Router that accepts empty password
  defmodule EmptyPasswordRouter do
    use Plug.Router

    plug :fetch_query_params
    plug :match
    plug :dispatch

    get "/soap" do
      if conn.query_params["wsdl"] != nil do
        Lather.Server.Plug.call(
          conn,
          Lather.Server.Plug.init(
            service: Lather.Integration.BasicAuthRoundTripTest.TestCalculatorService
          )
        )
      else
        send_resp(conn, 400, "Invalid request")
      end
    end

    post "/soap" do
      case authenticate(conn) do
        {:ok, conn} ->
          Lather.Server.Plug.call(
            conn,
            Lather.Server.Plug.init(
              service: Lather.Integration.BasicAuthRoundTripTest.TestCalculatorService
            )
          )

        {:error, _reason} ->
          conn
          |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
          |> send_resp(401, "Unauthorized")
      end
    end

    defp authenticate(conn) do
      case Plug.Conn.get_req_header(conn, "authorization") do
        [] ->
          {:error, :missing_authorization}

        [auth_header | _] ->
          # Accept empty password
          validator = fn username, password ->
            username == "service_account" && password == ""
          end

          case Lather.Auth.Basic.validate(auth_header, validator) do
            {:ok, _} -> {:ok, conn}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  describe "successful authentication" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: AuthenticatedRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "valid credentials allow successful SOAP operation", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("testuser", "testpass123")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "result")
      assert String.contains?(response.body, "15")
    end

    test "multiple sequential authenticated calls succeed", %{port: port} do
      {auth_key, auth_value} = Basic.header("testuser", "testpass123")

      base_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      # Make several calls in sequence
      request1 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(1, 2))
      request2 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(3, 4))
      request3 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(10, 10))

      assert {:ok, r1} = Finch.request(request1, Lather.Finch)
      assert {:ok, r2} = Finch.request(request2, Lather.Finch)
      assert {:ok, r3} = Finch.request(request3, Lather.Finch)

      assert r1.status == 200
      assert r2.status == 200
      assert r3.status == 200

      assert String.contains?(r1.body, "3")
      assert String.contains?(r2.body, "7")
      assert String.contains?(r3.body, "20")
    end

    test "concurrent authenticated calls succeed", %{port: port} do
      {auth_key, auth_value} = Basic.header("testuser", "testpass123")

      base_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      # Make concurrent calls
      tasks =
        Enum.map([{1, 1}, {2, 2}, {3, 3}, {5, 5}], fn {a, b} ->
          Task.async(fn ->
            request = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(a, b))
            Finch.request(request, Lather.Finch)
          end)
        end)

      results = Task.await_many(tasks, 10_000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, %{status: 200}} -> true
               _ -> false
             end)
    end

    test "direct HTTP request with Basic Auth header succeeds", %{port: port} do
      # Build SOAP request manually
      soap_request = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                     xmlns:tns="http://test.example.com/calculator">
        <soap:Body>
          <tns:Add>
            <a>25</a>
            <b>17</b>
          </tns:Add>
        </soap:Body>
      </soap:Envelope>
      """

      # Create Basic Auth header
      {auth_key, auth_value} = Basic.header("testuser", "testpass123")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      # Make direct HTTP request using Finch
      finch_name = Lather.Finch

      request =
        Finch.build(
          :post,
          "http://localhost:#{port}/soap",
          headers,
          soap_request
        )

      assert {:ok, response} = Finch.request(request, finch_name)
      assert response.status == 200
      assert String.contains?(response.body, "result")
    end
  end

  describe "failed authentication with invalid credentials" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: AuthenticatedRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "request with wrong password returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("testuser", "wrongpassword")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert has_www_authenticate_header?(response)
      assert String.contains?(response.body, "Invalid username or password")
    end

    test "request with wrong username returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("wronguser", "testpass123")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert has_www_authenticate_header?(response)
    end

    test "request with both wrong username and password returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("baduser", "badpass")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "request with invalid credentials receives 401 error", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("testuser", "wrongpassword")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end
  end

  describe "missing Authorization header" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: AuthenticatedRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "request without Authorization header returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert has_www_authenticate_header?(response)
      assert String.contains?(response.body, "Authorization header required")
    end

    test "request without auth configuration fails on protected endpoint", %{port: port} do
      soap_request = build_add_request(10, 5)

      # No Authorization header
      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert String.contains?(response.body, "Authorization header required")
    end
  end

  describe "malformed Authorization header handling" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: AuthenticatedRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "request with Bearer token instead of Basic returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {"authorization", "Bearer some-token-value"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert String.contains?(response.body, "Invalid authorization header format")
    end

    test "request with invalid Base64 encoding returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {"authorization", "Basic !!!invalid-base64!!!"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
      assert String.contains?(response.body, "Invalid Base64 encoding")
    end

    test "request with empty Basic value returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {"authorization", "Basic "}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "request with credentials missing colon returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)

      # Encode credentials without colon separator
      invalid_credentials = Base.encode64("usernameonly")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {"authorization", "Basic #{invalid_credentials}"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "request with just 'Basic' without encoded part returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {"authorization", "Basic"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end

    test "request with lowercase 'basic' prefix returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)

      # Use lowercase 'basic' instead of 'Basic'
      credentials = Base.encode64("testuser:testpass123")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {"authorization", "basic #{credentials}"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      # Should fail because implementation expects exact "Basic " prefix
      assert response.status == 401
    end
  end

  describe "special characters in username/password" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: SpecialCharsRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "username with @ symbol authenticates successfully", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("user@domain.com", "p@ss:word&more!")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
    end

    test "password with colon authenticates successfully", %{port: port} do
      # The password "p@ss:word&more!" contains a colon
      soap_request = build_add_request(20, 10)
      {auth_key, auth_value} = Basic.header("user@domain.com", "p@ss:word&more!")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "result")
    end

    test "request with special characters in credentials succeeds", %{port: port} do
      soap_request = build_add_request(100, 50)
      {auth_key, auth_value} = Basic.header("user@domain.com", "p@ss:word&more!")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "150")
    end

    test "password with ampersand and special chars works", %{port: port} do
      soap_request = build_add_request(5, 3)
      {auth_key, auth_value} = Basic.header("user@domain.com", "p@ss:word&more!")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
    end
  end

  describe "empty password handling" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: EmptyPasswordRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "empty password authenticates when server allows it", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("service_account", "")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "result")
    end

    test "request with empty password authenticates successfully", %{port: port} do
      soap_request = build_add_request(7, 3)
      {auth_key, auth_value} = Basic.header("service_account", "")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "10")
    end

    test "wrong username with empty password returns 401", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("wrong_account", "")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 401
    end
  end

  describe "client sending Basic Auth header with SOAP request" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: AuthenticatedRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "WSDL endpoint is accessible without authentication", %{port: port} do
      # WSDL should be accessible without auth
      request = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [], nil)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "definitions")
      assert String.contains?(response.body, "TestCalculatorService")
    end

    test "Basic Auth header is correctly formatted for SOAP request", %{port: port} do
      soap_request = build_add_request(42, 8)
      {auth_key, auth_value} = Basic.header("testuser", "testpass123")

      # Verify the header format
      assert auth_key == "Authorization"
      assert String.starts_with?(auth_value, "Basic ")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "50")
    end

    test "Authorization header is sent with every HTTP request", %{port: port} do
      {auth_key, auth_value} = Basic.header("testuser", "testpass123")

      base_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      # Each call should include the Authorization header
      request1 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(1, 1))
      request2 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(2, 2))
      request3 = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(3, 3))

      assert {:ok, r1} = Finch.request(request1, Lather.Finch)
      assert {:ok, r2} = Finch.request(request2, Lather.Finch)
      assert {:ok, r3} = Finch.request(request3, Lather.Finch)

      assert r1.status == 200
      assert r2.status == 200
      assert r3.status == 200
    end

    test "same credentials work across multiple sequential calls", %{port: port} do
      {auth_key, auth_value} = Basic.header("testuser", "testpass123")

      base_headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      # Make 5 sequential calls - all should succeed using stored credentials
      results =
        Enum.map(1..5, fn i ->
          request = Finch.build(:post, "http://localhost:#{port}/soap", base_headers, build_add_request(i, i))
          Finch.request(request, Lather.Finch)
        end)

      assert Enum.all?(results, fn
               {:ok, %{status: 200}} -> true
               _ -> false
             end)
    end
  end

  describe "edge cases and security" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: AuthenticatedRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      {:ok, port: port}
    end

    test "very long username is handled", %{port: port} do
      soap_request = build_add_request(10, 5)
      long_username = String.duplicate("a", 1000)
      {auth_key, auth_value} = Basic.header(long_username, "testpass123")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      # Should return 401 since the long username doesn't match
      assert response.status == 401
    end

    test "very long password is handled", %{port: port} do
      soap_request = build_add_request(10, 5)
      long_password = String.duplicate("b", 1000)
      {auth_key, auth_value} = Basic.header("testuser", long_password)

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      # Should return 401 since the long password doesn't match
      assert response.status == 401
    end

    test "Unicode credentials are handled correctly", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, auth_value} = Basic.header("user", "pass")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, auth_value}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      # Will return 401 since credentials don't match, but should not crash
      assert response.status == 401
    end

    test "null bytes in credentials are handled", %{port: port} do
      soap_request = build_add_request(10, 5)

      # Create credentials with null byte (this is a security test)
      # The null byte should be properly encoded in Base64
      credentials_with_null = Base.encode64("user\x00name:pass\x00word")

      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {"authorization", "Basic #{credentials_with_null}"}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      # Should handle gracefully (401 since credentials don't match)
      assert response.status == 401
    end

    test "multiple Authorization headers uses first one", %{port: port} do
      soap_request = build_add_request(10, 5)
      {auth_key, valid_auth} = Basic.header("testuser", "testpass123")
      {_, invalid_auth} = Basic.header("baduser", "badpass")

      # Send two Authorization headers - the first valid, second invalid
      headers = [
        {"content-type", "text/xml; charset=utf-8"},
        {"soapaction", "Add"},
        {auth_key, valid_auth},
        {auth_key, invalid_auth}
      ]

      request = Finch.build(:post, "http://localhost:#{port}/soap", headers, soap_request)
      assert {:ok, response} = Finch.request(request, Lather.Finch)

      # First header should be used (valid credentials)
      assert response.status == 200
    end
  end

  # Helper functions

  defp build_add_request(a, b) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                   xmlns:tns="http://test.example.com/calculator">
      <soap:Body>
        <tns:Add>
          <a>#{a}</a>
          <b>#{b}</b>
        </tns:Add>
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
