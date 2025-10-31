defmodule Lather.Auth.WSSecurity do
  @moduledoc """
  WS-Security implementation for SOAP authentication.

  This module provides WS-Security authentication mechanisms including:
  - UsernameToken authentication
  - Timestamp elements
  - Nonce generation
  - Password digest generation
  """

  @doc """
  Creates a WS-Security UsernameToken header.

  ## Parameters

    * `username` - The username for authentication
    * `password` - The password for authentication
    * `options` - Additional options
      * `:password_type` - `:digest` or `:text` (default: `:text`)
      * `:include_nonce` - Whether to include a nonce (default: `true` for digest)
      * `:include_created` - Whether to include timestamp (default: `true`)

  ## Examples

      iex> Lather.Auth.WSSecurity.username_token("admin", "password")
      %{
        "Security" => %{
          "UsernameToken" => %{
            "Username" => "admin",
            "Password" => %{"#text" => "password", "@Type" => "...PasswordText"}
          }
        }
      }
  """
  @spec username_token(String.t(), String.t(), keyword()) :: map()
  def username_token(username, password, options \\ []) do
    password_type = Keyword.get(options, :password_type, :text)
    include_nonce = Keyword.get(options, :include_nonce, password_type == :digest)
    include_created = Keyword.get(options, :include_created, true)

    nonce = if include_nonce, do: generate_nonce(), else: nil
    created = if include_created, do: generate_timestamp(), else: nil

    password_element = build_password_element(password, password_type, nonce, created)

    username_token = %{
      "@xmlns:wsse" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
      "@xmlns:wsu" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd",
      "wsse:Username" => username,
      "wsse:Password" => password_element
    }

    username_token = if nonce do
      Map.put(username_token, "wsse:Nonce", %{
        "@EncodingType" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary",
        "#text" => nonce
      })
    else
      username_token
    end

    username_token = if created do
      Map.put(username_token, "wsu:Created", created)
    else
      username_token
    end

    %{
      "wsse:Security" => %{
        "@xmlns:wsse" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
        "@xmlns:wsu" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd",
        "wsse:UsernameToken" => username_token
      }
    }
  end

  @doc """
  Creates a WS-Security timestamp header.

  ## Parameters

    * `options` - Options for the timestamp
      * `:ttl` - Time to live in seconds (default: 300)

  ## Examples

      iex> Lather.Auth.WSSecurity.timestamp()
      %{
        "Security" => %{
          "Timestamp" => %{
            "Created" => "2023-01-01T12:00:00Z",
            "Expires" => "2023-01-01T12:05:00Z"
          }
        }
      }
  """
  @spec timestamp(keyword()) :: map()
  def timestamp(options \\ []) do
    ttl = Keyword.get(options, :ttl, 300)

    now = DateTime.utc_now()
    expires = DateTime.add(now, ttl, :second)

    created = DateTime.to_iso8601(now)
    expires_str = DateTime.to_iso8601(expires)

    %{
      "wsse:Security" => %{
        "@xmlns:wsse" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
        "@xmlns:wsu" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd",
        "wsu:Timestamp" => %{
          "wsu:Created" => created,
          "wsu:Expires" => expires_str
        }
      }
    }
  end

  @doc """
  Creates a combined WS-Security header with both UsernameToken and Timestamp.

  ## Parameters

    * `username` - The username for authentication
    * `password` - The password for authentication
    * `options` - Combined options for both UsernameToken and Timestamp

  ## Examples

      iex> Lather.Auth.WSSecurity.username_token_with_timestamp("admin", "password")
      %{
        "Security" => %{
          "UsernameToken" => %{...},
          "Timestamp" => %{...}
        }
      }
  """
  @spec username_token_with_timestamp(String.t(), String.t(), keyword()) :: map()
  def username_token_with_timestamp(username, password, options \\ []) do
    password_type = Keyword.get(options, :password_type, :text)
    include_nonce = Keyword.get(options, :include_nonce, password_type == :digest)
    ttl = Keyword.get(options, :ttl, 300)

    nonce = if include_nonce, do: generate_nonce(), else: nil
    created = generate_timestamp()

    password_element = build_password_element(password, password_type, nonce, created)

    username_token = %{
      "@wsu:Id" => "UsernameToken-" <> generate_id(),
      "wsse:Username" => username,
      "wsse:Password" => password_element
    }

    username_token = if nonce do
      Map.put(username_token, "wsse:Nonce", %{
        "@EncodingType" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary",
        "#text" => nonce
      })
    else
      username_token
    end

    username_token = Map.put(username_token, "wsu:Created", created)

    now = DateTime.utc_now()
    expires = DateTime.add(now, ttl, :second)
    expires_str = DateTime.to_iso8601(expires)

    timestamp = %{
      "@wsu:Id" => "Timestamp-" <> generate_id(),
      "wsu:Created" => created,
      "wsu:Expires" => expires_str
    }

    %{
      "wsse:Security" => %{
        "@xmlns:wsse" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
        "@xmlns:wsu" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd",
        "wsu:Timestamp" => timestamp,
        "wsse:UsernameToken" => username_token
      }
    }
  end

  # Private helper functions

  defp build_password_element(password, :text, _nonce, _created) do
    %{
      "@Type" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText",
      "#text" => password
    }
  end

  defp build_password_element(password, :digest, nonce, created) when is_binary(nonce) and is_binary(created) do
    digest = generate_password_digest(password, nonce, created)
    %{
      "@Type" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest",
      "#text" => digest
    }
  end

  defp build_password_element(password, :digest, _nonce, _created) do
    # Fallback to text if nonce or created is missing
    build_password_element(password, :text, nil, nil)
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16)
    |> Base.encode64()
  end

  defp generate_timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  defp generate_password_digest(password, nonce, created) do
    nonce_decoded = Base.decode64!(nonce)

    # Password digest = Base64(SHA1(nonce + created + password))
    digest_input = nonce_decoded <> created <> password

    :crypto.hash(:sha, digest_input)
    |> Base.encode64()
  end
end
