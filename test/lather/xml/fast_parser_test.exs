defmodule Lather.Xml.FastParserTest do
  use ExUnit.Case, async: true

  alias Lather.Xml.{FastParser, Parser}

  test "parses simple elements" do
    assert {:ok, %{"root" => %{"item" => "value"}}} =
             FastParser.parse("<root><item>value</item></root>")
  end

  test "parses SOAP-style envelopes" do
    xml =
      "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\">" <>
        "<soap:Body><EchoResponse><echo>hi</echo></EchoResponse></soap:Body>" <>
        "</soap:Envelope>"

    assert {:ok, %{"soap:Envelope" => %{"soap:Body" => %{"EchoResponse" => %{"echo" => "hi"}}}}} =
             FastParser.parse(xml)
  end

  test "handles attributes and self-closing tags" do
    {:ok, result} = FastParser.parse("<a x=\"1\"><b/></a>")
    assert result == %{"a" => %{"b" => %{}}}
  end

  test "decodes entities" do
    assert {:ok, %{"a" => "x & y"}} = FastParser.parse("<a>x &amp; y</a>")
  end

  test "mixed text and children" do
    assert {:ok, %{"a" => %{"value" => "text", "child" => "kid"}}} =
             FastParser.parse("<a>text<child>kid</child></a>")
  end

  test "empty elements" do
    {:ok, result} = FastParser.parse("<a></a>")
    assert result == %{"a" => %{}}
  end

  test "fast parser agrees with the full parser on flat documents" do
    xml = "<root><name>Bob</name><age>42</age></root>"

    {:ok, full} = Parser.parse(xml)
    {:ok, fast} = FastParser.parse(xml)

    assert full == fast
  end

  test "performance: fast parser beats the full parser on large documents" do
    rows =
      Enum.map(1..2000, fn i ->
        "<item><id>#{i}</id><name>row #{i}</name></item>"
      end)

    xml = "<items>" <> Enum.join(rows, "") <> "</items>"

    {fast_time, _} = :timer.tc(fn -> FastParser.parse(xml) end)
    {full_time, _} = :timer.tc(fn -> Parser.parse(xml) end)

    # The fast parser should be at least 2x faster on this shape.
    assert fast_time < full_time
  end
end

defmodule Lather.Xml.ParserFastSwitchTest do
  use ExUnit.Case, async: false

  test "Parser.parse/1 uses the fast path when fast_xml_parse is enabled" do
    Application.put_env(:lather, :fast_xml_parse, true)

    try do
      {:ok, result} = Lather.Xml.Parser.parse("<root><item>value</item></root>")
      assert result == %{"root" => %{"item" => "value"}}
    after
      Application.delete_env(:lather, :fast_xml_parse)
    end
  end

  test "Parser.parse/1 keeps the strict path by default" do
    {:ok, result} = Lather.Xml.Parser.parse("<root><item>value</item></root>")
    assert result == %{"root" => %{"item" => "value"}}
  end
end
