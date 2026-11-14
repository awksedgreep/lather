defmodule Lather.Soap.ProfileTest do
  use ExUnit.Case, async: true

  doctest Lather.Soap.Profile

  alias Lather.Soap.Profile

  test "valid SOAP 1.2 envelope passes" do
    xml = """
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Header><ws:Auth xmlns:ws="urn:auth" token="x"/></soap:Header>
      <soap:Body><Echo/></soap:Body>
    </soap:Envelope>
    """

    assert {:ok, []} = Profile.validate(xml)
  end

  test "missing body is reported" do
    xml = """
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Header><Auth xmlns="urn:auth"/></soap:Header>
    </soap:Envelope>
    """

    assert {:error, problems} = Profile.validate(xml)
    assert Enum.any?(problems, fn p -> p =~ "Body" end)
  end

  test "double body is reported" do
    xml = """
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Body><A/></soap:Body>
      <soap:Body><B/></soap:Body>
    </soap:Envelope>
    """

    assert {:error, problems} = Profile.validate(xml)
    assert Enum.any?(problems, fn p -> p =~ "exactly one Body" end)
  end

  test "header after body is reported" do
    xml = """
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Body><A/></soap:Body>
      <soap:Header><Auth/></soap:Header>
    </soap:Envelope>
    """

    assert {:error, problems} = Profile.validate(xml)
    assert Enum.any?(problems, fn p -> p =~ "Header must appear before Body" end)
  end

  test "unknown namespace is reported" do
    xml = """
    <env:Envelope xmlns:env="urn:custom">
      <env:Body><A/></env:Body>
    </env:Envelope>
    """

    assert {:error, problems} = Profile.validate(xml)
    assert Enum.any?(problems, fn p -> p =~ "namespace" end)
  end

  test "invalid mustUnderstand is reported" do
    xml = """
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Header><Auth soap:mustUnderstand="maybe"/></soap:Header>
      <soap:Body><A/></soap:Body>
    </soap:Envelope>
    """

    assert {:error, problems} = Profile.validate(xml)
    assert Enum.any?(problems, fn p -> p =~ "mustUnderstand" end)
  end

  test "valid mustUnderstand values pass" do
    xml = """
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Header><Auth soap:mustUnderstand="1"/></soap:Header>
      <soap:Body><A/></soap:Body>
    </soap:Envelope>
    """

    assert {:ok, []} = Profile.validate(xml)
  end
end
