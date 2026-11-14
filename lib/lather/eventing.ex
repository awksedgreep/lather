defmodule Lather.Eventing do
  @moduledoc """
  WS-Eventing style publish/subscribe for Lather services.

  Subscriptions are in-memory (per Erlang node) and keyed by channel.
  Publishers post events to a channel; subscribers poll their
  subscription and receive the events as WS-Eventing `Notify` messages.

  ## Examples

      iex> Lather.Eventing.notify_envelope("sub-1", "hello")
      ...> |> String.contains?("wse:Notify")
      true

  """

  use GenServer

  @eventing_namespace "http://schemas.xmlsoap.org/ws/2004/06/eventing"

  @doc """
  Starts the event broker.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Creates a subscription for a channel. Returns `{:ok, subscription_id}`.
  """
  @spec subscribe(String.t(), keyword()) :: {:ok, String.t()}
  def subscribe(channel, opts \\ []) do
    GenServer.call(broker(opts), {:subscribe, channel})
  end

  @doc """
  Publishes a payload to all subscribers of a channel.
  Returns the number of subscribers notified.
  """
  @spec publish(String.t(), term(), keyword()) :: {:ok, non_neg_integer()}
  def publish(channel, payload, opts \\ []) do
    GenServer.call(broker(opts), {:publish, channel, payload})
  end

  @doc """
  Polls a subscription, draining any queued events.

  Returns `{:ok, [notify_xml]}` where each entry is a WS-Eventing Notify
  envelope.
  """
  @spec poll(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, :unknown_subscription}
  def poll(subscription_id, opts \\ []) do
    GenServer.call(broker(opts), {:poll, subscription_id})
  end

  @doc """
  Cancels a subscription.
  """
  @spec unsubscribe(String.t(), keyword()) :: :ok
  def unsubscribe(subscription_id, opts \\ []) do
    GenServer.call(broker(opts), {:unsubscribe, subscription_id})
  end

  @doc """
  Builds a WS-Eventing Notify envelope for a payload.
  """
  @spec notify_envelope(String.t(), term()) :: String.t()
  def notify_envelope(subscription_id, payload) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/ws/2003/05/soap-envelope"
      xmlns:wse="#{@eventing_namespace}">
      <soap:Header>
        <wse:Event xmlns:wse="#{@eventing_namespace}">
          <wse:Source>urn:lather:eventing</wse:Source>
          <wse:SubscriptionId>#{subscription_id}</wse:SubscriptionId>
        </wse:Event>
      </soap:Header>
      <soap:Body>
        <wse:Notify>
          <payload>#{payload}</payload>
        </wse:Notify>
      </soap:Body>
    </soap:Envelope>
    """
  end

  defp broker(opts) do
    Keyword.get(opts, :name, __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: %{}, queues: %{}}}
  end

  @impl true
  def handle_call({:subscribe, channel}, _from, state) do
    id = Lather.Wsdl.Addressing.generate_message_id()
    subscriptions = Map.put(state.subscriptions, id, channel)
    queues = Map.put(state.queues, id, [])

    {:reply, {:ok, id}, %{state | subscriptions: subscriptions, queues: queues}}
  end

  def handle_call({:publish, channel, payload}, _from, state) do
    matching =
      Enum.filter(state.subscriptions, &(elem(&1, 1) == channel))

    queues =
      Enum.reduce(matching, state.queues, fn {id, _ch}, acc ->
        Map.update(acc, id, [payload], fn queue -> queue ++ [payload] end)
      end)

    {:reply, {:ok, length(matching)}, %{state | queues: queues}}
  end

  def handle_call({:poll, subscription_id}, _from, state) do
    case Map.get(state.queues, subscription_id) do
      nil ->
        {:reply, {:error, :unknown_subscription}, state}

      queue ->
        envelopes = Enum.map(queue, fn payload -> notify_envelope(subscription_id, payload) end)
        {:reply, {:ok, envelopes}, %{state | queues: Map.put(state.queues, subscription_id, [])}}
    end
  end

  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    {:reply, :ok,
     %{
       state
       | subscriptions: Map.delete(state.subscriptions, subscription_id),
         queues: Map.delete(state.queues, subscription_id)
     }}
  end
end
