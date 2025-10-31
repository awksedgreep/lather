defmodule Lather.ClientTest do
  use ExUnit.Case
  doctest Lather.Client

  alias Lather.Client
  alias Lather.Soap.Envelope

  describe "client creation" do
    test "creates a new client with endpoint" do
      client = Client.new("https://example.com/soap")

      assert client.endpoint == "https://example.com/soap"
      assert client.options == []
    end

    test "creates a new client with options" do
      options = [timeout: 60_000, headers: [{"custom", "header"}]]
      client = Client.new("https://example.com/soap", options)

      assert client.endpoint == "https://example.com/soap"
      assert client.options == options
    end
  end

  describe "envelope building" do
    test "builds a basic SOAP envelope" do
      {:ok, envelope} = Envelope.build(:get_user, %{id: 123})

      assert String.contains?(envelope, "soap:Envelope")
      assert String.contains?(envelope, "soap:Body")
      assert String.contains?(envelope, "get_user")
      assert String.contains?(envelope, "123")
    end

    test "builds envelope with namespace" do
      {:ok, envelope} = Envelope.build(:get_user, %{id: 123}, namespace: "http://example.com")

      assert String.contains?(envelope, "xmlns=\"http://example.com\"")
    end

    test "builds envelope with headers" do
      headers = [{"custom_header", "value"}]
      {:ok, envelope} = Envelope.build(:get_user, %{id: 123}, headers: headers)

      assert String.contains?(envelope, "soap:Header")
      assert String.contains?(envelope, "custom_header")
    end
  end
end
