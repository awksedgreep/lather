defmodule Lather.Auth.Certificate do
  @moduledoc """
  Client-certificate authentication for SOAP services.

  Clients present an X.509 certificate (PEM) in the HTTP header
  `X-Client-Certificate`. The server parses it with Erlang's `:public_key`
  and checks the subject common name, expiry, and fingerprint against the
  configured allowlist.

  ## Examples

      iex> {:ok, info} = Lather.Auth.Certificate.parse_pem(pem)
      iex> info.common_name
      "lather-client"

  """

  @doc """
  Parses a PEM certificate into `%{common_name:, serial:, not_before:,
  not_after:, fingerprint:}`.
  """
  @spec parse_pem(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_pem(pem) when is_binary(pem) do
    case pem_to_der(pem) do
      {:ok, der} ->
        cert = safe_decode(der)

        if is_tuple(cert) do
          {:ok,
           %{
             common_name: extract_cn(cert),
             serial: serial(cert),
             not_before: validity_start(cert),
             not_after: validity_end(cert),
             fingerprint: der_fingerprint(der)
           }}
        else
          {:error, :unable_to_parse_certificate}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  SHA-256 fingerprint (hex) of a PEM certificate.
  """
  @spec fingerprint(String.t()) :: String.t() | nil
  def fingerprint(pem) do
    case pem_to_der(pem) do
      {:ok, der} -> der_fingerprint(der)
      _ -> nil
    end
  end

  @doc """
  Validates a client certificate against a configured allowlist.

  `allowlist` is a map of common name -> expected PEM fingerprint, or a
  list of fingerprints.
  """
  @spec verify(String.t(), map() | [String.t()]) :: {:ok, map()} | {:error, term()}
  def verify(pem, allowlist) do
    case parse_pem(pem) do
      {:ok, info} ->
        now = :os.system_time(:second)

        cond do
          info.not_after != nil and info.not_after < now ->
            {:error, :expired}

          info.not_before != nil and info.not_before > now ->
            {:error, :not_yet_valid}

          allowed?(info, allowlist) ->
            {:ok, info}

          true ->
            {:error, :certificate_not_allowed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Convenience header for clients: `[{"x-client-certificate", base64(pem)}]`.

  PEM is base64-encoded so it is safe to send over HTTP/2 header values.
  """
  @spec header(String.t()) :: [{String.t(), String.t()}]
  def header(pem) do
    [{"x-client-certificate", Base.encode64(pem)}]
  end

  @doc """
  Extracts and decodes the client certificate PEM from HTTP headers.
  """
  @spec extract(list()) :: String.t() | nil
  def extract(headers) do
    Enum.find_value(headers, fn pair ->
      case pair do
        {name, value} ->
          if String.downcase(to_string(name)) == "x-client-certificate" do
            case Base.decode64(value) do
              {:ok, pem} -> pem
              :error -> value
            end
          end

        _ ->
          nil
      end
    end)
  end

  defp pem_to_der(pem) do
    body =
      pem
      |> String.split("\n")
      |> Enum.reject(fn line -> String.starts_with?(line, "-----") end)
      |> Enum.join("")

    try do
      {:ok, Base.decode64!(body)}
    rescue
      _ -> {:error, :invalid_pem}
    end
  end

  defp safe_decode(der) do
    try do
      :public_key.pkix_decode_cert(der, :otp)
    rescue
      _ -> nil
    end
  end

  defp der_fingerprint(der) do
    :crypto.hash(:sha256, der) |> Base.encode16(case: :lower)
  end

  defp extract_cn({:OTPCertificate, tbs, _, _}) do
    tbs
    |> Tuple.to_list()
    |> Enum.reduce(nil, fn entry, acc ->
      case entry do
        {:rdnSequence, rdn_entries} ->
          cn = find_cn(rdn_entries)

          if cn, do: cn, else: acc

        _ ->
          acc
      end
    end)
  end

  defp extract_cn(_), do: nil

  defp find_cn(rdn_sequence) do
    rdn_sequence
    |> List.flatten()
    |> Enum.reduce(nil, fn entry, acc ->
      case entry do
        {:AttributeTypeAndValue, {2, 5, 4, 3}, value} -> value_to_string(value)
        _ -> acc
      end
    end)
  end

  defp value_to_string({_type, value}) when is_binary(value), do: value
  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(_), do: nil

  defp serial({:OTPCertificate, tbs, _, _}) do
    case elem(tbs, 2) do
      value when is_integer(value) -> value
      _ -> nil
    end
  end

  defp serial(_), do: nil

  defp validity(cert) do
    case cert do
      {:OTPCertificate, tbs, _, _} ->
        Enum.find(Tuple.to_list(tbs), fn entry ->
          case entry do
            {:Validity, _, _} -> true
            _ -> false
          end
        end)

      _ ->
        nil
    end
  end

  defp validity_start(cert) do
    case validity(cert) do
      {:Validity, start, _} -> parse_utc_time(start)
      _ -> nil
    end
  end

  defp validity_end(cert) do
    case validity(cert) do
      {:Validity, _, stop} -> parse_utc_time(stop)
      _ -> nil
    end
  end

  defp parse_utc_time({:utcTime, chars}) do
    str = List.to_string(chars)

    year = 2000 + String.to_integer(String.slice(str, 0, 2))
    month = String.to_integer(String.slice(str, 2, 2))
    day = String.to_integer(String.slice(str, 4, 2))
    hour = String.to_integer(String.slice(str, 6, 2))
    minute = String.to_integer(String.slice(str, 8, 2))
    second = String.to_integer(String.slice(str, 10, 2))

    seconds =
      :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}})

    seconds - 62_167_219_200
  end

  defp parse_utc_time({:generalizedTime, chars}) do
    str = List.to_string(chars)

    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> nil
    end
  end

  defp parse_utc_time(_), do: nil

  defp allowed?(_info, nil), do: true
  defp allowed?(info, []), do: info.fingerprint != nil

  defp allowed?(info, allowlist) when is_map(allowlist) do
    cond do
      Map.has_key?(allowlist, info.common_name) ->
        Map.get(allowlist, info.common_name) == info.fingerprint

      true ->
        Enum.member?(Map.values(allowlist), info.fingerprint)
    end
  end

  defp allowed?(info, allowlist) when is_list(allowlist) do
    Enum.member?(allowlist, info.fingerprint)
  end
end
