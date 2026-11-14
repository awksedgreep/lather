defmodule Lather.PropertySoapRoundTripTest do
  use ExUnit.Case, async: true

  alias Lather.Soap.Envelope
  alias Lather.Xml.Parser

  defp random_alnum(len) do
    chars = ?a..?z |> Enum.to_list()

    1..len
    |> Enum.map(fn _ ->
      Enum.at(chars, :rand.uniform(length(chars)) - 1)
    end)
    |> List.to_string()
  end

  test "random envelopes round-trip through the XML parser" do
    for _ <- 1..30 do
      operation = random_alnum(6)
      key = random_alnum(5)
      value = random_alnum(12)

      {:ok, xml} = Envelope.build(operation, %{key => value})
      {:ok, parsed} = Parser.parse(xml)

      body = get_in(parsed, ["soap:Envelope", "soap:Body"])

      assert is_map(body) || is_list(body)
      assert body && Map.get(body, operation) != nil
      assert Map.get(Map.get(body, operation), key) == value
    end
  end

  test "random nested parameters survive parsing" do
    for _ <- 1..20 do
      key = random_alnum(4)
      inner = random_alnum(6)
      value = random_alnum(8)

      {:ok, xml} = Envelope.build("Nested", %{key => %{inner => value}})
      {:ok, parsed} = Parser.parse(xml)

      body = get_in(parsed, ["soap:Envelope", "soap:Body", "Nested", key, inner])
      assert body == value
    end
  end
end
