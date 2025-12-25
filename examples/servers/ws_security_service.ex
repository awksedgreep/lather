defmodule Examples.Servers.WSSecurityService do
  @moduledoc """
  WS-Security protected SOAP service demonstration.

  This example demonstrates how to implement server-side WS-Security validation
  for incoming SOAP requests. It covers:

  - WS-Security header parsing and validation
  - UsernameToken extraction and verification
  - Timestamp validation (rejecting expired requests)
  - Password digest verification
  - Custom authentication Plug for SOAP services
  - Proper SOAP fault responses for unauthorized requests

  ## WS-Security Overview

  WS-Security (Web Services Security) is an OASIS standard that provides
  mechanisms for securing SOAP messages. Key concepts include:

  ### UsernameToken Profile

  The UsernameToken profile provides username/password authentication.
  Two password types are supported:

  - **PasswordText**: Password sent in plaintext (requires transport security)
  - **PasswordDigest**: Password hashed with nonce and timestamp
    - Digest = Base64(SHA1(nonce + created + password))

  ### Timestamp Element

  Timestamps prevent replay attacks by including:
  - `Created`: When the message was created
  - `Expires`: When the message expires (typically 5 minutes)

  ### Nonce

  A random value included in digest calculations to prevent replay attacks.
  Servers should track used nonces within the timestamp validity window.

  ## Usage

  Start the service with the WS-Security authentication plug:

      # In Phoenix router
      scope "/soap" do
        pipe_through :api

        post "/secure", Lather.Server.Plug,
          service: Examples.Servers.WSSecurityService,
          auth_handler: Examples.Servers.WSSecurityService.AuthHandler
      end

  ## Security Considerations

  1. Always use HTTPS in production to protect credentials
  2. For PasswordText, transport-level encryption is mandatory
  3. Store only password hashes, never plaintext passwords
  4. Implement nonce tracking to prevent replay attacks
  5. Use reasonable timestamp windows (e.g., 5 minutes)
  6. Log authentication failures for security monitoring

  ## Example WS-Security Header (client-side)

      # Using Lather.Auth.WSSecurity to create headers:
      security_header = Lather.Auth.WSSecurity.username_token_with_timestamp(
        "admin",
        "secret",
        password_type: :digest,
        ttl: 300
      )

  ## Example SOAP Request with WS-Security

      <?xml version="1.0"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Header>
          <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
                         xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
            <wsu:Timestamp>
              <wsu:Created>2024-01-15T10:30:00Z</wsu:Created>
              <wsu:Expires>2024-01-15T10:35:00Z</wsu:Expires>
            </wsu:Timestamp>
            <wsse:UsernameToken>
              <wsse:Username>admin</wsse:Username>
              <wsse:Password Type="...#PasswordDigest">digest_here</wsse:Password>
              <wsse:Nonce EncodingType="...#Base64Binary">nonce_here</wsse:Nonce>
              <wsu:Created>2024-01-15T10:30:00Z</wsu:Created>
            </wsse:UsernameToken>
          </wsse:Security>
        </soap:Header>
        <soap:Body>
          <GetSecureData>
            <resourceId>secret-123</resourceId>
          </GetSecureData>
        </soap:Body>
      </soap:Envelope>
  """

  use Lather.Server

  @namespace "http://examples.com/security"
  @service_name "WSSecurityService"

  # Define response types
  soap_type "SecureResource" do
    description "A protected resource"

    element "id", :string, required: true, description: "Resource identifier"
    element "name", :string, required: true, description: "Resource name"
    element "classification", :string, required: true, description: "Security classification"
    element "data", :string, required: true, description: "Secure data payload"
    element "accessedAt", :dateTime, required: true, description: "Access timestamp"
    element "accessedBy", :string, required: true, description: "Username who accessed"
  end

  soap_type "AuditEntry" do
    description "Security audit log entry"

    element "timestamp", :dateTime, required: true, description: "When the action occurred"
    element "username", :string, required: true, description: "User who performed the action"
    element "action", :string, required: true, description: "Action performed"
    element "resource", :string, required: false, description: "Resource affected"
    element "result", :string, required: true, description: "Result of the action"
  end

  # Protected operation - Get secure data
  soap_operation "GetSecureData" do
    description "Retrieves protected resource data. Requires WS-Security authentication."

    input do
      parameter "resourceId", :string, required: true, description: "ID of the resource to retrieve"
    end

    output do
      parameter "resource", "SecureResource", description: "The protected resource"
    end

    soap_action "http://examples.com/security/GetSecureData"
  end

  def get_secure_data(%{"resourceId" => resource_id} = params) do
    # In a real implementation, the authenticated user would be passed via conn.assigns
    # For this example, we simulate it
    username = Map.get(params, "__authenticated_user", "authenticated_user")

    case SecureResourceStore.get(resource_id) do
      {:ok, resource} ->
        # Add access metadata
        enriched_resource = Map.merge(resource, %{
          "accessedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "accessedBy" => username
        })
        {:ok, %{"resource" => enriched_resource}}

      {:error, :not_found} ->
        soap_fault("Client", "Resource not found", %{resourceId: resource_id})

      {:error, :access_denied} ->
        soap_fault("Client", "Access denied to resource", %{resourceId: resource_id})
    end
  end

  # Protected operation - Create secure data
  soap_operation "CreateSecureData" do
    description "Creates a new protected resource. Requires WS-Security authentication."

    input do
      parameter "name", :string, required: true, description: "Resource name"
      parameter "classification", :string, required: true, description: "Security classification (public, internal, confidential, secret)"
      parameter "data", :string, required: true, description: "Data payload"
    end

    output do
      parameter "resourceId", :string, description: "ID of the created resource"
      parameter "resource", "SecureResource", description: "The created resource"
    end

    soap_action "http://examples.com/security/CreateSecureData"
  end

  def create_secure_data(%{"name" => name, "classification" => classification, "data" => data} = params) do
    username = Map.get(params, "__authenticated_user", "authenticated_user")

    # Validate classification level
    valid_classifications = ["public", "internal", "confidential", "secret"]
    unless classification in valid_classifications do
      return soap_fault("Client", "Invalid classification level", %{
        provided: classification,
        valid_values: valid_classifications
      })
    end

    case SecureResourceStore.create(name, classification, data, username) do
      {:ok, resource} ->
        {:ok, %{
          "resourceId" => resource["id"],
          "resource" => resource
        }}

      {:error, reason} ->
        soap_fault("Server", "Failed to create resource: #{reason}")
    end
  end

  # Protected operation - Get audit log
  soap_operation "GetAuditLog" do
    description "Retrieves security audit log. Requires WS-Security authentication with admin role."

    input do
      parameter "startDate", :dateTime, required: false, description: "Start of date range"
      parameter "endDate", :dateTime, required: false, description: "End of date range"
      parameter "username", :string, required: false, description: "Filter by username"
      parameter "maxEntries", :int, required: false, description: "Maximum entries to return"
    end

    output do
      parameter "entries", "AuditEntry", max_occurs: "unbounded", description: "Audit log entries"
      parameter "totalCount", :int, description: "Total number of matching entries"
    end

    soap_action "http://examples.com/security/GetAuditLog"
  end

  def get_audit_log(params) do
    # In production, check for admin role from authenticated user
    max_entries = params |> Map.get("maxEntries", "100") |> parse_integer(100)

    entries = AuditLog.get_entries(
      start_date: params["startDate"],
      end_date: params["endDate"],
      username: params["username"],
      limit: max_entries
    )

    {:ok, %{
      "entries" => entries,
      "totalCount" => length(entries)
    }}
  end

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
  defp parse_integer(value, _default) when is_integer(value), do: value
  defp parse_integer(_, default), do: default
end

# =============================================================================
# WS-Security Authentication Handler
# =============================================================================

defmodule Examples.Servers.WSSecurityService.AuthHandler do
  @moduledoc """
  WS-Security authentication handler for Plug integration.

  This module implements the authentication handler interface expected by
  `Lather.Server.Plug` and provides comprehensive WS-Security validation.

  ## Features

  - Extracts WS-Security headers from SOAP envelope
  - Validates UsernameToken credentials
  - Verifies timestamps are within acceptable window
  - Supports both PasswordText and PasswordDigest authentication
  - Tracks nonces to prevent replay attacks
  - Returns proper SOAP faults for authentication failures

  ## Configuration

  Configure via application environment:

      config :my_app, Examples.Servers.WSSecurityService.AuthHandler,
        timestamp_tolerance: 300,  # 5 minutes
        users: %{
          "admin" => %{password_hash: "hashed_password", roles: ["admin"]},
          "user" => %{password_hash: "hashed_password", roles: ["user"]}
        }

  ## Usage with Lather.Server.Plug

      post "/secure", Lather.Server.Plug,
        service: Examples.Servers.WSSecurityService,
        auth_handler: Examples.Servers.WSSecurityService.AuthHandler
  """

  require Logger

  # WS-Security XML namespaces
  @wsse_ns "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
  @wsu_ns "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"

  # Password type URIs
  @password_text "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText"
  @password_digest "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest"

  # Default timestamp tolerance in seconds (5 minutes)
  @default_timestamp_tolerance 300

  @doc """
  Authenticates an incoming SOAP request by validating WS-Security headers.

  Returns `{:ok, conn}` with authenticated user info in assigns, or
  `{:error, reason}` if authentication fails.
  """
  def authenticate(conn) do
    with {:ok, body} <- read_body(conn),
         {:ok, security_header} <- extract_security_header(body),
         {:ok, credentials} <- extract_credentials(security_header),
         :ok <- validate_timestamp(security_header),
         :ok <- validate_nonce(credentials),
         {:ok, user} <- verify_credentials(credentials) do

      # Log successful authentication
      AuditLog.log_authentication(credentials.username, :success)

      # Add authenticated user to connection assigns
      conn = Plug.Conn.assign(conn, :authenticated_user, user)
      conn = Plug.Conn.assign(conn, :ws_security_credentials, credentials)

      {:ok, conn}
    else
      {:error, reason} = error ->
        # Log authentication failure
        log_auth_failure(reason)
        error
    end
  end

  # Read the request body (for header extraction)
  defp read_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> {:ok, body}
      {:more, _partial, _conn} -> {:error, :body_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts the WS-Security header from a SOAP envelope.

  The security header typically contains:
  - Timestamp (Created/Expires)
  - UsernameToken (Username, Password, Nonce, Created)
  """
  def extract_security_header(soap_body) when is_binary(soap_body) do
    # Parse the SOAP envelope and extract the Security header
    # This is a simplified implementation - production code would use
    # a proper XML parser like SweetXml or Saxy

    cond do
      # Check for wsse:Security element
      String.contains?(soap_body, "Security") ->
        parse_security_header(soap_body)

      true ->
        {:error, :missing_security_header}
    end
  end

  # Parse the WS-Security header from XML
  # In production, use a proper XML parser. This is simplified for demonstration.
  defp parse_security_header(xml) do
    # Extract key elements using pattern matching
    # Note: This is a simplified parser. Use SweetXml or Saxy in production.

    security_header = %{
      timestamp: extract_timestamp(xml),
      username_token: extract_username_token(xml)
    }

    if security_header.username_token do
      {:ok, security_header}
    else
      {:error, :invalid_security_header}
    end
  end

  # Extract Timestamp element
  defp extract_timestamp(xml) do
    created = extract_element_value(xml, "Created")
    expires = extract_element_value(xml, "Expires")

    if created do
      %{
        created: created,
        expires: expires
      }
    else
      nil
    end
  end

  # Extract UsernameToken element
  defp extract_username_token(xml) do
    username = extract_element_value(xml, "Username")
    password = extract_element_value(xml, "Password")
    nonce = extract_element_value(xml, "Nonce")
    created = extract_element_value(xml, "UsernameToken", "Created") ||
              extract_element_value(xml, "Created")

    # Determine password type from attribute
    password_type = cond do
      String.contains?(xml, "PasswordDigest") -> :digest
      String.contains?(xml, "PasswordText") -> :text
      true -> :text  # Default to text
    end

    if username && password do
      %{
        username: username,
        password: password,
        password_type: password_type,
        nonce: nonce,
        created: created
      }
    else
      nil
    end
  end

  # Simple XML element extraction (for demonstration)
  # In production, use SweetXml: xpath(xml, ~x"//wsse:Username/text()"s)
  defp extract_element_value(xml, element_name) do
    # Handle both prefixed and non-prefixed elements
    patterns = [
      ~r/<(?:wsse:|wsu:)?#{element_name}[^>]*>([^<]+)<\/(?:wsse:|wsu:)?#{element_name}>/,
      ~r/<#{element_name}[^>]*>([^<]+)<\/#{element_name}>/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, xml) do
        [_, value] -> String.trim(value)
        _ -> nil
      end
    end)
  end

  defp extract_element_value(xml, _parent, element_name) do
    extract_element_value(xml, element_name)
  end

  @doc """
  Extracts credentials from the parsed security header.
  """
  def extract_credentials(%{username_token: nil}) do
    {:error, :missing_credentials}
  end

  def extract_credentials(%{username_token: token}) do
    {:ok, %{
      username: token.username,
      password: token.password,
      password_type: token.password_type,
      nonce: token.nonce,
      created: token.created
    }}
  end

  @doc """
  Validates the timestamp in the security header.

  Checks that:
  1. Timestamp is present
  2. Created time is not in the future (with tolerance)
  3. Message has not expired
  4. Created time is within acceptable window
  """
  def validate_timestamp(%{timestamp: nil}) do
    # Timestamp is optional but recommended
    # In strict mode, return {:error, :missing_timestamp}
    :ok
  end

  def validate_timestamp(%{timestamp: timestamp}) do
    now = DateTime.utc_now()
    tolerance = get_timestamp_tolerance()

    with {:ok, created} <- parse_datetime(timestamp.created),
         {:ok, expires} <- parse_datetime(timestamp.expires) do

      created_with_tolerance = DateTime.add(created, -tolerance, :second)
      expires_with_tolerance = DateTime.add(expires, tolerance, :second)

      cond do
        # Created time is too far in the future
        DateTime.compare(created_with_tolerance, now) == :gt ->
          {:error, :timestamp_in_future}

        # Message has expired
        DateTime.compare(now, expires_with_tolerance) == :gt ->
          {:error, :message_expired}

        # Created time is too old (beyond reasonable window)
        DateTime.diff(now, created, :second) > tolerance * 2 ->
          {:error, :timestamp_too_old}

        true ->
          :ok
      end
    else
      {:error, :invalid_datetime} ->
        {:error, :invalid_timestamp_format}
    end
  end

  defp parse_datetime(nil), do: {:error, :invalid_datetime}
  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_datetime}
    end
  end

  @doc """
  Validates the nonce to prevent replay attacks.

  In production, this should:
  1. Check if nonce was already used within the timestamp validity window
  2. Store the nonce with expiration time
  3. Use a distributed cache (Redis, ETS with distribution) for multi-node setups
  """
  def validate_nonce(%{nonce: nil, password_type: :digest}) do
    # Nonce is required for password digest
    {:error, :missing_nonce}
  end

  def validate_nonce(%{nonce: nil}) do
    # Nonce is optional for password text
    :ok
  end

  def validate_nonce(%{nonce: nonce, username: username}) do
    # Check if nonce was already used
    case NonceStore.check_and_store(username, nonce) do
      :ok -> :ok
      :already_used -> {:error, :nonce_already_used}
    end
  end

  @doc """
  Verifies the credentials against the user store.

  For PasswordDigest, recomputes the digest and compares.
  For PasswordText, compares the password directly (or hash).
  """
  def verify_credentials(%{username: username, password: password, password_type: :text}) do
    case UserStore.get_user(username) do
      {:ok, user} ->
        if verify_password_text(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end

      {:error, :not_found} ->
        # Use constant-time comparison to prevent timing attacks
        verify_password_text(password, "dummy_hash_for_timing")
        {:error, :invalid_credentials}
    end
  end

  def verify_credentials(%{
    username: username,
    password: digest,
    password_type: :digest,
    nonce: nonce,
    created: created
  }) do
    case UserStore.get_user(username) do
      {:ok, user} ->
        if verify_password_digest(digest, user.password, nonce, created) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end

      {:error, :not_found} ->
        # Prevent timing attacks
        verify_password_digest(digest, "dummy_password", nonce || "", created || "")
        {:error, :invalid_credentials}
    end
  end

  def verify_credentials(_) do
    {:error, :invalid_credentials}
  end

  # Verify password text (comparing against stored hash)
  defp verify_password_text(password, stored_hash) do
    # In production, use a proper password hashing library like Bcrypt or Argon2
    # This is a simplified example using SHA256
    computed_hash = :crypto.hash(:sha256, password) |> Base.encode64()
    secure_compare(computed_hash, stored_hash)
  end

  # Verify password digest
  # Digest = Base64(SHA1(nonce + created + password))
  defp verify_password_digest(received_digest, stored_password, nonce, created) do
    case Base.decode64(nonce) do
      {:ok, nonce_bytes} ->
        # Recompute the digest
        digest_input = nonce_bytes <> created <> stored_password
        computed_digest = :crypto.hash(:sha, digest_input) |> Base.encode64()
        secure_compare(computed_digest, received_digest)

      :error ->
        false
    end
  end

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  end
  defp secure_compare(_, _), do: false

  # Get timestamp tolerance from config
  defp get_timestamp_tolerance do
    Application.get_env(:my_app, __MODULE__, [])
    |> Keyword.get(:timestamp_tolerance, @default_timestamp_tolerance)
  end

  # Log authentication failures
  defp log_auth_failure(reason) do
    Logger.warning("WS-Security authentication failed: #{inspect(reason)}")

    case reason do
      :missing_security_header ->
        AuditLog.log_authentication("unknown", :failure, "Missing WS-Security header")
      :invalid_credentials ->
        AuditLog.log_authentication("unknown", :failure, "Invalid credentials")
      :message_expired ->
        AuditLog.log_authentication("unknown", :failure, "Message expired")
      :nonce_already_used ->
        AuditLog.log_authentication("unknown", :failure, "Replay attack detected")
      _ ->
        AuditLog.log_authentication("unknown", :failure, to_string(reason))
    end
  end
end

# =============================================================================
# WS-Security Fault Builder
# =============================================================================

defmodule Examples.Servers.WSSecurityService.FaultBuilder do
  @moduledoc """
  Builds WS-Security specific SOAP faults.

  WS-Security failures should return appropriate fault codes and messages
  that help clients understand and resolve authentication issues without
  exposing sensitive security information.
  """

  @doc """
  Builds a SOAP fault for WS-Security authentication failures.

  ## Fault Codes

  - `wsse:InvalidSecurityToken` - Invalid or missing security token
  - `wsse:FailedAuthentication` - Authentication failed
  - `wsse:FailedCheck` - Signature or decryption check failed
  - `wsse:SecurityTokenUnavailable` - Referenced token not found
  - `wsse:MessageExpired` - Message timestamp expired

  ## Example Response

      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>wsse:FailedAuthentication</faultcode>
            <faultstring>Authentication failed</faultstring>
            <detail>
              <wsse:SecurityError>Invalid credentials provided</wsse:SecurityError>
            </detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
  """
  def build_security_fault(error_type, message \\ nil) do
    {fault_code, fault_string, detail} = case error_type do
      :missing_security_header ->
        {"wsse:InvalidSecurityToken",
         "Security header missing",
         "The SOAP message does not contain a WS-Security header"}

      :invalid_security_header ->
        {"wsse:InvalidSecurityToken",
         "Invalid security token",
         "The WS-Security header is malformed or incomplete"}

      :missing_credentials ->
        {"wsse:InvalidSecurityToken",
         "Credentials missing",
         "UsernameToken not found in security header"}

      :invalid_credentials ->
        {"wsse:FailedAuthentication",
         "Authentication failed",
         "The provided credentials are invalid"}

      :message_expired ->
        {"wsse:MessageExpired",
         "Message expired",
         "The message timestamp has expired"}

      :timestamp_in_future ->
        {"wsse:InvalidSecurityToken",
         "Invalid timestamp",
         "Message timestamp is in the future"}

      :timestamp_too_old ->
        {"wsse:MessageExpired",
         "Timestamp too old",
         "Message timestamp is outside acceptable window"}

      :nonce_already_used ->
        {"wsse:FailedCheck",
         "Replay attack detected",
         "The nonce has already been used"}

      :missing_nonce ->
        {"wsse:InvalidSecurityToken",
         "Nonce required",
         "Password digest authentication requires a nonce"}

      _ ->
        {"wsse:FailedAuthentication",
         "Authentication failed",
         message || "An authentication error occurred"}
    end

    build_fault_xml(fault_code, fault_string, detail)
  end

  defp build_fault_xml(fault_code, fault_string, detail) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                   xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
      <soap:Body>
        <soap:Fault>
          <faultcode>#{fault_code}</faultcode>
          <faultstring>#{fault_string}</faultstring>
          <detail>
            <wsse:SecurityError>#{detail}</wsse:SecurityError>
          </detail>
        </soap:Fault>
      </soap:Body>
    </soap:Envelope>
    """
  end
end

# =============================================================================
# Supporting Mock Modules (for demonstration)
# =============================================================================

defmodule SecureResourceStore do
  @moduledoc """
  Mock secure resource store for demonstration.
  In production, this would be backed by a database with proper access controls.
  """

  def get("secret-123") do
    {:ok, %{
      "id" => "secret-123",
      "name" => "Confidential Report",
      "classification" => "confidential",
      "data" => "This is sensitive data that requires authentication to access."
    }}
  end

  def get("internal-456") do
    {:ok, %{
      "id" => "internal-456",
      "name" => "Internal Memo",
      "classification" => "internal",
      "data" => "Internal company information."
    }}
  end

  def get("restricted-789") do
    {:error, :access_denied}
  end

  def get(_), do: {:error, :not_found}

  def create(name, classification, data, created_by) do
    id = generate_id()
    resource = %{
      "id" => id,
      "name" => name,
      "classification" => classification,
      "data" => data,
      "accessedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "accessedBy" => created_by
    }
    {:ok, resource}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

defmodule UserStore do
  @moduledoc """
  Mock user store for authentication.
  In production, this would query a database and use proper password hashing.
  """

  @users %{
    "admin" => %{
      username: "admin",
      # In production, use Bcrypt/Argon2. This is SHA256 of "admin_password"
      password_hash: "jGl25bVBBBW96Qi9Te4V37Fnqchz/Eu4qB9vKrRIqRg=",
      # Plain password stored for digest verification (in production, don't store plain passwords)
      password: "admin_password",
      roles: ["admin", "user"],
      email: "admin@example.com"
    },
    "user" => %{
      username: "user",
      password_hash: "XohImNooBHFR0OVvjcYpJ3NgPQ1qq73WKhHvch0VQtg=",
      password: "user_password",
      roles: ["user"],
      email: "user@example.com"
    },
    "service" => %{
      username: "service",
      password_hash: "n4bQgYhMfWWaL+qgxVrQFaO/TxsrC4Is0V1sFbDwCgg=",
      password: "service_password",
      roles: ["service"],
      email: "service@example.com"
    }
  }

  def get_user(username) do
    case Map.get(@users, username) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def authenticate(username, password) do
    case get_user(username) do
      {:ok, user} ->
        if verify_password(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_password}
        end
      error -> error
    end
  end

  defp verify_password(password, hash) do
    computed = :crypto.hash(:sha256, password) |> Base.encode64()
    computed == hash
  end
end

defmodule NonceStore do
  @moduledoc """
  Mock nonce store for replay attack prevention.

  In production, use:
  - ETS table with TTL-based cleanup
  - Redis with expiration
  - Database with scheduled cleanup

  Nonces should be stored with the timestamp and automatically
  expired after the timestamp validity window passes.
  """

  # Simple in-memory store (not suitable for production)
  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def check_and_store(username, nonce) do
    # Ensure agent is started (for demo purposes)
    ensure_started()

    key = "#{username}:#{nonce}"

    Agent.get_and_update(__MODULE__, fn nonces ->
      if Map.has_key?(nonces, key) do
        {:already_used, nonces}
      else
        # Store with timestamp for cleanup
        {:ok, Map.put(nonces, key, DateTime.utc_now())}
      end
    end)
  end

  def cleanup_expired(max_age_seconds \\ 600) do
    ensure_started()
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_seconds, :second)

    Agent.update(__MODULE__, fn nonces ->
      nonces
      |> Enum.reject(fn {_key, timestamp} ->
        DateTime.compare(timestamp, cutoff) == :lt
      end)
      |> Map.new()
    end)
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil -> start_link()
      _pid -> :ok
    end
  end
end

defmodule AuditLog do
  @moduledoc """
  Mock audit logging for security events.
  In production, this would persist to a secure audit log database.
  """

  require Logger

  def log_authentication(username, result, details \\ nil) do
    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      event_type: "authentication",
      username: username,
      result: result,
      details: details
    }

    # In production, persist to audit database
    Logger.info("AUDIT: #{inspect(entry)}")
    :ok
  end

  def log_access(username, resource_id, action, result) do
    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      event_type: "access",
      username: username,
      resource: resource_id,
      action: action,
      result: result
    }

    Logger.info("AUDIT: #{inspect(entry)}")
    :ok
  end

  def get_entries(opts \\ []) do
    # Mock implementation returning sample entries
    limit = Keyword.get(opts, :limit, 100)

    sample_entries = [
      %{
        "timestamp" => "2024-01-15T10:30:00Z",
        "username" => "admin",
        "action" => "authentication",
        "resource" => nil,
        "result" => "success"
      },
      %{
        "timestamp" => "2024-01-15T10:30:05Z",
        "username" => "admin",
        "action" => "GetSecureData",
        "resource" => "secret-123",
        "result" => "success"
      },
      %{
        "timestamp" => "2024-01-15T10:25:00Z",
        "username" => "unknown",
        "action" => "authentication",
        "resource" => nil,
        "result" => "failure"
      }
    ]

    Enum.take(sample_entries, limit)
  end
end

# =============================================================================
# Example Usage and Testing
# =============================================================================

defmodule Examples.Servers.WSSecurityService.Demo do
  @moduledoc """
  Demonstration of how to use the WS-Security service.

  ## Running the Demo

      # Start the demo
      Examples.Servers.WSSecurityService.Demo.run()

  ## Manual Testing with curl

      # Get WSDL
      curl http://localhost:4000/soap/secure?wsdl

      # Call with WS-Security header
      curl -X POST http://localhost:4000/soap/secure \\
        -H "Content-Type: text/xml" \\
        -d @ws_security_request.xml
  """

  alias Lather.Auth.WSSecurity

  @doc """
  Demonstrates creating a WS-Security protected request.
  """
  def create_secure_request(username, password, operation, params) do
    # Generate WS-Security header with username token and timestamp
    security_header = WSSecurity.username_token_with_timestamp(
      username,
      password,
      password_type: :digest,
      ttl: 300
    )

    IO.puts("Generated WS-Security Header:")
    IO.inspect(security_header, pretty: true)

    # In a real scenario, this would be sent via Lather client
    # with the security header included
    {:ok, security_header, operation, params}
  end

  @doc """
  Demonstrates the authentication flow.
  """
  def demonstrate_auth_flow do
    IO.puts("\n=== WS-Security Authentication Flow Demo ===\n")

    # 1. Create security header
    IO.puts("1. Creating WS-Security header with digest password...")
    security_header = WSSecurity.username_token_with_timestamp(
      "admin",
      "admin_password",
      password_type: :digest,
      ttl: 300
    )
    IO.inspect(security_header, pretty: true, limit: :infinity)

    # 2. Simulate header extraction
    IO.puts("\n2. Server extracts and validates security header...")
    IO.puts("   - Checking timestamp validity")
    IO.puts("   - Extracting username token")
    IO.puts("   - Verifying password digest")
    IO.puts("   - Checking nonce for replay attacks")

    # 3. Show what happens on failure
    IO.puts("\n3. Example failure scenarios:")
    IO.puts("   - Missing header -> SOAP Fault: wsse:InvalidSecurityToken")
    IO.puts("   - Expired message -> SOAP Fault: wsse:MessageExpired")
    IO.puts("   - Invalid credentials -> SOAP Fault: wsse:FailedAuthentication")
    IO.puts("   - Reused nonce -> SOAP Fault: wsse:FailedCheck")

    :ok
  end

  @doc """
  Shows example SOAP request with WS-Security.
  """
  def show_example_request do
    IO.puts("\n=== Example SOAP Request with WS-Security ===\n")

    request = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                   xmlns:sec="http://examples.com/security">
      <soap:Header>
        <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
                       xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
          <wsu:Timestamp wsu:Id="Timestamp-1">
            <wsu:Created>#{DateTime.utc_now() |> DateTime.to_iso8601()}</wsu:Created>
            <wsu:Expires>#{DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_iso8601()}</wsu:Expires>
          </wsu:Timestamp>
          <wsse:UsernameToken wsu:Id="UsernameToken-1">
            <wsse:Username>admin</wsse:Username>
            <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">
              <!-- Base64(SHA1(nonce + created + password)) -->
              dGVzdF9kaWdlc3Q=
            </wsse:Password>
            <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">
              #{:crypto.strong_rand_bytes(16) |> Base.encode64()}
            </wsse:Nonce>
            <wsu:Created>#{DateTime.utc_now() |> DateTime.to_iso8601()}</wsu:Created>
          </wsse:UsernameToken>
        </wsse:Security>
      </soap:Header>
      <soap:Body>
        <sec:GetSecureData>
          <sec:resourceId>secret-123</sec:resourceId>
        </sec:GetSecureData>
      </soap:Body>
    </soap:Envelope>
    """

    IO.puts(request)
    :ok
  end

  @doc """
  Shows example SOAP fault for authentication failure.
  """
  def show_example_fault do
    IO.puts("\n=== Example SOAP Fault for Authentication Failure ===\n")

    fault = Examples.Servers.WSSecurityService.FaultBuilder.build_security_fault(:invalid_credentials)
    IO.puts(fault)
    :ok
  end

  def run do
    demonstrate_auth_flow()
    show_example_request()
    show_example_fault()
  end
end
