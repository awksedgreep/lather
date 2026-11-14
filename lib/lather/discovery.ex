defmodule Lather.Discovery do
  @moduledoc """
  WS-Discovery support.

  Servers with `enable_discovery: true` respond to WS-Discovery Probe
  messages sent to `<endpoint>?discovery` with a Matches document
  listing their services. Clients can use `probe/1` to find services.

  ## Examples

      iex> {:ok, xml} = Lather.Discovery.matches_document("MyService", "http://localhost:4000/soap")
      iex> xml =~ "wsd:Matches"
      true

  """

  alias Lather.Xml.Parser

  @discovery_namespace "http://schemas.xmlsoap.org/ws/2005/04/discovery"

  @doc """
  Builds a WS-Discovery Probe envelope.
  """
  @spec probe_envelope(String.t() | nil) :: String.t()
  def probe_envelope(types \\ nil) do
    types_tag =
      if types, do: "<wsd:Types>#{types}</wsd:Types>", else: ""

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/ws/2003/05/soap-envelope"
      xmlns:wsd="#{@discovery_namespace}">
      <soap:Header>
        <wsa:Action xmlns:wsa="http://www.w3.org/2005/08/addressing">
          http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe
        </wsa:Action>
      </soap:Header>
      <soap:Body>
        <wsd:Probe>
          #{types_tag}
        </wsd:Probe>
      </soap:Body>
    </soap:Envelope>
    """
  end

  @doc """
  Builds a Matches document for a service.
  """
  @spec matches_document(String.t(), String.t()) :: {:ok, String.t()}
  def matches_document(service_name, endpoint) do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/ws/2003/05/soap-envelope"
      xmlns:wsd="#{@discovery_namespace}">
      <soap:Body>
        <wsd:Matches>
          <wsd:Match endpoint="#{endpoint}">
            <wsd:Types>#{service_name}</wsd:Types>
          </wsd:Match>
        </wsd:Matches>
      </soap:Body>
    </soap:Envelope>
    """

    {:ok, xml}
  end

  @doc """
  Sends a WS-Discovery Probe to a discovery endpoint and returns the
  matching services as `%{endpoint: ..., types: ...}` maps.
  """
  @spec probe(String.t()) :: {:ok, [map()]} | {:error, term()}
  def probe(endpoint) do
    url = endpoint <> "?discovery"

    options = [content_type: "application/soap+xml", soap_version: :v1_2]

    with {:ok, %{status: 200, body: body}} <-
           Lather.Http.Transport.post(url, probe_envelope(), options),
         {:ok, parsed} <- Parser.parse(body) do
      matches =
        parsed
        |> get_in(["soap:Envelope", "soap:Body", "wsd:Matches", "wsd:Match"])
        |> normalize_matches()

      {:ok, matches}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_matches(nil), do: []
  defp normalize_matches(matches) when is_list(matches), do: Enum.map(matches, &match_map/1)
  defp normalize_matches(match) when is_map(match), do: [match_map(match)]
  defp normalize_matches(_other), do: []

  defp match_map(match) when is_map(match) do
    %{
      endpoint: match["endpoint"] || match["@endpoint"],
      types: match["wsd:Types"]
    }
  end

  defp match_map(_other), do: %{endpoint: nil, types: nil}
end
