defmodule Lather.Http.Pool do
  @moduledoc """
  Connection pool configuration for HTTP transport.

  Provides configuration and utilities for managing Finch connection pools
  optimized for SOAP requests.
  """

  @doc """
  Returns the default pool configuration for SOAP clients.

  Optimized for typical SOAP usage patterns with reasonable defaults
  for connection pooling, timeouts, and SSL settings.
  """
  @spec default_config() :: keyword()
  def default_config do
    [
      # Connection pool settings
      pool_timeout: 5_000,
      pool_max_idle_time: 30_000,

      # HTTP/2 settings
      http2_max_concurrent_streams: 1000,

      # SSL settings
      transport_opts: [
        verify: :verify_peer,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]
  end

  @doc """
  Creates a pool configuration for a specific endpoint.

  Allows customization of pool settings per endpoint, useful for
  services with different performance characteristics.
  """
  @spec config_for_endpoint(String.t(), keyword()) :: keyword()
  def config_for_endpoint(endpoint, overrides \\ []) do
    base_config = default_config()

    # Extract host for pool naming
    uri = URI.parse(endpoint)
    pool_name = String.to_atom("lather_pool_#{uri.host}")

    base_config
    |> Keyword.put(:name, pool_name)
    |> Keyword.merge(overrides)
  end

  @doc """
  Validates pool configuration options.
  """
  @spec validate_config(keyword()) :: :ok | {:error, String.t()}
  def validate_config(config) do
    with :ok <- validate_timeout(config[:pool_timeout]),
         :ok <- validate_timeout(config[:pool_max_idle_time]) do
      :ok
    end
  end

  defp validate_timeout(nil), do: :ok
  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, "timeout must be a positive integer"}
end
