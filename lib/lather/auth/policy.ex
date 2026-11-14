defmodule Lather.Auth.Policy do
  @moduledoc """
  Declarative security policies for Lather services.

  A policy is a map of requirements checked against the options passed to
  `Lather.Server.EnhancedPlug.init/1`. When a service declares a
  `:security_policy`, the plug validates its own configuration at startup
  and raises if the policy is not satisfied.

  ## Supported requirements

    * `require_auth: [:api_key, :jwt, :saml, :signature, :basic]` - each
      listed factor must be configured on the service
    * `min_factors: n` - at least `n` authentication factors configured
    * `max_body_size: n` - `:max_body_size` must not exceed `n` bytes
    * `require_encryption: true` - an `:encryption_key` must be configured

  ## Examples

      iex> Lather.Auth.Policy.validate([api_keys: ["k1"]], %{require_auth: [:api_key]})
      :ok

      iex> Lather.Auth.Policy.validate([], %{require_auth: [:api_key]})
      {:error, ["api_key authentication is required but not configured"]}

  """

  @doc """
  Validates service options against a policy.

  Returns `:ok` or `{:error, [violation, ...]}`.
  """
  @spec validate(keyword(), map()) :: :ok | {:error, [String.t()]}
  def validate(opts, policy) when is_list(opts) and is_map(policy) do
    violations =
      append_auth_violations(opts, policy) ++
        append_factor_violations(opts, policy) ++
        append_body_size_violation(opts, policy) ++
        append_encryption_violation(opts, policy)

    if violations == [] do
      :ok
    else
      {:error, violations}
    end
  end

  @doc """
  Like `validate/2` but raises `ArgumentError` on violations. Used by
  `Lather.Server.EnhancedPlug.init/1` when `:security_policy` is set.
  """
  @spec validate!(keyword(), map()) :: :ok
  def validate!(opts, policy) do
    case validate(opts, policy) do
      :ok ->
        :ok

      {:error, violations} ->
        raise ArgumentError,
              "security policy violated: " <> Enum.join(violations, "; ")
    end
  end

  defp configured_auth_factors(opts) do
    factors = []

    factors =
      if not is_nil(Keyword.get(opts, :api_keys)), do: factors ++ [:api_key], else: factors

    factors =
      if not is_nil(Keyword.get(opts, :jwt_secret)), do: factors ++ [:jwt], else: factors

    factors =
      if not is_nil(Keyword.get(opts, :saml_secret)), do: factors ++ [:saml], else: factors

    factors =
      if not is_nil(Keyword.get(opts, :verify_signature)),
        do: factors ++ [:signature],
        else: factors

    factors =
      if not is_nil(Keyword.get(opts, :auth_handler)), do: factors ++ [:basic], else: factors

    factors
  end

  defp append_auth_violations(opts, policy) do
    required = Map.get(policy, "require_auth") || Map.get(policy, :require_auth) || []
    configured = configured_auth_factors(opts)

    required
    |> Enum.map(fn factor ->
      f = if is_atom(factor), do: factor, else: String.to_atom(factor)

      if Enum.member?(configured, f) do
        nil
      else
        "#{f} authentication is required but not configured"
      end
    end)
    |> Enum.reject(&(&1 == nil))
  end

  defp append_factor_violations(opts, policy) do
    min = Map.get(policy, "min_factors") || Map.get(policy, :min_factors)

    if is_integer(min) and length(configured_auth_factors(opts)) < min do
      [
        "at least #{min} authentication factors are required, found #{length(configured_auth_factors(opts))}"
      ]
    else
      []
    end
  end

  defp append_body_size_violation(opts, policy) do
    max = Map.get(policy, "max_body_size") || Map.get(policy, :max_body_size)

    if is_integer(max) and Keyword.get(opts, :max_body_size, 0) > max do
      ["max_body_size exceeds the policy limit of #{max} bytes"]
    else
      []
    end
  end

  defp append_encryption_violation(opts, policy) do
    required = Map.get(policy, "require_encryption") || Map.get(policy, :require_encryption)

    if required && is_nil(Keyword.get(opts, :encryption_key)) do
      ["XML encryption is required but no encryption_key is configured"]
    else
      []
    end
  end
end
