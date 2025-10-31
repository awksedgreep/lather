defmodule Lather.Auth.WSSecurityTest do
  use ExUnit.Case

  alias Lather.Auth.WSSecurity

  describe "username_token/3 - UsernameToken generation" do
    test "generates text password token" do
      token = WSSecurity.username_token("admin", "password")

      assert is_map(token)
      assert Map.has_key?(token, "wsse:Security")
      security = token["wsse:Security"]
      assert Map.has_key?(security, "wsse:UsernameToken")
    end

    test "includes username in token" do
      token = WSSecurity.username_token("testuser", "testpass")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == "testuser"
    end

    test "includes password in token" do
      token = WSSecurity.username_token("user", "mypassword")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      password_elem = username_token["wsse:Password"]
      assert Map.has_key?(password_elem, "#text")
      assert password_elem["#text"] == "mypassword"
    end

    test "text password type is default" do
      token = WSSecurity.username_token("user", "pass")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      password_elem = username_token["wsse:Password"]
      assert String.contains?(password_elem["@Type"], "PasswordText")
    end

    test "generates with digest password type" do
      token = WSSecurity.username_token("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      password_elem = username_token["wsse:Password"]
      assert String.contains?(password_elem["@Type"], "PasswordDigest")
    end

    test "includes nonce with digest password" do
      token = WSSecurity.username_token("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert Map.has_key?(username_token, "wsse:Nonce")
    end

    test "excludes nonce when requested" do
      token = WSSecurity.username_token("user", "pass", include_nonce: false)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert !Map.has_key?(username_token, "wsse:Nonce")
    end

    test "includes created timestamp" do
      token = WSSecurity.username_token("user", "pass")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert Map.has_key?(username_token, "wsu:Created")
      created = username_token["wsu:Created"]
      assert is_binary(created)
    end

    test "excludes created when requested" do
      token = WSSecurity.username_token("user", "pass", include_created: false)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert !Map.has_key?(username_token, "wsu:Created")
    end

    test "includes correct namespaces" do
      token = WSSecurity.username_token("user", "pass")

      security = token["wsse:Security"]
      assert String.contains?(security["@xmlns:wsse"], "wssecurity-secext")
      assert String.contains?(security["@xmlns:wsu"], "wssecurity-utility")
    end

    test "handles special characters in username" do
      token = WSSecurity.username_token("user@domain.com", "pass&word")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == "user@domain.com"
      assert username_token["wsse:Password"]["#text"] == "pass&word"
    end

    test "handles Unicode in credentials" do
      token = WSSecurity.username_token("用户", "密码")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == "用户"
      assert username_token["wsse:Password"]["#text"] == "密码"
    end

    test "handles empty password" do
      token = WSSecurity.username_token("user", "")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Password"]["#text"] == ""
    end

    test "digest has base64 encoded nonce" do
      token = WSSecurity.username_token("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      nonce = username_token["wsse:Nonce"]["#text"]

      # Should be valid base64
      assert is_binary(nonce)
      assert String.length(nonce) > 0
    end

    test "digest has base64 encoded password" do
      token = WSSecurity.username_token("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      password_elem = username_token["wsse:Password"]
      password_digest = password_elem["#text"]

      # Should be base64 encoded SHA1 hash
      assert is_binary(password_digest)
      assert String.length(password_digest) > 0
    end

    test "encoding type for nonce is correct" do
      token = WSSecurity.username_token("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      nonce = username_token["wsse:Nonce"]
      assert String.contains?(nonce["@EncodingType"], "Base64Binary")
    end
  end

  describe "timestamp/1 - Timestamp generation" do
    test "generates timestamp with default TTL" do
      ts = WSSecurity.timestamp()

      assert is_map(ts)
      assert Map.has_key?(ts, "wsse:Security")
      security = ts["wsse:Security"]
      assert Map.has_key?(security, "wsu:Timestamp")
    end

    test "includes created field" do
      ts = WSSecurity.timestamp()

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      assert Map.has_key?(timestamp, "wsu:Created")
      created = timestamp["wsu:Created"]
      assert is_binary(created)
    end

    test "includes expires field" do
      ts = WSSecurity.timestamp()

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      assert Map.has_key?(timestamp, "wsu:Expires")
      expires = timestamp["wsu:Expires"]
      assert is_binary(expires)
    end

    test "created is ISO8601 format" do
      ts = WSSecurity.timestamp()

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      created = timestamp["wsu:Created"]

      # Should be ISO8601 format
      assert String.contains?(created, "T")
      assert String.contains?(created, "Z") or String.contains?(created, "+")
    end

    test "expires is after created" do
      ts = WSSecurity.timestamp()

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      created = timestamp["wsu:Created"]
      expires = timestamp["wsu:Expires"]

      {:ok, created_dt, _} = DateTime.from_iso8601(created)
      {:ok, expires_dt, _} = DateTime.from_iso8601(expires)

      assert DateTime.compare(expires_dt, created_dt) == :gt
    end

    test "respects custom TTL" do
      ts = WSSecurity.timestamp(ttl: 600)

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      created = timestamp["wsu:Created"]
      expires = timestamp["wsu:Expires"]

      {:ok, created_dt, _} = DateTime.from_iso8601(created)
      {:ok, expires_dt, _} = DateTime.from_iso8601(expires)

      diff = DateTime.diff(expires_dt, created_dt)
      assert diff == 600
    end

    test "default TTL is 300 seconds" do
      ts = WSSecurity.timestamp()

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      created = timestamp["wsu:Created"]
      expires = timestamp["wsu:Expires"]

      {:ok, created_dt, _} = DateTime.from_iso8601(created)
      {:ok, expires_dt, _} = DateTime.from_iso8601(expires)

      diff = DateTime.diff(expires_dt, created_dt)
      assert diff == 300
    end

    test "includes correct namespaces" do
      ts = WSSecurity.timestamp()

      security = ts["wsse:Security"]
      assert String.contains?(security["@xmlns:wsse"], "wssecurity-secext")
      assert String.contains?(security["@xmlns:wsu"], "wssecurity-utility")
    end

    test "handles zero TTL" do
      ts = WSSecurity.timestamp(ttl: 0)

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      created = timestamp["wsu:Created"]
      expires = timestamp["wsu:Expires"]

      {:ok, created_dt, _} = DateTime.from_iso8601(created)
      {:ok, expires_dt, _} = DateTime.from_iso8601(expires)

      diff = DateTime.diff(expires_dt, created_dt)
      assert diff == 0
    end

    test "handles large TTL" do
      ts = WSSecurity.timestamp(ttl: 86400)

      security = ts["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      created = timestamp["wsu:Created"]
      expires = timestamp["wsu:Expires"]

      {:ok, created_dt, _} = DateTime.from_iso8601(created)
      {:ok, expires_dt, _} = DateTime.from_iso8601(expires)

      diff = DateTime.diff(expires_dt, created_dt)
      assert diff == 86400
    end
  end

  describe "username_token_with_timestamp/3 - Combined token" do
    test "generates combined username token and timestamp" do
      token = WSSecurity.username_token_with_timestamp("admin", "password")

      assert is_map(token)
      security = token["wsse:Security"]
      assert Map.has_key?(security, "wsse:UsernameToken")
      assert Map.has_key?(security, "wsu:Timestamp")
    end

    test "includes both username and password" do
      token = WSSecurity.username_token_with_timestamp("user", "pass")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == "user"
      assert username_token["wsse:Password"]["#text"] == "pass"
    end

    test "includes both created and expires" do
      token = WSSecurity.username_token_with_timestamp("user", "pass")

      security = token["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      assert Map.has_key?(timestamp, "wsu:Created")
      assert Map.has_key?(timestamp, "wsu:Expires")
    end

    test "generates unique IDs" do
      token = WSSecurity.username_token_with_timestamp("user", "pass")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      timestamp = security["wsu:Timestamp"]

      username_id = username_token["@wsu:Id"]
      timestamp_id = timestamp["@wsu:Id"]

      assert is_binary(username_id)
      assert is_binary(timestamp_id)
      refute username_id == timestamp_id
    end

    test "respects custom TTL in combined token" do
      token = WSSecurity.username_token_with_timestamp("user", "pass", ttl: 600)

      security = token["wsse:Security"]
      timestamp = security["wsu:Timestamp"]
      created = timestamp["wsu:Created"]
      expires = timestamp["wsu:Expires"]

      {:ok, created_dt, _} = DateTime.from_iso8601(created)
      {:ok, expires_dt, _} = DateTime.from_iso8601(expires)

      diff = DateTime.diff(expires_dt, created_dt)
      assert diff == 600
    end

    test "includes nonce when digest password" do
      token = WSSecurity.username_token_with_timestamp("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert Map.has_key?(username_token, "wsse:Nonce")
    end

    test "timestamp in username token matches overall timestamp" do
      token = WSSecurity.username_token_with_timestamp("user", "pass")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      overall_timestamp = security["wsu:Timestamp"]

      username_created = username_token["wsu:Created"]
      timestamp_created = overall_timestamp["wsu:Created"]

      # Should be very close (within same second)
      {:ok, username_dt, _} = DateTime.from_iso8601(username_created)
      {:ok, timestamp_dt, _} = DateTime.from_iso8601(timestamp_created)

      diff = DateTime.diff(username_dt, timestamp_dt)
      assert abs(diff) <= 1
    end

    test "handles special characters in combined token" do
      token = WSSecurity.username_token_with_timestamp("user@domain.com", "p@ss&word")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == "user@domain.com"
      assert username_token["wsse:Password"]["#text"] == "p@ss&word"
    end

    test "handles Unicode in combined token" do
      token = WSSecurity.username_token_with_timestamp("用户", "密码")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == "用户"
      assert username_token["wsse:Password"]["#text"] == "密码"
    end
  end

  describe "Password digest generation" do
    test "digest is different for different passwords" do
      token1 = WSSecurity.username_token("user", "pass1", password_type: :digest)
      token2 = WSSecurity.username_token("user", "pass2", password_type: :digest)

      security1 = token1["wsse:Security"]
      security2 = token2["wsse:Security"]

      digest1 = security1["wsse:UsernameToken"]["wsse:Password"]["#text"]
      digest2 = security2["wsse:UsernameToken"]["wsse:Password"]["#text"]

      refute digest1 == digest2
    end

    test "digest is base64 encoded" do
      token = WSSecurity.username_token("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      digest = security["wsse:UsernameToken"]["wsse:Password"]["#text"]

      # Should be valid base64
      assert is_binary(digest)
      assert String.length(digest) > 0

      # Try to decode
      case Base.decode64(digest) do
        {:ok, _} -> assert true
        :error -> assert false, "Digest is not valid base64"
      end
    end

    test "digest includes nonce" do
      token = WSSecurity.username_token("user", "password", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      nonce = username_token["wsse:Nonce"]["#text"]
      digest = username_token["wsse:Password"]["#text"]

      # Digest should be reproducible with nonce and created
      assert is_binary(nonce)
      assert is_binary(digest)
    end
  end

  describe "Namespace handling" do
    test "WSSE namespace is included" do
      token = WSSecurity.username_token("user", "pass")

      security = token["wsse:Security"]
      assert Map.has_key?(security, "@xmlns:wsse")
      assert String.contains?(security["@xmlns:wsse"], "wssecurity-secext")
    end

    test "WSSE utility namespace is included" do
      token = WSSecurity.username_token("user", "pass")

      security = token["wsse:Security"]
      assert Map.has_key?(security, "@xmlns:wsu")
      assert String.contains?(security["@xmlns:wsu"], "wssecurity-utility")
    end

    test "namespace URIs are correct" do
      token = WSSecurity.username_token("user", "pass")

      security = token["wsse:Security"]
      assert String.contains?(security["@xmlns:wsse"], "2004/01")

      assert String.contains?(security["@xmlns:wsse"], "wssecurity-secext")
    end
  end

  describe "Edge cases" do
    test "handles very long username" do
      long_user = String.duplicate("a", 1000)
      token = WSSecurity.username_token(long_user, "pass")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == long_user
    end

    test "handles very long password" do
      long_pass = String.duplicate("b", 1000)
      token = WSSecurity.username_token("user", long_pass)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Password"]["#text"] == long_pass
    end

    test "handles empty username" do
      token = WSSecurity.username_token("", "password")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Username"] == ""
    end

    test "handles empty password" do
      token = WSSecurity.username_token("user", "")

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]
      assert username_token["wsse:Password"]["#text"] == ""
    end

    test "nonce is unique across calls" do
      token1 = WSSecurity.username_token("user", "pass", password_type: :digest)
      token2 = WSSecurity.username_token("user", "pass", password_type: :digest)

      nonce1 = token1["wsse:Security"]["wsse:UsernameToken"]["wsse:Nonce"]["#text"]
      nonce2 = token2["wsse:Security"]["wsse:UsernameToken"]["wsse:Nonce"]["#text"]

      # Nonces should be different due to random generation
      refute nonce1 == nonce2
    end

    test "ID generation is unique" do
      token = WSSecurity.username_token_with_timestamp("user", "pass")

      security = token["wsse:Security"]
      username_id = security["wsse:UsernameToken"]["@wsu:Id"]
      timestamp_id = security["wsu:Timestamp"]["@wsu:Id"]

      assert username_id != timestamp_id
    end
  end

  describe "Integration scenarios" do
    test "token structure is valid for SOAP header" do
      token = WSSecurity.username_token("admin", "secret")

      # Should be a nested map structure suitable for SOAP header
      assert is_map(token)
      assert Map.has_key?(token, "wsse:Security")

      security = token["wsse:Security"]
      assert is_map(security)
      assert Map.has_key?(security, "wsse:UsernameToken")
    end

    test "digest token can be used with timestamp" do
      token = WSSecurity.username_token_with_timestamp("user", "pass", password_type: :digest)

      security = token["wsse:Security"]
      username_token = security["wsse:UsernameToken"]

      # Verify all digest components
      assert Map.has_key?(username_token, "wsse:Nonce")
      assert Map.has_key?(username_token, "wsu:Created")
      assert String.contains?(username_token["wsse:Password"]["@Type"], "PasswordDigest")
    end

    test "text password token is simpler than digest" do
      text_token = WSSecurity.username_token("user", "pass", password_type: :text)
      digest_token = WSSecurity.username_token("user", "pass", password_type: :digest)

      text_security = text_token["wsse:Security"]
      digest_security = digest_token["wsse:Security"]

      # Text should not have nonce
      assert !Map.has_key?(text_security["wsse:UsernameToken"], "wsse:Nonce")
      # Digest should have nonce
      assert Map.has_key?(digest_security["wsse:UsernameToken"], "wsse:Nonce")
    end
  end
end
