defmodule Lather.Server.HtmlEscapeTest do
  @moduledoc """
  The built-in dashboard, docs and error pages escape service/operation
  metadata instead of interpolating it raw (follow-up to issue #32).
  """
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lather.Server.EnhancedPlug

  defmodule EscapeService do
    @moduledoc false
    use Lather.Server

    @service_name "Escape & <script>alert(1)</script> Service"

    soap_operation "Get<script>alert(1)</script>" do
      description("Fish & Chips <b>")

      input do
        parameter("value<script>", :string, required: true)
      end

      output do
        parameter("result", :string)
      end
    end
  end

  defp request(method, path) do
    conn(method, path) |> EnhancedPlug.call(EnhancedPlug.init(service: EscapeService))
  end

  test "the dashboard escapes service and operation metadata" do
    response = request(:get, "/soap?dashboard")
    body = response.resp_body

    assert response.status == 200
    assert body =~ "Escape &amp; &lt;script&gt;alert(1)&lt;/script&gt; Service"
    refute body =~ "<script>alert(1)</script>"
  end

  test "the docs page escapes operation names, descriptions and parameters" do
    response = request(:get, "/soap?docs")
    body = response.resp_body

    assert response.status == 200
    assert body =~ "Get&lt;script&gt;alert(1)&lt;/script&gt;"
    assert body =~ "Fish &amp; Chips &lt;b&gt;"
    assert body =~ "value&lt;script&gt;"
    refute body =~ "<script>alert(1)</script>"
  end

  test "error pages escape the message" do
    response = request(:get, "/soap?op=<script>alert(1)</script>")
    body = response.resp_body

    assert response.status == 404
    assert body =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute body =~ "<script>alert(1)</script>"
  end
end
