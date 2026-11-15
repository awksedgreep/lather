defmodule Lather.ReliableMessaging do
  @moduledoc """
  WS-ReliableMessaging-style guaranteed delivery for SOAP calls.

  Wraps request sending with WS-RM headers (`wsrm:MessageID`,
  `wsrm:Sequence`, `wsrm:Expires`) and retries transport-level failures
  with exponential backoff, so transient network errors don't fail the
  call.

  ## Examples

      iex> headers = Lather.ReliableMessaging.headers("msg-1", 1, 30)
      iex> Enum.any?(headers, fn {k, _v} -> k == "wsrm:MessageID" end)
      true

  """

  @wsrm_namespace "http://docs.oasis-open.org/ws-rx/wsrm/200608"

  @doc """
  Builds WS-RM SOAP header entries for a message.
  """
  @spec headers(String.t(), integer(), integer()) :: [map()]
  def headers(message_id, sequence, expires_seconds \\ 30) do
    [
      %{
        "wsrm:MessageID" => message_id,
        "wsrm:Sequence" => sequence,
        "wsrm:Expires" =>
          DateTime.add(DateTime.utc_now(), expires_seconds, :second)
          |> DateTime.to_iso8601(),
        "@xmlns:wsrm" => @wsrm_namespace
      }
    ]
  end

  @doc """
  Generates a stable WS-RM message id.
  """
  @spec generate_message_id() :: String.t()
  def generate_message_id do
    Lather.Wsdl.Addressing.generate_message_id()
  end

  @doc """
  Runs `fun` until it returns `{:ok, _}` or succeeds, retrying transport
  errors up to `retries` times with exponential backoff.

  Returns the last result when all attempts fail.
  """
  @spec deliver(
          (-> {:ok, term()} | {:error, term()}),
          non_neg_integer(),
          non_neg_integer(),
          map() | nil
        ) :: {:ok, term()} | {:error, term()}
  def deliver(fun, retries \\ 3, backoff_ms \\ 100, metrics \\ nil) do
    deliver_loop(fun, retries, backoff_ms, 0, metrics)
  end

  defp deliver_loop(fun, retries, backoff_ms, attempt, metrics) do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:error, {:transport_error, _}} = error ->
        if attempt < retries do
          if metrics, do: Lather.Http.Metrics.record_retry(metrics)
          Process.sleep(backoff_ms * 2 ** attempt)
          deliver_loop(fun, retries, backoff_ms, attempt + 1, metrics)
        else
          error
        end

      {:error, {:soap_fault, fault}} = error ->
        if attempt < retries and retryable_fault?(fault) do
          if metrics, do: Lather.Http.Metrics.record_retry(metrics)
          Process.sleep(backoff_ms * 2 ** attempt)
          deliver_loop(fun, retries, backoff_ms, attempt + 1, metrics)
        else
          error
        end

      other ->
        other
    end
  end

  @doc """
  Returns true when a result is a retryable transport failure.
  """
  @spec retryable?({:error, term()}) :: boolean()
  def retryable?({:error, {:transport_error, _}}), do: true
  def retryable?({:error, _}), do: false

  @doc """
  Returns true when a SOAP fault is a transient (Receiver) fault that is
  safe to redeliver.
  """
  @spec retryable_fault?(map()) :: boolean()
  def retryable_fault?(fault) when is_map(fault) do
    fault_code = fault[:fault_code] || fault["fault_code"] || ""
    String.contains?(to_string(fault_code), "Receiver")
  end

  def retryable_fault?(_), do: false
end
