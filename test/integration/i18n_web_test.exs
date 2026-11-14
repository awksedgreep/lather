defmodule Lather.I18nWebTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule WebService do
    @moduledoc false
    use Lather.Server

    @service_name "WebService"
    @namespace "urn:web"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  defp fetch(port, path) do
    {:ok, response} =
      Lather.Http.Transport.get("http://127.0.0.1:#{port}#{path}")

    response.body
  end

  test "docs page renders in the requested language" do
    plug = {Lather.Server.EnhancedPlug, [service: WebService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    english = fetch(port, "/soap?docs")
    spanish = fetch(port, "/soap?docs&lang=es")
    german = fetch(port, "/soap?docs&lang=de")

    assert english =~ "API Documentation"
    assert spanish =~ "Documentación de la API"
    assert german =~ "API-Dokumentation"
  end

  test "web pages are accessible and responsive" do
    {:ok, store} = Lather.Persistence.start_link(name: :web_history)

    plug = {
      Lather.Server.EnhancedPlug,
      [service: WebService, enable_metrics: true, persistence_store: store]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    html = fetch(port, "/soap?dashboard")

    assert html =~ "lang=\"en\""
    assert html =~ "meta name=\"viewport\""
    assert html =~ "Skip to main content"
    assert html =~ "prefers-contrast"
    assert html =~ "aria-label"
    assert html =~ "max-width: 600px"
  end

  test "I18n falls back to English for unknown languages" do
    assert Lather.I18n.t("operations", "fr") == "Operations"
    assert Lather.I18n.t("operations", "es") == "Operaciones"
    assert Lather.I18n.t("unknown_key", "en") == "unknown_key"
    assert "en" in Lather.I18n.languages()
  end
end
