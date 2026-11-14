defmodule Lather.Auth.TokenManager do
  @moduledoc """
  GenServer-based issuer for JWT access tokens with refresh and revocation.

  Tokens are standard HS256 JWTs (see `Lather.Auth.JWT`) carrying an `exp`
  claim and a `jti` identifier. The manager tracks revoked `jti`s so a
  refreshed (or manually revoked) token stops validating even before its
  expiry.

  ## Examples

      {:ok, manager} = Lather.Auth.TokenManager.start_link(secret: "s3cret", ttl: 60)

      token = Lather.Auth.TokenManager.issue(manager, %{"sub" => "alice"})
      {:ok, claims} = Lather.Auth.TokenManager.validate(manager, token)

      new_token = Lather.Auth.TokenManager.refresh(manager, token)
      Lather.Auth.TokenManager.validate(manager, token)
      # {:error, :revoked}

  """

  use GenServer

  alias Lather.Auth.JWT

  @doc """
  Starts the token manager.

  ## Options

    * `:name` - registered name (default `Lather.Auth.TokenManager`)
    * `:secret` - HMAC secret (required)
    * `:ttl` - token lifetime in seconds (default 3600)
    * `:refresh_grace` - seconds after expiry for which a refresh token is
      still accepted (default 0)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    secret = Keyword.get(opts, :secret)

    unless is_binary(secret) do
      raise ArgumentError, "TokenManager requires a :secret option"
    end

    state = %{
      secret: secret,
      ttl: Keyword.get(opts, :ttl, 3600),
      refresh_grace: Keyword.get(opts, :refresh_grace, 0),
      revoked: MapSet.new()
    }

    {:ok, state}
  end

  @doc """
  Issues a new token for the given claims.

  Adds `exp` (now + ttl), `iat`, and a random `jti` claim.
  """
  @spec issue(GenServer.server(), map()) :: String.t()
  def issue(manager, claims \\ %{}) do
    GenServer.call(manager, {:issue, claims})
  end

  @doc """
  Validates a token: signature, expiry, and revocation status.
  """
  @spec validate(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def validate(manager, token) do
    GenServer.call(manager, {:validate, token})
  end

  @doc """
  Issues a fresh token from a valid (or recently expired) token, revoking
  the old one.

  The claims of the old token are carried over (its `exp`/`iat`/`jti` are
  replaced).
  """
  @spec refresh(GenServer.server(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def refresh(manager, token) do
    GenServer.call(manager, {:refresh, token})
  end

  @doc """
  Revokes a token (by value) so it no longer validates.
  """
  @spec revoke(GenServer.server(), String.t()) :: :ok
  def revoke(manager, token) do
    GenServer.call(manager, {:revoke, token})
  end

  @doc """
  Number of tokens currently revoked by this manager.
  """
  @spec revoked_count(GenServer.server()) :: non_neg_integer()
  def revoked_count(manager) do
    GenServer.call(manager, :revoked_count)
  end

  @impl true
  def handle_call({:issue, claims}, _from, state) do
    token = build_token(claims, state)
    {:reply, token, state}
  end

  def handle_call({:validate, token}, _from, state) do
    case JWT.verify(token, state.secret) do
      {:ok, claims} ->
        if MapSet.member?(state.revoked, claims["jti"]) do
          {:reply, {:error, :revoked}, state}
        else
          {:reply, {:ok, claims}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:refresh, token}, _from, state) do
    claims = extract_refreshable_claims(token, state)

    case claims do
      {:ok, base_claims} ->
        new_token = build_token(base_claims, state)

        {:reply, {:ok, new_token},
         %{state | revoked: MapSet.put(state.revoked, token_jti(token))}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:revoke, token}, _from, state) do
    jti = token_jti(token)

    if jti == nil do
      {:reply, {:error, :invalid_token}, state}
    else
      {:reply, :ok, %{state | revoked: MapSet.put(state.revoked, jti)}}
    end
  end

  def handle_call(:revoked_count, _from, state) do
    {:reply, MapSet.size(state.revoked), state}
  end

  defp build_token(claims, state) do
    now = :os.system_time(:second)

    claims =
      claims
      |> Map.delete("exp")
      |> Map.delete("iat")
      |> Map.delete("jti")

    claims =
      claims
      |> Map.put("exp", now + state.ttl)
      |> Map.put("jti", random_jti())

    JWT.token(claims, state.secret)
  end

  defp extract_refreshable_claims(token, state) do
    parts = String.split(token, ".")

    case parts do
      [header, payload, signature] ->
        expected =
          :crypto.mac(:hmac, :sha256, state.secret, header <> "." <> payload)
          |> Base.encode64()
          |> String.replace("+", "-")
          |> String.replace("/", "_")
          |> String.trim_trailing("=")

        if signature != expected do
          {:error, :invalid_signature}
        else
          case decode_payload(payload) do
            {:ok, claims} ->
              exp = Map.get(claims, "exp")

              if exp == nil or exp + state.refresh_grace >= :os.system_time(:second) do
                {:ok, Map.take(claims, ["sub", "role", "scope", "aud"])}
              else
                {:error, :expired}
              end

            :error ->
              {:error, :malformed_payload}
          end
        end

      _ ->
        {:error, :malformed_token}
    end
  end

  defp decode_payload(payload) do
    padded =
      case rem(String.length(payload), 4) do
        0 -> payload
        n -> payload <> String.duplicate("=", 4 - n)
      end

    decoded =
      padded
      |> String.replace("-", "+")
      |> String.replace("_", "/")
      |> Base.decode64()

    case decoded do
      {:ok, json} -> Jason.decode(json)
      :error -> :error
    end
  end

  defp token_jti(token) do
    case String.split(token, ".") do
      [_, payload | _] ->
        case decode_payload(payload) do
          {:ok, claims} -> Map.get(claims, "jti")
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp random_jti do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64()
  end
end
