# Real-World Service Examples

## 1. Weather-style SOAP service

```elixir
defmodule WeatherService do
  use Lather.Server

  @service_name "WeatherService"
  @namespace "urn:weather"

  soap_operation "GetForecast" do
    input do
      parameter("zip", :string, required: true, pattern: "^[0-9]{5}$")
    end

    output do
      parameter("temperature", :integer)
      parameter("condition", :string, enum: ["sun", "cloud", "rain"])
    end
  end

  def get_forecast(%{"zip" => zip}) do
    {:ok, %{"temperature" => 72, "condition" => "sun", "zip" => zip}}
  end
end

{:ok, client} = Lather.DynamicClient.new("http://localhost:4000/soap?wsdl")
{:ok, forecast} = Lather.DynamicClient.call(client, "GetForecast", %{"zip" => "90210"})
```

## 2. Large attachment upload with MTOM + streaming

```elixir
{:ok, cache} = Lather.Mtom.Cache.start_link(name: :attach_cache)

{:ok, _} = Lather.DynamicClient.call(client, "UploadDoc", %{"name" => "doc1"},
  attachments: [{"doc.pdf", File.read("doc.pdf")}],
  mtom_cache: cache)
```

Repeat uploads reuse the cached attachment via the cache.

## 3. Pub/Sub via WS-Eventing

```elixir
plug = {Lather.Server.EnhancedPlug, [service: WeatherService, enable_eventing: true]}

{:ok, sub} = Lather.Eventing.subscribe("alerts")
Lather.Eventing.publish("alerts", %{"level" => "storm"})
{:ok, events} = Lather.Eventing.poll(sub)
```

## 4. Secure service with policy and multi-factor auth

```elixir
plug = {Lather.Server.EnhancedPlug, [
  service: WeatherService,
  security_policy: Lather.Auth.Policy.build([:api_key, :jwt]),
  api_keys: ["secret-key"],
  jwt_secret: System.get_env("JWT_SECRET")
]}
```

Requests must carry both an API key and a valid JWT.

## 5. Load testing a service before release

```elixir
stats = Lather.LoadTest.run(client, "GetForecast", %{"zip" => "90210"},
  iterations: 500, concurrency: 20)

IO.puts("average: #{stats.average_ms} ms, failures: #{stats.failure}")
```
