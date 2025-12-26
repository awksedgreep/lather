defmodule Lather.Integration.WSSecurityAuthTest do
  @moduledoc """
  Comprehensive integration tests for WS-Security authentication.

  These tests verify complete WS-Security authentication scenarios including:
  - UsernameToken with plaintext password
  - UsernameToken with digest password (SHA1)
  - Timestamp headers and validation
  - Combined UsernameToken + Timestamp
  - Authentication failure scenarios
  """
  use ExUnit.Case, async: false

  # These tests require starting actual HTTP servers
  @moduletag :integration

  alias Lather.Auth.WSSecurity
  alias Lather.Soap.Header

  # Test credentials
  @valid_username "test_admin"
  @valid_password "secure_pass_123"

  # WS-Security namespaces
  @wsse_ns "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
  @wsu_ns "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
  @password_text_type "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText"
  @password_digest_type "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest"

  # Test service module
  defmodule SecureCalculatorService do
    use Lather.Server

    @namespace "http://test.example.com/secure"
    @service_name "SecureCalculatorService"

    soap_operation "SecureAdd" do
      description "Adds two numbers securely"

      input do
        parameter "a", :decimal, required: true
        parameter "b", :decimal, required: true
      end

      output do
        parameter "result", :decimal
      end

      soap_action "SecureAdd"
    end

    soap_operation "SecureEcho" do
      description "Echoes the input message securely"

      input do
        parameter "message", :string, required: true
      end

      output do
        parameter "echo", :string
      end

      soap_action "SecureEcho"
    end

    def secure_add(%{"a" => a, "b" => b}) do
      {:ok, %{"result" => parse_number(a) + parse_number(b)}}
    end

    def secure_echo(%{"message" => msg}) do
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

  # ETS-based configuration storage for cross-process access
  defmodule SecurityConfig do
    @table_name :ws_security_auth_test_config

    def init do
      if :ets.whereis(@table_name) == :undefined do
        :ets.new(@table_name, [:named_table, :public, :set])
      end

      :ok
    end

    def set(mode, opts) do
      init()
      :ets.insert(@table_name, {:config, mode, opts})
    end

    def get do
      init()

      case :ets.lookup(@table_name, :config) do
        [{:config, mode, opts}] -> {mode, opts}
        [] -> {:text_password, []}
      end
    end
  end

  # Router that validates WS-Security headers
  defmodule SecureRouter do
    use Plug.Router

    @wsse_namespace "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"

    plug(:fetch_query_params)
    plug(:match)
    plug(:dispatch)

    # WSDL endpoint - no auth required
    get "/soap" do
      if conn.query_params["wsdl"] != nil do
        Lather.Server.Plug.call(
          conn,
          Lather.Server.Plug.init(
            service: Lather.Integration.WSSecurityAuthTest.SecureCalculatorService
          )
        )
      else
        send_resp(conn, 400, "Invalid request")
      end
    end

    # SOAP endpoint - requires WS-Security authentication
    post "/soap" do
      {:ok, body, conn} = read_full_body(conn)

      {validation_mode, opts} = Lather.Integration.WSSecurityAuthTest.SecurityConfig.get()

      case validate_ws_security(body, validation_mode, opts) do
        {:ok, _security_info} ->
          handle_soap_request(conn, body)

        {:error, :missing_security_header} ->
          send_soap_fault(
            conn,
            "Client",
            "wsse:InvalidSecurityToken",
            "WS-Security header is required but was not found"
          )

        {:error, :invalid_credentials} ->
          send_soap_fault(
            conn,
            "Client",
            "wsse:FailedAuthentication",
            "Authentication failed: invalid username or password"
          )

        {:error, :invalid_password_digest} ->
          send_soap_fault(
            conn,
            "Client",
            "wsse:FailedAuthentication",
            "Authentication failed: password digest verification failed"
          )

        {:error, :timestamp_expired} ->
          send_soap_fault(
            conn,
            "Client",
            "wsse:MessageExpired",
            "Message has expired based on timestamp"
          )

        {:error, :missing_timestamp} ->
          send_soap_fault(
            conn,
            "Client",
            "wsse:InvalidSecurityToken",
            "Timestamp is required but was not found"
          )

        {:error, :invalid_timestamp} ->
          send_soap_fault(
            conn,
            "Client",
            "wsse:InvalidSecurityToken",
            "Timestamp format is invalid"
          )

        {:error, reason} ->
          send_soap_fault(
            conn,
            "Client",
            "wsse:InvalidSecurityToken",
            "Security validation failed: #{inspect(reason)}"
          )
      end
    end

    defp read_full_body(conn, body \\ "") do
      case Plug.Conn.read_body(conn) do
        {:ok, chunk, conn} -> {:ok, body <> chunk, conn}
        {:more, chunk, conn} -> read_full_body(conn, body <> chunk)
        {:error, reason} -> {:error, reason}
      end
    end

    defp handle_soap_request(conn, body) do
      case Lather.Xml.Parser.parse(body) do
        {:ok, parsed} ->
          envelope = parsed["soap:Envelope"] || parsed["Envelope"] || %{}
          body_content = envelope["soap:Body"] || envelope["Body"] || %{}

          # Extract the operation
          {op_name, result} = process_operation(body_content)

          response_xml = """
          <?xml version="1.0" encoding="UTF-8"?>
          <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
            <soap:Body>
              <#{op_name}Response xmlns="http://test.example.com/secure">
                #{build_result_xml(result)}
              </#{op_name}Response>
            </soap:Body>
          </soap:Envelope>
          """

          conn
          |> Plug.Conn.put_resp_content_type("text/xml")
          |> Plug.Conn.send_resp(200, response_xml)

        {:error, _reason} ->
          send_soap_fault(conn, "Client", "InvalidRequest", "Failed to parse SOAP request")
      end
    end

    defp process_operation(body_content) do
      cond do
        Map.has_key?(body_content, "SecureAdd") || Map.has_key?(body_content, "tns:SecureAdd") ->
          op = body_content["SecureAdd"] || body_content["tns:SecureAdd"] || %{}
          a = parse_number(op["a"] || "0")
          b = parse_number(op["b"] || "0")
          {"SecureAdd", %{"result" => a + b}}

        Map.has_key?(body_content, "SecureEcho") || Map.has_key?(body_content, "tns:SecureEcho") ->
          op = body_content["SecureEcho"] || body_content["tns:SecureEcho"] || %{}
          message = op["message"] || ""
          {"SecureEcho", %{"echo" => message}}

        true ->
          {"Unknown", %{"error" => "Unknown operation"}}
      end
    end

    defp parse_number(val) when is_number(val), do: val

    defp parse_number(val) when is_binary(val) do
      case Float.parse(val) do
        {num, _} -> num
        :error -> 0
      end
    end

    defp build_result_xml(result) do
      result
      |> Enum.map(fn {k, v} -> "<#{k}>#{escape_xml(v)}</#{k}>" end)
      |> Enum.join()
    end

    defp escape_xml(text) when is_binary(text) do
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
    end

    defp escape_xml(val), do: to_string(val)

    defp validate_ws_security(body, mode, opts) do
      case Lather.Xml.Parser.parse(body) do
        {:ok, parsed} ->
          security = extract_security_header(parsed)
          validate_security(security, mode, opts)

        {:error, reason} ->
          {:error, {:parse_error, reason}}
      end
    end

    defp extract_security_header(parsed) do
      envelope = parsed["soap:Envelope"] || parsed["Envelope"] || %{}
      header = envelope["soap:Header"] || envelope["Header"]

      case header do
        nil -> nil
        "" -> nil
        header when is_map(header) -> header["wsse:Security"] || header["Security"] || nil
        _ -> nil
      end
    end

    # No authentication required
    defp validate_security(_security, :no_auth, _opts), do: {:ok, :no_auth_required}

    # Require security header to be present
    defp validate_security(nil, _mode, _opts), do: {:error, :missing_security_header}

    # Validate plaintext password
    defp validate_security(security, :text_password, opts) do
      expected_username = Keyword.get(opts, :username, "test_admin")
      expected_password = Keyword.get(opts, :password, "secure_pass_123")

      username_token = security["wsse:UsernameToken"] || security["UsernameToken"] || %{}
      username = username_token["wsse:Username"] || username_token["Username"]
      password_elem = username_token["wsse:Password"] || username_token["Password"] || %{}

      password = extract_password_text(password_elem)
      password_type = extract_password_type(password_elem)

      cond do
        username != expected_username ->
          {:error, :invalid_credentials}

        password != expected_password ->
          {:error, :invalid_credentials}

        password_type && !String.contains?(password_type, "PasswordText") ->
          {:error, :invalid_password_type}

        true ->
          {:ok, %{username: username, password_type: :text}}
      end
    end

    # Validate digest password
    defp validate_security(security, :digest_password, opts) do
      expected_username = Keyword.get(opts, :username, "test_admin")
      expected_password = Keyword.get(opts, :password, "secure_pass_123")

      username_token = security["wsse:UsernameToken"] || security["UsernameToken"] || %{}
      username = username_token["wsse:Username"] || username_token["Username"]
      password_elem = username_token["wsse:Password"] || username_token["Password"] || %{}
      nonce_elem = username_token["wsse:Nonce"] || username_token["Nonce"] || %{}
      created = username_token["wsu:Created"] || username_token["Created"]

      password_digest = extract_password_text(password_elem)
      password_type = extract_password_type(password_elem)
      nonce = extract_nonce(nonce_elem)

      cond do
        username != expected_username ->
          {:error, :invalid_credentials}

        password_type && !String.contains?(password_type, "PasswordDigest") ->
          {:error, :invalid_password_type}

        !verify_password_digest(password_digest, expected_password, nonce, created) ->
          {:error, :invalid_password_digest}

        true ->
          {:ok, %{username: username, password_type: :digest}}
      end
    end

    # Validate timestamp only
    defp validate_security(security, :timestamp_only, opts) do
      timestamp = security["wsu:Timestamp"] || security["Timestamp"] || %{}
      validate_timestamp(timestamp, opts)
    end

    # Require timestamp to be present
    defp validate_security(security, :require_timestamp, opts) do
      timestamp = security["wsu:Timestamp"] || security["Timestamp"]

      if timestamp do
        validate_timestamp(timestamp, opts)
      else
        {:error, :missing_timestamp}
      end
    end

    # Combined username + timestamp validation
    defp validate_security(security, :username_with_timestamp, opts) do
      case validate_security(security, :text_password, opts) do
        {:ok, cred_info} ->
          timestamp = security["wsu:Timestamp"] || security["Timestamp"] || %{}

          case validate_timestamp(timestamp, opts) do
            {:ok, ts_info} ->
              {:ok, Map.merge(cred_info, ts_info)}

            error ->
              error
          end

        error ->
          error
      end
    end

    # Combined digest username + timestamp validation
    defp validate_security(security, :digest_with_timestamp, opts) do
      case validate_security(security, :digest_password, opts) do
        {:ok, cred_info} ->
          timestamp = security["wsu:Timestamp"] || security["Timestamp"] || %{}

          case validate_timestamp(timestamp, opts) do
            {:ok, ts_info} ->
              {:ok, Map.merge(cred_info, ts_info)}

            error ->
              error
          end

        error ->
          error
      end
    end

    defp validate_timestamp(nil, _opts), do: {:error, :missing_timestamp}

    defp validate_timestamp(timestamp, opts) do
      created = timestamp["wsu:Created"] || timestamp["Created"]
      expires = timestamp["wsu:Expires"] || timestamp["Expires"]

      reject_expired = Keyword.get(opts, :reject_expired, true)

      cond do
        is_nil(created) ->
          {:error, :invalid_timestamp}

        is_nil(expires) ->
          {:error, :invalid_timestamp}

        reject_expired && timestamp_expired?(expires) ->
          {:error, :timestamp_expired}

        true ->
          {:ok, %{created: created, expires: expires}}
      end
    end

    defp timestamp_expired?(expires_str) do
      case DateTime.from_iso8601(expires_str) do
        {:ok, expires_dt, _offset} ->
          DateTime.compare(DateTime.utc_now(), expires_dt) == :gt

        _ ->
          true
      end
    end

    defp extract_password_text(password_elem) when is_binary(password_elem), do: password_elem
    defp extract_password_text(%{"#text" => text}), do: text
    defp extract_password_text(_), do: nil

    defp extract_password_type(%{"@Type" => type}), do: type
    defp extract_password_type(_), do: nil

    defp extract_nonce(nonce_elem) when is_binary(nonce_elem), do: nonce_elem
    defp extract_nonce(%{"#text" => text}), do: text
    defp extract_nonce(_), do: nil

    defp verify_password_digest(digest, password, nonce, created)
         when is_binary(digest) and is_binary(nonce) and is_binary(created) do
      case Base.decode64(nonce) do
        {:ok, nonce_decoded} ->
          digest_input = nonce_decoded <> created <> password
          expected_digest = :crypto.hash(:sha, digest_input) |> Base.encode64()
          digest == expected_digest

        :error ->
          false
      end
    end

    defp verify_password_digest(_, _, _, _), do: false

    defp send_soap_fault(conn, fault_code, subcode, fault_string) do
      fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                     xmlns:wsse="#{@wsse_namespace}">
        <soap:Body>
          <soap:Fault>
            <faultcode>#{fault_code}</faultcode>
            <faultstring>#{fault_string}</faultstring>
            <detail>
              <wsse:SecurityFault>#{subcode}</wsse:SecurityFault>
            </detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      conn
      |> Plug.Conn.put_resp_content_type("text/xml")
      |> Plug.Conn.send_resp(500, fault_xml)
    end
  end

  # ============================================================================
  # Test: UsernameToken with plaintext password
  # ============================================================================

  describe "UsernameToken with plaintext password" do
    setup do
      start_test_server(:text_password, username: @valid_username, password: @valid_password)
    end

    test "successful authentication with valid credentials", %{base_url: base_url} do
      security_header =
        WSSecurity.username_token(@valid_username, @valid_password, password_type: :text)

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 10, "b" => 5},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 200
      assert String.contains?(response.body, "result")
      assert String.contains?(response.body, "15")
    end

    test "header structure contains correct password type attribute" do
      token = WSSecurity.username_token(@valid_username, @valid_password, password_type: :text)

      password_elem = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsse:Password"])

      assert password_elem["@Type"] == @password_text_type
    end

    test "header includes wsu:Created timestamp by default" do
      token = WSSecurity.username_token(@valid_username, @valid_password)

      created = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsu:Created"])

      assert is_binary(created)
      assert {:ok, _, _} = DateTime.from_iso8601(created)
    end

    test "header includes correct wsse namespace" do
      token = WSSecurity.username_token(@valid_username, @valid_password)

      assert token["wsse:Security"]["@xmlns:wsse"] == @wsse_ns
    end

    test "header includes correct wsu namespace" do
      token = WSSecurity.username_token(@valid_username, @valid_password)

      assert token["wsse:Security"]["@xmlns:wsu"] == @wsu_ns
    end

    test "DynamicClient can make authenticated calls", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      security_header = Header.username_token(@valid_username, @valid_password)

      {:ok, response} =
        Lather.DynamicClient.call(
          client,
          "SecureAdd",
          %{"a" => 20, "b" => 30},
          headers: [security_header]
        )

      assert Map.has_key?(response, "result")
    end

    test "multiple sequential authenticated calls succeed", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      security_header = Header.username_token(@valid_username, @valid_password)

      {:ok, r1} =
        Lather.DynamicClient.call(
          client,
          "SecureAdd",
          %{"a" => 1, "b" => 2},
          headers: [security_header]
        )

      {:ok, r2} =
        Lather.DynamicClient.call(
          client,
          "SecureAdd",
          %{"a" => 3, "b" => 4},
          headers: [security_header]
        )

      {:ok, r3} =
        Lather.DynamicClient.call(
          client,
          "SecureEcho",
          %{"message" => "test"},
          headers: [security_header]
        )

      assert Map.has_key?(r1, "result")
      assert Map.has_key?(r2, "result")
      assert Map.has_key?(r3, "echo")
    end
  end

  # ============================================================================
  # Test: UsernameToken with digest password (SHA1)
  # ============================================================================

  describe "UsernameToken with digest password (SHA1)" do
    setup do
      start_test_server(:digest_password, username: @valid_username, password: @valid_password)
    end

    test "successful authentication with digest credentials", %{base_url: base_url} do
      security_header =
        WSSecurity.username_token(
          @valid_username,
          @valid_password,
          password_type: :digest
        )

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 100, "b" => 50},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 200
      assert String.contains?(response.body, "150")
    end

    test "header contains password digest type attribute" do
      token = WSSecurity.username_token(@valid_username, @valid_password, password_type: :digest)

      password_elem = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsse:Password"])

      assert password_elem["@Type"] == @password_digest_type
    end

    test "header includes nonce element for digest auth" do
      token = WSSecurity.username_token(@valid_username, @valid_password, password_type: :digest)

      nonce_elem = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsse:Nonce"])

      assert is_map(nonce_elem)
      assert Map.has_key?(nonce_elem, "#text")
      assert Map.has_key?(nonce_elem, "@EncodingType")
      assert String.contains?(nonce_elem["@EncodingType"], "Base64Binary")
    end

    test "nonce is base64 encoded" do
      token = WSSecurity.username_token(@valid_username, @valid_password, password_type: :digest)

      nonce = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsse:Nonce", "#text"])

      # Should be valid base64
      assert {:ok, _decoded} = Base.decode64(nonce)
    end

    test "digest includes created timestamp" do
      token = WSSecurity.username_token(@valid_username, @valid_password, password_type: :digest)

      created = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsu:Created"])

      assert is_binary(created)
      assert {:ok, _, _} = DateTime.from_iso8601(created)
    end

    test "different calls produce different nonces and digests" do
      token1 = WSSecurity.username_token(@valid_username, @valid_password, password_type: :digest)
      token2 = WSSecurity.username_token(@valid_username, @valid_password, password_type: :digest)

      nonce1 = get_in(token1, ["wsse:Security", "wsse:UsernameToken", "wsse:Nonce", "#text"])
      nonce2 = get_in(token2, ["wsse:Security", "wsse:UsernameToken", "wsse:Nonce", "#text"])

      digest1 = get_in(token1, ["wsse:Security", "wsse:UsernameToken", "wsse:Password", "#text"])
      digest2 = get_in(token2, ["wsse:Security", "wsse:UsernameToken", "wsse:Password", "#text"])

      # Nonces should be different (randomized)
      refute nonce1 == nonce2

      # Digests should be different (since they include nonce and timestamp)
      refute digest1 == digest2
    end

    test "password is properly hashed using SHA1(nonce + created + password)" do
      token = WSSecurity.username_token(@valid_username, @valid_password, password_type: :digest)

      nonce = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsse:Nonce", "#text"])
      created = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsu:Created"])
      digest = get_in(token, ["wsse:Security", "wsse:UsernameToken", "wsse:Password", "#text"])

      # Verify the digest manually
      {:ok, nonce_decoded} = Base.decode64(nonce)
      expected_digest = :crypto.hash(:sha, nonce_decoded <> created <> @valid_password) |> Base.encode64()

      assert digest == expected_digest
    end
  end

  # ============================================================================
  # Test: Timestamp headers and validation
  # ============================================================================

  describe "Timestamp headers and validation" do
    setup do
      start_test_server(:timestamp_only, reject_expired: true)
    end

    test "valid timestamp is accepted", %{base_url: base_url} do
      timestamp_header = WSSecurity.timestamp(ttl: 300)

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "timestamp test"},
          headers: [timestamp_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 200
    end

    test "timestamp includes Created element" do
      timestamp = WSSecurity.timestamp()

      created = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Created"])

      assert is_binary(created)
      assert {:ok, _, _} = DateTime.from_iso8601(created)
    end

    test "timestamp includes Expires element" do
      timestamp = WSSecurity.timestamp()

      expires = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Expires"])

      assert is_binary(expires)
      assert {:ok, _, _} = DateTime.from_iso8601(expires)
    end

    test "Expires is after Created" do
      timestamp = WSSecurity.timestamp(ttl: 300)

      created_str = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Created"])
      expires_str = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Expires"])

      {:ok, created, _} = DateTime.from_iso8601(created_str)
      {:ok, expires, _} = DateTime.from_iso8601(expires_str)

      assert DateTime.compare(expires, created) == :gt
    end

    test "TTL is correctly applied" do
      timestamp = WSSecurity.timestamp(ttl: 600)

      created_str = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Created"])
      expires_str = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Expires"])

      {:ok, created, _} = DateTime.from_iso8601(created_str)
      {:ok, expires, _} = DateTime.from_iso8601(expires_str)

      diff = DateTime.diff(expires, created)
      assert diff == 600
    end

    test "default TTL is 300 seconds" do
      timestamp = WSSecurity.timestamp()

      created_str = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Created"])
      expires_str = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Expires"])

      {:ok, created, _} = DateTime.from_iso8601(created_str)
      {:ok, expires, _} = DateTime.from_iso8601(expires_str)

      diff = DateTime.diff(expires, created)
      assert diff == 300
    end

    test "short TTL creates near-future expiry" do
      timestamp = WSSecurity.timestamp(ttl: 30)

      expires_str = get_in(timestamp, ["wsse:Security", "wsu:Timestamp", "wsu:Expires"])
      {:ok, expires, _} = DateTime.from_iso8601(expires_str)

      now = DateTime.utc_now()
      diff = DateTime.diff(expires, now)

      # Should be approximately 30 seconds in the future (allow some tolerance)
      assert diff >= 25 and diff <= 35
    end
  end

  # ============================================================================
  # Test: Combined UsernameToken + Timestamp
  # ============================================================================

  describe "Combined UsernameToken + Timestamp" do
    setup do
      start_test_server(:username_with_timestamp, username: @valid_username, password: @valid_password)
    end

    test "combined header is accepted by server", %{base_url: base_url} do
      combined_header =
        WSSecurity.username_token_with_timestamp(
          @valid_username,
          @valid_password,
          ttl: 300
        )

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 25, "b" => 75},
          headers: [combined_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 200
      assert String.contains?(response.body, "100")
    end

    test "combined header includes both UsernameToken and Timestamp" do
      combined = WSSecurity.username_token_with_timestamp(@valid_username, @valid_password)

      security = combined["wsse:Security"]

      assert Map.has_key?(security, "wsse:UsernameToken")
      assert Map.has_key?(security, "wsu:Timestamp")
    end

    test "UsernameToken has unique ID" do
      combined = WSSecurity.username_token_with_timestamp(@valid_username, @valid_password)

      username_token = get_in(combined, ["wsse:Security", "wsse:UsernameToken"])

      assert Map.has_key?(username_token, "@wsu:Id")
      assert String.starts_with?(username_token["@wsu:Id"], "UsernameToken-")
    end

    test "Timestamp has unique ID" do
      combined = WSSecurity.username_token_with_timestamp(@valid_username, @valid_password)

      timestamp = get_in(combined, ["wsse:Security", "wsu:Timestamp"])

      assert Map.has_key?(timestamp, "@wsu:Id")
      assert String.starts_with?(timestamp["@wsu:Id"], "Timestamp-")
    end

    test "IDs are unique across multiple calls" do
      combined1 = WSSecurity.username_token_with_timestamp(@valid_username, @valid_password)
      combined2 = WSSecurity.username_token_with_timestamp(@valid_username, @valid_password)

      id1 = get_in(combined1, ["wsse:Security", "wsse:UsernameToken", "@wsu:Id"])
      id2 = get_in(combined2, ["wsse:Security", "wsse:UsernameToken", "@wsu:Id"])

      refute id1 == id2
    end

    test "combined header with digest password type" do
      combined =
        WSSecurity.username_token_with_timestamp(
          @valid_username,
          @valid_password,
          password_type: :digest
        )

      password_elem = get_in(combined, ["wsse:Security", "wsse:UsernameToken", "wsse:Password"])

      assert String.contains?(password_elem["@Type"], "PasswordDigest")
    end

    test "combined header respects TTL option" do
      combined =
        WSSecurity.username_token_with_timestamp(
          @valid_username,
          @valid_password,
          ttl: 900
        )

      created_str = get_in(combined, ["wsse:Security", "wsu:Timestamp", "wsu:Created"])
      expires_str = get_in(combined, ["wsse:Security", "wsu:Timestamp", "wsu:Expires"])

      {:ok, created, _} = DateTime.from_iso8601(created_str)
      {:ok, expires, _} = DateTime.from_iso8601(expires_str)

      diff = DateTime.diff(expires, created)
      assert diff == 900
    end

    test "DynamicClient works with combined header", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      combined_header =
        Header.username_token_with_timestamp(
          @valid_username,
          @valid_password,
          ttl: 300
        )

      {:ok, response} =
        Lather.DynamicClient.call(
          client,
          "SecureEcho",
          %{"message" => "combined auth test"},
          headers: [combined_header]
        )

      assert Map.has_key?(response, "echo")
    end
  end

  # ============================================================================
  # Test: Authentication failure - wrong password
  # ============================================================================

  describe "Authentication failure - wrong password" do
    setup do
      start_test_server(:text_password, username: @valid_username, password: @valid_password)
    end

    test "wrong password is rejected", %{base_url: base_url} do
      security_header = WSSecurity.username_token(@valid_username, "wrong_password")

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 1, "b" => 1},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
      assert String.contains?(response.body, "FailedAuthentication") or
               String.contains?(response.body, "invalid")
    end

    test "wrong username is rejected", %{base_url: base_url} do
      security_header = WSSecurity.username_token("wrong_user", @valid_password)

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 1, "b" => 1},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
      assert String.contains?(response.body, "FailedAuthentication") or
               String.contains?(response.body, "invalid")
    end

    test "wrong both username and password are rejected", %{base_url: base_url} do
      security_header = WSSecurity.username_token("wrong_user", "wrong_password")

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 1, "b" => 1},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
    end

    test "wrong digest password is rejected" do
      # Stop current server and start one expecting digest
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      SecurityConfig.set(:digest_password, username: @valid_username, password: @valid_password)
      {:ok, server_pid} = Bandit.start_link(plug: SecureRouter, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      security_header =
        WSSecurity.username_token(
          @valid_username,
          "wrong_password",
          password_type: :digest
        )

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 1, "b" => 1},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", envelope)

      assert response.status == 500
      assert String.contains?(response.body, "FailedAuthentication") or
               String.contains?(response.body, "digest")
    end
  end

  # ============================================================================
  # Test: Authentication failure - missing header
  # ============================================================================

  describe "Authentication failure - missing header" do
    setup do
      start_test_server(:text_password, username: @valid_username, password: @valid_password)
    end

    test "request without security header is rejected", %{base_url: base_url} do
      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 1, "b" => 1},
          headers: [],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
      assert String.contains?(response.body, "Security") or
               String.contains?(response.body, "required")
    end

    test "request with empty security header is rejected", %{base_url: base_url} do
      empty_security = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => @wsse_ns,
          "@xmlns:wsu" => @wsu_ns
        }
      }

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 1, "b" => 1},
          headers: [empty_security],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
    end

    test "request with incomplete UsernameToken is rejected", %{base_url: base_url} do
      # UsernameToken without password
      incomplete_security = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => @wsse_ns,
          "@xmlns:wsu" => @wsu_ns,
          "wsse:UsernameToken" => %{
            "wsse:Username" => @valid_username
            # Missing password
          }
        }
      }

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureAdd",
          %{"a" => 1, "b" => 1},
          headers: [incomplete_security],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
    end
  end

  # ============================================================================
  # Test: Authentication failure - expired timestamp
  # ============================================================================

  describe "Authentication failure - expired timestamp" do
    setup do
      start_test_server(:require_timestamp, reject_expired: true)
    end

    test "expired timestamp is rejected", %{base_url: base_url} do
      now = DateTime.utc_now()
      # 2 minutes ago
      created = DateTime.add(now, -120, :second)
      # 1 minute ago (expired)
      expires = DateTime.add(now, -60, :second)

      expired_timestamp = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => @wsse_ns,
          "@xmlns:wsu" => @wsu_ns,
          "wsu:Timestamp" => %{
            "wsu:Created" => DateTime.to_iso8601(created),
            "wsu:Expires" => DateTime.to_iso8601(expires)
          }
        }
      }

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "expired test"},
          headers: [expired_timestamp],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
      assert String.contains?(response.body, "Expired") or
               String.contains?(response.body, "expired")
    end

    test "timestamp that just expired is rejected", %{base_url: base_url} do
      now = DateTime.utc_now()
      # 30 seconds ago
      created = DateTime.add(now, -30, :second)
      # 1 second ago (just expired)
      expires = DateTime.add(now, -1, :second)

      just_expired_timestamp = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => @wsse_ns,
          "@xmlns:wsu" => @wsu_ns,
          "wsu:Timestamp" => %{
            "wsu:Created" => DateTime.to_iso8601(created),
            "wsu:Expires" => DateTime.to_iso8601(expires)
          }
        }
      }

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "just expired test"},
          headers: [just_expired_timestamp],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
    end

    test "future timestamp is accepted", %{base_url: base_url} do
      timestamp_header = WSSecurity.timestamp(ttl: 300)

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "valid timestamp"},
          headers: [timestamp_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 200
    end

    test "timestamp missing Created element is rejected", %{base_url: base_url} do
      now = DateTime.utc_now()
      expires = DateTime.add(now, 300, :second)

      invalid_timestamp = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => @wsse_ns,
          "@xmlns:wsu" => @wsu_ns,
          "wsu:Timestamp" => %{
            # Missing Created
            "wsu:Expires" => DateTime.to_iso8601(expires)
          }
        }
      }

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "missing created"},
          headers: [invalid_timestamp],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
    end

    test "timestamp missing Expires element is rejected", %{base_url: base_url} do
      now = DateTime.utc_now()

      invalid_timestamp = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => @wsse_ns,
          "@xmlns:wsu" => @wsu_ns,
          "wsu:Timestamp" => %{
            "wsu:Created" => DateTime.to_iso8601(now)
            # Missing Expires
          }
        }
      }

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "missing expires"},
          headers: [invalid_timestamp],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
    end

    test "missing timestamp when required is rejected", %{base_url: base_url} do
      # Send request without any timestamp
      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "no timestamp"},
          headers: [],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 500
      assert String.contains?(response.body, "Timestamp") or
               String.contains?(response.body, "required") or
               String.contains?(response.body, "Security")
    end
  end

  # ============================================================================
  # Test: Header module compatibility
  # ============================================================================

  describe "Header module compatibility" do
    setup do
      start_test_server(:username_with_timestamp, username: @valid_username, password: @valid_password)
    end

    test "Header.username_token produces same structure as WSSecurity.username_token" do
      ws_token = WSSecurity.username_token("user", "pass")
      header_token = Header.username_token("user", "pass")

      # Both should have the same top-level keys
      assert Map.keys(ws_token) == Map.keys(header_token)

      # Both should have wsse:Security with wsse:UsernameToken
      assert Map.has_key?(ws_token["wsse:Security"], "wsse:UsernameToken")
      assert Map.has_key?(header_token["wsse:Security"], "wsse:UsernameToken")
    end

    test "Header.timestamp produces same structure as WSSecurity.timestamp" do
      ws_ts = WSSecurity.timestamp()
      header_ts = Header.timestamp()

      # Both should have the same top-level keys
      assert Map.keys(ws_ts) == Map.keys(header_ts)

      # Both should have wsse:Security with wsu:Timestamp
      assert Map.has_key?(ws_ts["wsse:Security"], "wsu:Timestamp")
      assert Map.has_key?(header_ts["wsse:Security"], "wsu:Timestamp")
    end

    test "Header.username_token_with_timestamp produces same structure as WSSecurity" do
      ws_combined = WSSecurity.username_token_with_timestamp("user", "pass")
      header_combined = Header.username_token_with_timestamp("user", "pass")

      ws_security = ws_combined["wsse:Security"]
      header_security = header_combined["wsse:Security"]

      assert Map.has_key?(ws_security, "wsse:UsernameToken")
      assert Map.has_key?(ws_security, "wsu:Timestamp")
      assert Map.has_key?(header_security, "wsse:UsernameToken")
      assert Map.has_key?(header_security, "wsu:Timestamp")
    end

    test "Header.merge_headers can combine WS-Security with custom headers" do
      security_header = Header.username_token(@valid_username, @valid_password)
      session_header = Header.session("session-12345")

      merged = Header.merge_headers([security_header, session_header])

      assert Map.has_key?(merged, "wsse:Security")
      assert Map.has_key?(merged, "SessionId")
    end

    test "merged headers work in actual request", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      combined_header =
        Header.username_token_with_timestamp(
          @valid_username,
          @valid_password,
          ttl: 300
        )

      {:ok, response} =
        Lather.DynamicClient.call(
          client,
          "SecureAdd",
          %{"a" => 11, "b" => 22},
          headers: [combined_header]
        )

      assert Map.has_key?(response, "result")
    end
  end

  # ============================================================================
  # Test: Special characters in credentials
  # ============================================================================

  describe "Special characters in credentials" do
    setup do
      start_test_server(:text_password, username: "user@domain.com", password: "p@ss&word<>\"'")
    end

    test "special characters in username are handled correctly", %{base_url: base_url} do
      security_header = WSSecurity.username_token("user@domain.com", "p@ss&word<>\"'")

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "special chars test"},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      {:ok, response} = make_soap_request(base_url, envelope)

      assert response.status == 200
    end

    test "XML special characters are properly escaped in envelope" do
      security_header = WSSecurity.username_token("user", "pass<>&\"'")

      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          "SecureEcho",
          %{"message" => "test"},
          headers: [security_header],
          namespace: "http://test.example.com/secure"
        )

      # The envelope should contain escaped characters
      assert String.contains?(envelope, "&lt;") or String.contains?(envelope, "&gt;")
    end
  end

  # ============================================================================
  # Helper functions
  # ============================================================================

  defp start_test_server(validation_mode, opts) do
    {:ok, _} = Application.ensure_all_started(:lather)

    port = Enum.random(10000..60000)
    SecurityConfig.set(validation_mode, opts)
    {:ok, server_pid} = Bandit.start_link(plug: SecureRouter, port: port, scheme: :http)

    on_exit(fn ->
      try do
        GenServer.stop(server_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    Process.sleep(50)

    {:ok, port: port, base_url: "http://localhost:#{port}/soap", server_pid: server_pid}
  end

  defp make_soap_request(url, body) do
    request = Finch.build(:post, url, [{"content-type", "text/xml; charset=utf-8"}], body)

    case Finch.request(request, Lather.Finch) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body, headers: response.headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
