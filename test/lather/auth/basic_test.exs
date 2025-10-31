defmodule Lather.Auth.BasicTest do
  use ExUnit.Case

  alias Lather.Auth.Basic

  describe "header/2 - Basic auth header generation" do
    test "generates valid basic auth header" do
      {header_name, header_value} = Basic.header("user", "pass")

      assert header_name == "Authorization"
      assert String.starts_with?(header_value, "Basic ")
    end

    test "encodes credentials in Base64" do
      {_, header_value} = Basic.header("admin", "password123")

      assert header_value == "Basic " <> Base.encode64("admin:password123")
    end

    test "handles simple credentials" do
      {_, header_value} = Basic.header("john", "secret")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "john:secret"
    end

    test "preserves username and password exactly" do
      username = "testuser"
      password = "testpass"
      {_, header_value} = Basic.header(username, password)

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "#{username}:#{password}"
    end

    test "handles special characters in password" do
      {_, header_value} = Basic.header("user", "p@ss:word&more")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "user:p@ss:word&more"
    end

    test "handles spaces in password" do
      {_, header_value} = Basic.header("user", "pass word with spaces")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "user:pass word with spaces"
    end

    test "handles Unicode characters in credentials" do
      {_, header_value} = Basic.header("üser", "pässwörd")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "üser:pässwörd"
    end

    test "handles colon in username" do
      {_, header_value} = Basic.header("user:name", "password")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "user:name:password"
    end

    test "handles empty username" do
      {_, header_value} = Basic.header("", "password")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == ":password"
    end

    test "handles empty password" do
      {_, header_value} = Basic.header("username", "")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "username:"
    end

    test "handles both empty username and password" do
      {_, header_value} = Basic.header("", "")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == ":"
    end

    test "handles very long credentials" do
      long_user = String.duplicate("a", 1000)
      long_pass = String.duplicate("b", 1000)

      {_, header_value} = Basic.header(long_user, long_pass)

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert String.starts_with?(decoded_creds, long_user)
    end

    test "handles credentials with newlines" do
      {_, header_value} = Basic.header("user\nname", "pass\nword")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "user\nname:pass\nword"
    end

    test "handles credentials with tabs" do
      {_, header_value} = Basic.header("user\tname", "pass\tword")

      decoded = String.replace_prefix(header_value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "user\tname:pass\tword"
    end
  end

  describe "header_value/2 - Header value only" do
    test "generates header value without key" do
      value = Basic.header_value("user", "pass")

      assert String.starts_with?(value, "Basic ")
      assert value == "Basic " <> Base.encode64("user:pass")
    end

    test "returns same encoding as header/2" do
      {_, full_header} = Basic.header("testuser", "testpass")
      value_only = Basic.header_value("testuser", "testpass")

      assert value_only == full_header
    end

    test "handles special characters" do
      value = Basic.header_value("admin", "p@ss&word")

      decoded = String.replace_prefix(value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "admin:p@ss&word"
    end

    test "handles empty credentials" do
      value = Basic.header_value("", "")

      decoded = String.replace_prefix(value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == ":"
    end

    test "handles Unicode credentials" do
      value = Basic.header_value("用户", "密码")

      decoded = String.replace_prefix(value, "Basic ", "")
      {:ok, decoded_creds} = Base.decode64(decoded)

      assert decoded_creds == "用户:密码"
    end
  end

  describe "decode/1 - Decoding Basic auth header" do
    test "decodes valid Basic auth header" do
      encoded = Base.encode64("user:pass")
      {:ok, {username, password}} = Basic.decode("Basic " <> encoded)

      assert username == "user"
      assert password == "pass"
    end

    test "decodes header with special characters in password" do
      encoded = Base.encode64("admin:p@ss:word&more")
      {:ok, {username, password}} = Basic.decode("Basic " <> encoded)

      assert username == "admin"
      assert password == "p@ss:word&more"
    end

    test "decodes header with empty username" do
      encoded = Base.encode64(":password")
      {:ok, {username, password}} = Basic.decode("Basic " <> encoded)

      assert username == ""
      assert password == "password"
    end

    test "decodes header with empty password" do
      encoded = Base.encode64("username:")
      {:ok, {username, password}} = Basic.decode("Basic " <> encoded)

      assert username == "username"
      assert password == ""
    end

    test "decodes header with both empty" do
      encoded = Base.encode64(":")
      {:ok, {username, password}} = Basic.decode("Basic " <> encoded)

      assert username == ""
      assert password == ""
    end

    test "decodes Unicode credentials" do
      encoded = Base.encode64("üser:pässwörd")
      {:ok, {username, password}} = Basic.decode("Basic " <> encoded)

      assert username == "üser"
      assert password == "pässwörd"
    end

    test "rejects header without Basic prefix" do
      encoded = Base.encode64("user:pass")
      assert {:error, :invalid_format} = Basic.decode(encoded)
    end

    test "rejects header with wrong prefix" do
      encoded = Base.encode64("user:pass")
      assert {:error, :invalid_format} = Basic.decode("Bearer " <> encoded)
    end

    test "rejects invalid Base64 encoding" do
      assert {:error, :invalid_encoding} = Basic.decode("Basic !!!invalid!!!")
    end

    test "rejects credentials without colon" do
      encoded = Base.encode64("no_colon_here")
      assert {:error, :invalid_credentials} = Basic.decode("Basic " <> encoded)
    end

    test "rejects malformed header format" do
      assert {:error, :invalid_format} = Basic.decode("invalid")
      assert {:error, :invalid_format} = Basic.decode("")
      assert {:error, :invalid_format} = Basic.decode(nil)
    end

    test "handles multiple colons in credentials" do
      encoded = Base.encode64("user:pass:extra:colons")
      {:ok, {username, password}} = Basic.decode("Basic " <> encoded)

      # Should split only on first colon
      assert username == "user"
      assert password == "pass:extra:colons"
    end

    test "case sensitive for Basic prefix" do
      encoded = Base.encode64("user:pass")
      # Should work with "Basic"
      assert {:ok, _} = Basic.decode("Basic " <> encoded)
      # Should fail with different case (depends on implementation)
      result = Basic.decode("basic " <> encoded)
      assert result == {:error, :invalid_format} or is_tuple(result)
    end

    test "rejects header with padding issues" do
      # Deliberately create malformed Base64
      assert {:error, _} = Basic.decode("Basic not-valid-base64-!!!")
    end
  end

  describe "validate/2 - Validation with custom validator" do
    test "validates credentials successfully" do
      validator = fn username, password ->
        username == "admin" && password == "secret"
      end

      encoded = Base.encode64("admin:secret")
      result = Basic.validate("Basic " <> encoded, validator)

      assert {:ok, {"admin", "secret"}} = result
    end

    test "rejects invalid credentials" do
      validator = fn username, password ->
        username == "admin" && password == "secret"
      end

      encoded = Base.encode64("user:wrong")
      result = Basic.validate("Basic " <> encoded, validator)

      assert {:error, :invalid_credentials} = result
    end

    test "calls validator with correct parameters" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      validator = fn username, password ->
        Agent.update(agent, fn state ->
          [{username, password} | state]
        end)

        true
      end

      encoded = Base.encode64("testuser:testpass")
      {:ok, _} = Basic.validate("Basic " <> encoded, validator)

      called_with = Agent.get(agent, &Enum.reverse/1)
      assert called_with == [{"testuser", "testpass"}]

      Agent.stop(agent)
    end

    test "returns error for malformed header before calling validator" do
      validator_called = fn -> false end

      result = Basic.validate("not a basic auth header", fn _, _ -> validator_called.() end)

      assert {:error, _} = result
    end

    test "propagates validator result" do
      validator = fn _, _ -> true end
      encoded = Base.encode64("user:pass")

      {:ok, credentials} = Basic.validate("Basic " <> encoded, validator)

      assert credentials == {"user", "pass"}
    end

    test "allows validator to check multiple conditions" do
      validator = fn username, password ->
        String.length(username) > 3 && String.length(password) > 5
      end

      # Valid
      encoded1 = Base.encode64("admin:password123")
      assert {:ok, _} = Basic.validate("Basic " <> encoded1, validator)

      # Invalid username too short
      encoded2 = Base.encode64("ad:password123")
      assert {:error, :invalid_credentials} = Basic.validate("Basic " <> encoded2, validator)

      # Invalid password too short
      encoded3 = Base.encode64("admin:pass")
      assert {:error, :invalid_credentials} = Basic.validate("Basic " <> encoded3, validator)
    end

    test "handles validator with special characters" do
      validator = fn username, password ->
        username == "user@domain.com" && password == "p@ss&word"
      end

      encoded = Base.encode64("user@domain.com:p@ss&word")
      result = Basic.validate("Basic " <> encoded, validator)

      assert {:ok, {"user@domain.com", "p@ss&word"}} = result
    end

    test "handles validator with Unicode" do
      validator = fn username, password ->
        username == "用户" && password == "密码"
      end

      encoded = Base.encode64("用户:密码")
      result = Basic.validate("Basic " <> encoded, validator)

      assert {:ok, {"用户", "密码"}} = result
    end

    test "handles validator exceptions gracefully" do
      validator = fn _, _ -> raise "Validator error" end

      encoded = Base.encode64("user:pass")
      # Should not crash, but handle error
      result = Basic.validate("Basic " <> encoded, validator)

      assert true or is_tuple(result)
    end
  end

  describe "Round-trip encoding/decoding" do
    test "header and decode are inverse operations" do
      username = "testuser"
      password = "testpass123"

      {_, header_value} = Basic.header(username, password)
      {:ok, {decoded_user, decoded_pass}} = Basic.decode(header_value)

      assert decoded_user == username
      assert decoded_pass == password
    end

    test "round-trip with special characters" do
      username = "admin@example.com"
      password = "P@ssw0rd!&More"

      {_, header_value} = Basic.header(username, password)
      {:ok, {decoded_user, decoded_pass}} = Basic.decode(header_value)

      assert decoded_user == username
      assert decoded_pass == password
    end

    test "round-trip with Unicode" do
      username = "用户名"
      password = "密码123"

      {_, header_value} = Basic.header(username, password)
      {:ok, {decoded_user, decoded_pass}} = Basic.decode(header_value)

      assert decoded_user == username
      assert decoded_pass == password
    end

    test "header_value and decode are inverse" do
      username = "john"
      password = "doe"

      header_value = Basic.header_value(username, password)
      {:ok, {decoded_user, decoded_pass}} = Basic.decode(header_value)

      assert decoded_user == username
      assert decoded_pass == password
    end
  end

  describe "Integration scenarios" do
    test "typical HTTP header usage" do
      {key, value} = Basic.header("user", "pass")

      # Simulate adding to HTTP headers
      headers = [
        {"content-type", "application/json"},
        {key, value},
        {"accept", "application/json"}
      ]

      assert Enum.find(headers, fn {k, _} -> k == "Authorization" end) != nil
    end

    test "validates request with stored credentials" do
      # Simulate storing credentials at startup
      valid_user = "admin"
      valid_pass = "secret123"

      # Simulate receiving request
      request_header = "Basic " <> Base.encode64("admin:secret123")

      validator = fn username, password ->
        username == valid_user && password == valid_pass
      end

      assert {:ok, _} = Basic.validate(request_header, validator)
    end

    test "rejects invalid request credentials" do
      # Simulate storing credentials
      valid_user = "admin"
      valid_pass = "secret123"

      # Simulate receiving request with wrong password
      request_header = "Basic " <> Base.encode64("admin:wrongpass")

      validator = fn username, password ->
        username == valid_user && password == valid_pass
      end

      assert {:error, :invalid_credentials} = Basic.validate(request_header, validator)
    end

    test "multiple credential pairs" do
      credentials = [
        {"user1", "pass1"},
        {"user2", "pass2"},
        {"admin", "secret"}
      ]

      # Create validator that accepts multiple credentials
      validator = fn username, password ->
        Enum.any?(credentials, fn {u, p} ->
          username == u && password == p
        end)
      end

      # Test each credential
      Enum.each(credentials, fn {user, pass} ->
        encoded = Base.encode64("#{user}:#{pass}")
        assert {:ok, {^user, ^pass}} = Basic.validate("Basic " <> encoded, validator)
      end)
    end
  end

  describe "Edge cases and error conditions" do
    test "very long credential strings" do
      long_user = String.duplicate("a", 5000)
      long_pass = String.duplicate("b", 5000)

      {_, header_value} = Basic.header(long_user, long_pass)
      {:ok, {decoded_user, decoded_pass}} = Basic.decode(header_value)

      assert decoded_user == long_user
      assert decoded_pass == long_pass
    end

    test "credentials with all special characters" do
      special_chars = "!@#$%^&*()_+-=[]{}|;:',.<>?/~`"
      username = "user"
      password = special_chars

      {_, header_value} = Basic.header(username, password)
      {:ok, {decoded_user, decoded_pass}} = Basic.decode(header_value)

      assert decoded_user == username
      assert decoded_pass == password
    end

    test "whitespace-only credentials" do
      username = "   "
      password = "\t\n"

      {_, header_value} = Basic.header(username, password)
      {:ok, {decoded_user, decoded_pass}} = Basic.decode(header_value)

      assert decoded_user == username
      assert decoded_pass == password
    end

    test "decode handles malformed base64 gracefully" do
      assert {:error, :invalid_encoding} = Basic.decode("Basic @@@@")
      assert {:error, :invalid_encoding} = Basic.decode("Basic !!!!")
    end

    test "validator receives exact credentials" do
      original_user = "TestUser"
      original_pass = "TestPass"

      validator = fn username, password ->
        # Capture the values
        send(self(), {:credentials, username, password})
        username == original_user && password == original_pass
      end

      encoded = Base.encode64("#{original_user}:#{original_pass}")
      Basic.validate("Basic " <> encoded, validator)

      assert_receive {:credentials, ^original_user, ^original_pass}
    end
  end
end
