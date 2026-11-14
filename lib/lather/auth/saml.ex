defmodule Lather.Auth.SAML do
  @moduledoc """
  SAML 2.0 assertion support for WS-Security SOAP headers.

  Assertions are carried inside the `wsse:Security` header and signed with
  HMAC-SHA256 over a canonicalized rendering of the assertion (an
  "unsigned-XML-with-HMAC" profile suitable for trusted party-to-party
  services; use a full PKI SAML stack for federation):

      <wsse:Security xmlns:wsse="...">
        <saml:Assertion xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
                        Version="2.0" ID="saml-...">
          <saml:Issuer>lather</saml:Issuer>
          <saml:Subject>
            <saml:Name Format="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent">alice</saml:Name>
          </saml:Subject>
          <saml:Conditions NotOnOrAfter="2026-11-14T12:00:00Z"/>
          <saml:Attribute Name="role" Value="admin"/>
          <saml:Signature Algorithm="HMAC-SHA256">hex-digest</saml:Signature>
        </saml:Assertion>
      </wsse:Security>

  ## Examples

      assertion = Lather.Auth.SAML.assertion("alice", secret: "s3cret")
      {:ok, claims} = Lather.Auth.SAML.verify(assertion["saml:Assertion"], "s3cret")
      claims["subject"]
      # "alice"

  """

  alias Lather.Soap.Elements

  @saml_namespace "urn:oasis:names:tc:SAML:2.0:assertion"
  @wsse_namespace "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"

  @doc """
  Builds a signed SAML assertion header fragment.

  ## Options

    * `:secret` - HMAC-SHA256 secret (required)
    * `:issuer` - issuer string (default `"lather"`)
    * `:ttl` - seconds until `NotOnOrAfter` (default 3600)
    * `:attributes` - map of assertion attributes, e.g. `%{"role" => "admin"}`

  Returns a `%{"saml:Assertion" => ...}` map suitable for a SOAP header.
  """
  @spec assertion(String.t(), keyword()) :: map()
  def assertion(subject, opts \\ []) do
    secret = Keyword.get(opts, :secret)

    unless is_binary(secret) do
      raise ArgumentError, "SAML assertion requires a :secret option"
    end

    issuer = Keyword.get(opts, :issuer, "lather")
    ttl = Keyword.get(opts, :ttl, 3600)
    attributes = Keyword.get(opts, :attributes, %{})
    {:ok, now} = DateTime.now("Etc/UTC")
    id = "saml-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    not_on_or_after = now |> DateTime.add(ttl, :second) |> DateTime.to_iso8601()

    content = %{
      "@xmlns:saml" => @saml_namespace,
      "@Version" => "2.0",
      "@ID" => id,
      "saml:Issuer" => issuer,
      "saml:Subject" => %{
        "saml:Name" => %{
          "@Format" => "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
          "#text" => subject
        }
      },
      "saml:Conditions" => %{"@NotOnOrAfter" => not_on_or_after},
      "saml:Attribute" => %{
        "@Name" => Map.keys(attributes) |> Enum.sort() |> List.first() || "role",
        "@Value" => attributes |> Map.values() |> List.first() || "user"
      }
    }

    digest = signature(content, secret)

    signed_content =
      Map.put(content, "saml:Signature", %{"@Algorithm" => "HMAC-SHA256", "#text" => digest})

    %{"saml:Assertion" => signed_content}
  end

  @doc """
  Wraps an assertion in a `wsse:Security` SOAP header.

  ## Examples

      iex> header = Lather.Auth.SAML.security_header(Lather.Auth.SAML.assertion("a", secret: "k"))
      iex> header["wsse:Security"]["saml:Assertion"]["@Version"]
      "2.0"

  """
  @spec security_header(map()) :: map()
  def security_header(assertion_header) do
    %{
      "wsse:Security" =>
        %{
          "@xmlns:wsse" => @wsse_namespace,
          "@xmlns:saml" => @saml_namespace
        }
        |> Map.merge(assertion_header)
    }
  end

  @doc """
  Verifies a (parsed) SAML assertion's signature and expiry.

  Returns `{:ok, claims}` where claims is
  `%{"subject" => ..., "issuer" => ..., "attributes" => %{...}}`, or
  `{:error, reason}`.
  """
  @spec verify(map(), binary()) :: {:ok, map()} | {:error, term()}
  def verify(assertion, secret) when is_map(assertion) and is_binary(secret) do
    canonical = canonical_content(assertion)
    expected = :crypto.mac(:hmac, :sha256, secret, canonical) |> Base.encode16(case: :lower)

    signature_text =
      Enum.find_value(assertion, fn {key, value} ->
        if Elements.local_name(key) == "Signature" and is_map(value) do
          Map.get(value, "#text")
        end
      end)

    cond do
      signature_text == nil ->
        {:error, :missing_signature}

      signature_text != expected ->
        {:error, :invalid_signature}

      expired?(assertion) ->
        {:error, :expired}

      true ->
        {:ok, extract_claims(assertion)}
    end
  end

  @doc """
  Finds a SAML assertion in parsed SOAP headers.
  """
  @spec extract(list()) :: map() | nil
  def extract(headers) when is_list(headers) do
    Enum.find_value(headers, fn pair ->
      {name, content} = pair

      if Elements.local_name(to_string(name)) == "Assertion" and is_map(content) do
        content
      else
        if Elements.local_name(to_string(name)) == "Security" and is_map(content) do
          Enum.find_value(content, fn sub ->
            {sub_name, sub_content} = sub

            if Elements.local_name(to_string(sub_name)) == "Assertion" and
                 is_map(sub_content) do
              sub_content
            end
          end)
        end
      end
    end)
  end

  defp signature(content, secret) do
    canonical = canonical_content(content)
    :crypto.mac(:hmac, :sha256, secret, canonical) |> Base.encode16(case: :lower)
  end

  defp canonical_content(assertion) do
    assertion
    |> Enum.reject(fn {key, _value} -> Elements.local_name(to_string(key)) == "Signature" end)
    |> Enum.sort_by(&to_string(elem(&1, 0)))
    |> Enum.map_join(";", fn {key, value} -> "#{key}=#{canonical_value(value)}" end)
  end

  defp canonical_value(value) when is_binary(value), do: value

  defp canonical_value(value) when is_map(value) do
    value
    |> Enum.sort_by(&to_string(elem(&1, 0)))
    |> Enum.map_join(",", fn {key, sub} -> "#{key}=#{canonical_value(sub)}" end)
  end

  defp canonical_value(value), do: to_string(value)

  defp expired?(assertion) do
    not_on_or_after =
      Enum.find_value(assertion, fn {key, value} ->
        if Elements.local_name(to_string(key)) == "Conditions" and is_map(value) do
          Map.get(value, "@NotOnOrAfter")
        end
      end)

    case not_on_or_after do
      nil ->
        false

      value ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} ->
            {:ok, now} = DateTime.now("Etc/UTC")
            DateTime.compare(datetime, now) == :lt

          _ ->
            false
        end
    end
  end

  defp extract_claims(assertion) do
    subject =
      Enum.find_value(assertion, fn {key, value} ->
        if Elements.local_name(to_string(key)) == "Subject" and is_map(value) do
          Enum.find_value(value, fn sub ->
            {sub_key, sub_value} = sub

            if Elements.local_name(to_string(sub_key)) == "Name" do
              if is_binary(sub_value) do
                sub_value
              else
                Map.get(sub_value, "#text")
              end
            end
          end)
        end
      end)

    issuer =
      Enum.find_value(assertion, fn {key, value} ->
        if Elements.local_name(to_string(key)) == "Issuer", do: value
      end)

    attributes =
      Enum.reduce(assertion, %{}, fn {key, value}, acc ->
        if Elements.local_name(to_string(key)) == "Attribute" and is_map(value) do
          Map.put(acc, Map.get(value, "@Name", "unknown"), Map.get(value, "@Value"))
        else
          acc
        end
      end)

    %{"subject" => subject, "issuer" => issuer, "attributes" => attributes}
  end
end
