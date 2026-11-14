defmodule Lather.Server.MustUnderstandTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lather.Server.EnhancedPlug

  defmodule HeaderService do
    use Lather.Server

    @service_name "HeaderService"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(_params), do: {:ok, %{"pong" => "pong"}}
  end

  def soap_body(header_xml) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Header>
        #{header_xml}
      </soap:Header>
      <soap:Body>
        <Ping xmlns="urn:example"/>
      </soap:Body>
    </soap:Envelope>
    """
  end

  test "mustUnderstand headers the service knows are accepted" do
    config = EnhancedPlug.init(service: HeaderService, understood_headers: ["AuthToken"])

    body = soap_body(~s(<AuthToken xmlns="urn:auth" soap:mustUnderstand="1">token</AuthToken>))

    response = conn(:post, "/soap", body) |> EnhancedPlug.call(config)
    assert response.status == 200
    assert response.resp_body =~ "pong"
  end

  test "unknown mustUnderstand headers produce a NotUnderstood fault" do
    config = EnhancedPlug.init(service: HeaderService, understood_headers: ["AuthToken"])

    body =
      soap_body(~s(<FutureHeader xmlns="urn:future" soap:mustUnderstand="1">x</FutureHeader>))

    response = conn(:post, "/soap", body) |> EnhancedPlug.call(config)
    assert response.status == 500
    assert response.resp_body =~ "NotUnderstood"
    assert response.resp_body =~ "FutureHeader"
  end

  test "headers without mustUnderstand are always accepted" do
    config = EnhancedPlug.init(service: HeaderService, understood_headers: ["AuthToken"])

    body = soap_body(~s(<FutureHeader xmlns="urn:future">x</FutureHeader>))

    response = conn(:post, "/soap", body) |> EnhancedPlug.call(config)
    assert response.status == 200
  end

  test "mustUnderstand=\"0\" is not enforced" do
    config = EnhancedPlug.init(service: HeaderService, understood_headers: [])

    body = soap_body(~s(<AnyHeader xmlns="urn:any" soap:mustUnderstand="0">x</AnyHeader>))

    response = conn(:post, "/soap", body) |> EnhancedPlug.call(config)
    assert response.status == 200
  end

  test "by default all headers are understood" do
    config = EnhancedPlug.init(service: HeaderService)

    body = soap_body(~s(<Whatever xmlns="urn:whatever" soap:mustUnderstand="true">x</Whatever>))

    response = conn(:post, "/soap", body) |> EnhancedPlug.call(config)
    assert response.status == 200
  end

  test "namespace-based understanding works" do
    config = EnhancedPlug.init(service: HeaderService, understood_headers: ["urn:auth"])

    body = soap_body(~s(<Token xmlns="urn:auth" soap:mustUnderstand="1">t</Token>))

    response = conn(:post, "/soap", body) |> EnhancedPlug.call(config)
    assert response.status == 200
  end
end
