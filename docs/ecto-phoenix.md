# Ecto and Phoenix Integration

## Ecto-backed handlers

Handlers can call Ecto repositories directly; Lather does not depend on
Ecto itself:

```elixir
defmodule UserService do
  use Lather.Server

  soap_operation "GetUser" do
    input do
      parameter("id", :integer, required: true, min: 1)
    end
    output do
      parameter("name", :string)
    end
  end

  def get_user(%{"id" => id}) do
    case MyApp.Repo.get(User, id) do
      nil -> {:error, "user not found"}
      user -> {:ok, %{"name" => user.name}}
    end
  end
end
```

Map Ecto changesets into parameter validation with the DSL
(`enum:`, `pattern:`, `min:`, `max:`, `default:`) so most invalid input
fails before the repo call.

## Phoenix mount

Mount an EnhancedPlug in a Phoenix router:

```elixir
forward "/soap", Lather.Server.EnhancedPlug, [service: UserService]
```

If your app already serves its own `/health` or `/metrics` routes, either keep
the SOAP service on its own path (as above) or turn Lather's built-ins off.
The endpoints are matched on complete path segments, so unrelated routes such
as `/healthcare/patients` or `/api/health-check` are never intercepted:

```elixir
forward "/soap", Lather.Server.EnhancedPlug, [
  service: UserService,
  health_path: nil,      # or "/soap-health" to relocate
  metrics_path: nil,
  openapi_path: "/openapi.json"
]
```

Disabled paths are also omitted from the generated OpenAPI document.

For Phoenix PubSub bridging to WS-Eventing:

```elixir
defmodule EventBridge do
  def start(channel) do
    {:ok, sub_id} = Lather.Eventing.subscribe(channel)
    spawn_link(fn -> poll_loop(sub_id, channel) end)
  end

  defp poll_loop(sub_id, channel) do
    case Lather.Eventing.poll(sub_id) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          Phoenix.PubSub.broadcast(MyApp.PubSub, channel, event)
        end)
      _ -> :ok
    end

    Process.sleep(500)
    poll_loop(sub_id, channel)
  end
end
```

This turns WS-Eventing publications into Phoenix PubSub broadcasts and
vice versa (send PubSub messages to `Lather.Eventing.publish/3`).
