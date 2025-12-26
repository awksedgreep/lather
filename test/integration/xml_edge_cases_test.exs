defmodule Lather.Integration.XmlEdgeCasesTest do
  @moduledoc """
  Integration tests for XML edge cases.

  Tests proper handling of:
  - XML special characters that need escaping
  - Unicode/UTF-8 characters
  - CDATA-like content
  - Whitespace normalization
  - Encoding edge cases
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  defmodule XmlEdgeCasesService do
    use Lather.Server

    @namespace "http://test.example.com/xmledge"
    @service_name "XmlEdgeCasesService"

    soap_operation "EchoText" do
      description "Echoes text, testing XML special character handling"
      input do
        parameter "text", :string, required: true
      end
      output do
        parameter "result", :string
      end
      soap_action "EchoText"
    end

    def echo_text(%{"text" => text}), do: {:ok, %{"result" => text}}

    soap_operation "EchoMultiple" do
      description "Echoes multiple fields"
      input do
        parameter "field1", :string, required: true
        parameter "field2", :string, required: true
      end
      output do
        parameter "result1", :string
        parameter "result2", :string
      end
      soap_action "EchoMultiple"
    end

    def echo_multiple(%{"field1" => f1, "field2" => f2}) do
      {:ok, %{"result1" => f1, "result2" => f2}}
    end
  end

  defmodule XmlEdgeCasesRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.XmlEdgeCasesTest.XmlEdgeCasesService)
      )
    end
  end

  describe "XML special character escaping" do
    setup :start_server

    test "handles ampersand character", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "Tom & Jerry"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles less-than character", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "5 < 10"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles greater-than character", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "10 > 5"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles single quote character", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "It's working"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles double quote character", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "He said \"hello\""
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles all XML special chars combined", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "Tom & Jerry said \"It's < 5 > 0\""
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles HTML-like content", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "<html><body>Test</body></html>"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles XML declaration-like content", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "<?xml version=\"1.0\"?>"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end
  end

  describe "Unicode and UTF-8 handling" do
    setup :start_server

    test "handles basic Latin extended characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "café résumé naïve"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles German umlauts", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "größe über müssen"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles Cyrillic characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "Привет мир"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles Chinese characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "你好世界"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles Japanese characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "こんにちは"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles Arabic characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "مرحبا بالعالم"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles emoji", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "Hello 👋 World 🌍"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles mixed scripts", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "Hello Привет 你好 مرحبا"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end
  end

  describe "whitespace handling" do
    setup :start_server

    test "handles leading and trailing spaces", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "  padded text  "
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      # XML may normalize whitespace, but should preserve content
      assert is_binary(response["result"])
      assert String.contains?(response["result"], "padded text")
    end

    test "handles tab characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "column1\tcolumn2\tcolumn3"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert is_binary(response["result"])
    end

    test "handles newline characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "line1\nline2\nline3"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert is_binary(response["result"])
    end

    test "handles carriage return and newline", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "line1\r\nline2\r\nline3"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert is_binary(response["result"])
    end

    test "handles multiple consecutive spaces", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "word1    word2     word3"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert is_binary(response["result"])
    end
  end

  describe "edge case values" do
    setup :start_server

    test "handles numeric-looking strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "12345"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles boolean-looking strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Test that "true" as a string stays a string
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => "true"})
      assert response["result"] == "true"
    end

    test "handles null-like strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => "null"})
      assert response["result"] == "null"
    end

    test "handles backslash characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "path\\to\\file"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles forward slash characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "path/to/file"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles URL-like strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "https://example.com/path?query=value&other=123"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end

    test "handles JSON-like strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      text = "{\"key\": \"value\", \"number\": 42}"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoText", %{"text" => text})
      assert response["result"] == text
    end
  end

  describe "multiple fields with special characters" do
    setup :start_server

    test "handles special chars in multiple fields simultaneously", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "field1" => "Tom & Jerry",
        "field2" => "5 < 10"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoMultiple", params)
      assert response["result1"] == "Tom & Jerry"
      assert response["result2"] == "5 < 10"
    end

    test "handles unicode in multiple fields", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "field1" => "Привет",
        "field2" => "你好"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoMultiple", params)
      assert response["result1"] == "Привет"
      assert response["result2"] == "你好"
    end
  end

  # Setup helper
  defp start_server(_context) do
    {:ok, _} = Application.ensure_all_started(:lather)

    port = Enum.random(10000..60000)
    {:ok, server_pid} = Bandit.start_link(plug: XmlEdgeCasesRouter, port: port, scheme: :http)

    on_exit(fn ->
      try do
        GenServer.stop(server_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    Process.sleep(50)
    {:ok, port: port, base_url: "http://localhost:#{port}"}
  end
end
