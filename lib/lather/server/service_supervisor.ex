defmodule Lather.Server.ServiceSupervisor do
  @moduledoc """
  GenServer that supervises a Lather service.

  The supervisor owns the service configuration and can:

    * invoke operations in-process (`call/3`) without an HTTP server
    * start/stop an HTTP server (`start_http_server/2`, `stop_http_server/1`)
    * report usage stats (`stats/1`)

  ## Examples

      {:ok, pid} = Lather.Server.ServiceSupervisor.start_link(MyService)

      {:ok, result} = Lather.Server.ServiceSupervisor.call(pid, "Echo", %{"message" => "hi"})

      {:ok, port} = Lather.Server.ServiceSupervisor.start_http_server(pid, 0)

      stats = Lather.Server.ServiceSupervisor.stats(pid)
  """

  use GenServer

  alias Lather.Server.EnhancedPlug
  alias Lather.TestClient

  @doc """
  Starts the supervisor for the given service module.

  Options are those of `Lather.Server.EnhancedPlug.init/1` plus `:name`.
  """
  @spec start_link(module(), keyword()) :: GenServer.on_start()
  def start_link(service, opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, {service, opts}, name: name)
  end

  @doc """
  Calls an operation through the service's JSON dispatch path.

  Returns `{:ok, decoded_response}` or `{:error, reason}`.
  """
  @spec call(GenServer.server(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call(server, operation, params) do
    GenServer.call(server, {:call, operation, params})
  end

  @doc """
  Starts an HTTP server for the supervised service.

  Pass `port: 0` to let the OS pick a free port. Returns `{:ok, port}`.
  """
  @spec start_http_server(GenServer.server(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def start_http_server(server, port \\ 0) do
    GenServer.call(server, {:start_http_server, port})
  end

  @doc """
  Stops the supervised HTTP server (if running).
  """
  @spec stop_http_server(GenServer.server()) :: :ok
  def stop_http_server(server) do
    GenServer.call(server, :stop_http_server)
  end

  @doc """
  Returns supervisor stats: service name, request/error counts, the HTTP
  server status, and uptime in seconds.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  @impl true
  def init({service, opts}) do
    config = EnhancedPlug.init([service: service] ++ opts)

    state = %{
      service: service,
      opts: [service: service] ++ opts,
      config: config,
      http_pid: nil,
      http_port: nil,
      requests: 0,
      errors: 0,
      started_at: :os.system_time(:second)
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:plug_conn, :sent}, state) do
    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:call, operation, params}, _from, state) do
    conn = TestClient.call_json(state.config, operation, params)

    state = %{state | requests: state.requests + 1}
    state = if conn.status >= 400, do: %{state | errors: state.errors + 1}, else: state

    {:reply, decode_response(conn), state}
  end

  def handle_call({:start_http_server, port}, _from, state) do
    cond do
      state.http_pid ->
        {:reply, {:ok, state.http_port}, state}

      not Code.ensure_loaded?(Bandit) ->
        {:reply, {:error, :bandit_not_available}, state}

      true ->
        case apply(Bandit, :start_link, [[plug: {EnhancedPlug, state.opts}, port: port]]) do
          {:ok, pid} ->
            actual_port =
              if Code.ensure_loaded?(ThousandIsland) do
                case apply(ThousandIsland, :listener_info, [pid]) do
                  {:ok, {_address, p}} -> p
                  _ -> port
                end
              else
                port
              end

            {:reply, {:ok, actual_port}, %{state | http_pid: pid, http_port: actual_port}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:stop_http_server, _from, state) do
    if state.http_pid do
      Process.exit(state.http_pid, :shutdown)
    end

    {:reply, :ok, %{state | http_pid: nil, http_port: nil}}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      service: state.service,
      requests: state.requests,
      errors: state.errors,
      http_running: state.http_pid != nil,
      http_port: state.http_port,
      uptime_seconds: :os.system_time(:second) - state.started_at
    }

    {:reply, stats, state}
  end

  defp decode_response(conn) do
    case conn.resp_body do
      nil ->
        {:error, :empty_response}

      body ->
        case Jason.decode(body) do
          {:ok, %{"success" => true, "data" => data}} -> {:ok, data}
          {:ok, %{"success" => false, "error" => error}} -> {:error, error}
          {:ok, other} -> {:ok, other}
          {:error, _} -> {:ok, body}
        end
    end
  end
end
