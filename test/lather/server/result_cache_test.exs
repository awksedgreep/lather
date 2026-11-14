defmodule Lather.Server.ResultCacheTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lather.Server.EnhancedPlug

  defmodule CounterService do
    use Lather.Server

    @service_name "CounterService"

    soap_operation "Count" do
      input do
        parameter("key", :string, required: true)
      end

      output do
        parameter("count", :int)
      end
    end

    soap_operation "FailFirst" do
      input do
        parameter("key", :string, required: true)
      end

      output do
        parameter("value", :string)
      end
    end

    def count(%{"key" => key}) do
      n = :persistent_term.get({__MODULE__, key}, 0) + 1
      :persistent_term.put({__MODULE__, key}, n)
      {:ok, %{"count" => n}}
    end

    def fail_first(%{"key" => key}) do
      attempts = :persistent_term.get({__MODULE__, :fail, key}, 0) + 1
      :persistent_term.put({__MODULE__, :fail, key}, attempts)

      if attempts == 1 do
        {:error, "transient failure"}
      else
        {:ok, %{"value" => "recovered"}}
      end
    end
  end

  defp json_call(config, operation, params) do
    conn(:post, "/soap/api/#{operation}", Jason.encode!(params))
    |> EnhancedPlug.call(config)
  end

  test "identical requests are served from the cache" do
    config = EnhancedPlug.init(service: CounterService, cache_results: true)
    key = "cache-hit-#{System.unique_integer([:positive])}"

    first = json_call(config, "Count", %{"key" => key})
    second = json_call(config, "Count", %{"key" => key})

    assert first.status == 200
    assert second.status == 200
    assert Jason.decode!(first.resp_body)["data"]["count"] == 1
    assert Jason.decode!(second.resp_body)["data"]["count"] == 1
  end

  test "caching is disabled by default" do
    config = EnhancedPlug.init(service: CounterService)
    key = "no-cache-#{System.unique_integer([:positive])}"

    first = json_call(config, "Count", %{"key" => key})
    second = json_call(config, "Count", %{"key" => key})

    assert Jason.decode!(first.resp_body)["data"]["count"] == 1
    assert Jason.decode!(second.resp_body)["data"]["count"] == 2
  end

  test "expired entries are recomputed" do
    config = EnhancedPlug.init(service: CounterService, cache_results: true, cache_ttl: 0)
    key = "ttl-#{System.unique_integer([:positive])}"

    first = json_call(config, "Count", %{"key" => key})
    second = json_call(config, "Count", %{"key" => key})

    assert Jason.decode!(first.resp_body)["data"]["count"] == 1
    assert Jason.decode!(second.resp_body)["data"]["count"] == 2
  end

  test "failed operations are not cached" do
    config = EnhancedPlug.init(service: CounterService, cache_results: true)
    key = "fail-#{System.unique_integer([:positive])}"

    first = json_call(config, "FailFirst", %{"key" => key})
    second = json_call(config, "FailFirst", %{"key" => key})

    assert first.status == 500
    assert second.status == 200
    assert Jason.decode!(second.resp_body)["data"]["value"] == "recovered"
  end

  test "different parameters get different cache entries" do
    config = EnhancedPlug.init(service: CounterService, cache_results: true)
    key = "params-#{System.unique_integer([:positive])}"

    a = json_call(config, "Count", %{"key" => key <> "a"})
    b = json_call(config, "Count", %{"key" => key <> "b"})

    assert Jason.decode!(a.resp_body)["data"]["count"] == 1
    assert Jason.decode!(b.resp_body)["data"]["count"] == 1
  end

  test "clearing the cache forces recomputation" do
    config = EnhancedPlug.init(service: CounterService, cache_results: true)
    key = "clear-#{System.unique_integer([:positive])}"

    json_call(config, "Count", %{"key" => key})
    Lather.Server.ResultCache.clear(config.result_cache)
    again = json_call(config, "Count", %{"key" => key})

    assert Jason.decode!(again.resp_body)["data"]["count"] == 2
  end

  test "SOAP requests also use the cache" do
    config = EnhancedPlug.init(service: CounterService, cache_results: true)
    key = "soap-#{System.unique_integer([:positive])}"

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <Count xmlns="urn:example">
          <key>#{key}</key>
        </Count>
      </soap:Body>
    </soap:Envelope>
    """

    first = conn(:post, "/soap", body) |> EnhancedPlug.call(config)
    second = conn(:post, "/soap", body) |> EnhancedPlug.call(config)

    assert first.status == 200
    assert second.status == 200
    assert first.resp_body == second.resp_body
    assert second.resp_body =~ "<count>1</count>"
  end
end
