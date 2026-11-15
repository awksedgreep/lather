defmodule Lather.Server.AuditTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lather.Server.EnhancedPlug

  defmodule AuditedService do
    use Lather.Server

    @service_name "AuditedService"

    soap_operation "Ping" do
      input do
        parameter("seq", :int, required: true)
      end

      output do
        parameter("pong", :string)
      end
    end

    def ping(%{"seq" => seq}), do: {:ok, %{"pong" => "pong #{seq}"}}
  end

  defp tmp_log() do
    id = "#{System.unique_integer([:positive])}-#{:rand.uniform(1_000_000)}"
    path = System.tmp_dir!() |> Path.join("lather_audit_#{id}.jsonl")
    File.write(path, "")
    path
  end

  test "requests are appended to the audit log" do
    path = tmp_log()
    config = EnhancedPlug.init(service: AuditedService, audit_log: path)

    conn(:get, "/soap?health") |> EnhancedPlug.call(config)
    conn(:get, "/soap?openapi") |> EnhancedPlug.call(config)

    {:ok, contents} = File.read(path)
    lines = contents |> String.trim() |> String.split("\n")
    assert length(lines) == 2

    entries = Enum.map(lines, &Jason.decode!/1)
    assert Enum.all?(entries, fn entry -> entry["status"] == 200 end)
    assert Enum.any?(entries, fn entry -> entry["path"] == "/soap" end)
    assert Enum.all?(entries, fn entry -> entry["service"] == inspect(AuditedService) end)
  end

  test "concurrent requests are all recorded without loss" do
    path = tmp_log()
    config = EnhancedPlug.init(service: AuditedService, audit_log: path)

    1..20
    |> Task.async_stream(
      fn _ ->
        conn(:get, "/soap?health") |> EnhancedPlug.call(config)
      end,
      max_concurrency: 10
    )
    |> Enum.to_list()

    {:ok, contents} = File.read(path)
    lines = contents |> String.trim() |> String.split("\n")

    assert length(lines) == 20
  end

  test "failed requests are recorded with their status" do
    path = tmp_log()
    config = EnhancedPlug.init(service: AuditedService, audit_log: path)

    conn(:post, "/soap", "invalid xml") |> EnhancedPlug.call(config)

    {:ok, contents} = File.read(path)
    [entry] = contents |> String.trim() |> String.split("\n") |> Enum.map(&Jason.decode!/1)
    assert entry["status"] == 400
    assert entry["method"] == "POST"
  end

  test "no audit log is written when not configured" do
    config = EnhancedPlug.init(service: AuditedService)
    conn(:get, "/soap?health") |> EnhancedPlug.call(config)
    assert :ok
  end
end
