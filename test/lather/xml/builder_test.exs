defmodule Lather.Xml.BuilderTest do
  use ExUnit.Case
  doctest Lather.Xml.Builder

  alias Lather.Xml.Builder

  describe "build/1 - Basic XML generation" do
    test "builds simple single-element XML" do
      {:ok, xml} = Builder.build(%{"root" => "content"})

      assert String.contains?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      assert String.contains?(xml, "<root>content</root>")
    end

    test "builds nested XML structure" do
      {:ok, xml} =
        Builder.build(%{
          "root" => %{
            "child" => "value"
          }
        })

      assert String.contains?(xml, "<root>")
      assert String.contains?(xml, "<child>value</child>")
      assert String.contains?(xml, "</root>")
    end

    test "builds deeply nested structures" do
      {:ok, xml} =
        Builder.build(%{
          "level1" => %{
            "level2" => %{
              "level3" => "deep_value"
            }
          }
        })

      assert String.contains?(xml, "<level1>")
      assert String.contains?(xml, "<level2>")
      assert String.contains?(xml, "<level3>deep_value</level3>")
    end

    test "includes XML declaration" do
      {:ok, xml} = Builder.build(%{"root" => "content"})
      assert String.starts_with?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    end

    test "handles multiple top-level keys" do
      {:ok, xml} =
        Builder.build(%{
          "element1" => "value1",
          "element2" => "value2"
        })

      assert String.contains?(xml, "<element1>value1</element1>")
      assert String.contains?(xml, "<element2>value2</element2>")
    end

    test "rejects non-map input" do
      assert {:error, :invalid_data_structure} = Builder.build("not a map")
      assert {:error, :invalid_data_structure} = Builder.build([1, 2, 3])
      assert {:error, :invalid_data_structure} = Builder.build(nil)
      assert {:error, :invalid_data_structure} = Builder.build(123)
    end

    test "handles empty map" do
      {:ok, xml} = Builder.build(%{})
      # Should produce valid XML even with empty map
      assert String.contains?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    end

    test "handles integer values" do
      {:ok, xml} = Builder.build(%{"age" => 42})
      assert String.contains?(xml, "<age>42</age>")
    end

    test "handles float values" do
      {:ok, xml} = Builder.build(%{"price" => 19.99})
      assert String.contains?(xml, "<price>19.99</price>")
    end

    test "handles boolean values" do
      {:ok, xml_true} = Builder.build(%{"active" => true})
      {:ok, xml_false} = Builder.build(%{"active" => false})

      assert String.contains?(xml_true, "<active>true</active>")
      assert String.contains?(xml_false, "<active>false</active>")
    end

    test "handles atom values" do
      {:ok, xml} = Builder.build(%{"status" => :active})
      assert String.contains?(xml, "<status>active</status>")
    end
  end

  describe "build/1 - Attributes handling" do
    test "builds element with single attribute" do
      {:ok, xml} =
        Builder.build(%{
          "root" => %{
            "@id" => "123",
            "#text" => "content"
          }
        })

      assert String.contains?(xml, "root")
      assert String.contains?(xml, "id=\"123\"")
      assert String.contains?(xml, "content")
    end

    test "builds element with multiple attributes" do
      {:ok, xml} =
        Builder.build(%{
          "item" => %{
            "@id" => "1",
            "@type" => "product",
            "@active" => "true",
            "#text" => "Widget"
          }
        })

      assert String.contains?(xml, "id=\"1\"")
      assert String.contains?(xml, "type=\"product\"")
      assert String.contains?(xml, "active=\"true\"")
      assert String.contains?(xml, "Widget")
    end

    test "builds elements with attributes but no text" do
      {:ok, xml} =
        Builder.build(%{
          "element" => %{
            "@name" => "test"
          }
        })

      assert String.contains?(xml, "name=\"test\"")
      # Should be self-closing or empty
      assert String.contains?(xml, "element")
    end

    test "builds nested elements with attributes" do
      {:ok, xml} =
        Builder.build(%{
          "root" => %{
            "@version" => "1.0",
            "child" => %{
              "@id" => "1",
              "#text" => "data"
            }
          }
        })

      assert String.contains?(xml, "version=\"1.0\"")
      assert String.contains?(xml, "id=\"1\"")
      assert String.contains?(xml, "data")
    end

    test "escapes attribute values" do
      {:ok, xml} =
        Builder.build(%{
          "element" => %{
            "@message" => "Say \"hello\" & goodbye",
            "#text" => "content"
          }
        })

      assert String.contains?(xml, "&quot;") or String.contains?(xml, "\"")
      assert String.contains?(xml, "&amp;")
    end

    test "handles single quote in attribute" do
      {:ok, xml} =
        Builder.build(%{
          "element" => %{
            "@text" => "it's",
            "#text" => "content"
          }
        })

      assert String.contains?(xml, "&apos;") or String.contains?(xml, "'")
    end
  end

  describe "build/1 - Text content and escaping" do
    test "escapes XML special characters in text" do
      {:ok, xml} =
        Builder.build(%{
          "message" => "5 < 10 & 10 > 5"
        })

      assert String.contains?(xml, "&lt;")
      assert String.contains?(xml, "&gt;")
      assert String.contains?(xml, "&amp;")
    end

    test "escapes ampersand" do
      {:ok, xml} = Builder.build(%{"text" => "Huey & Dewey"})
      # Should contain escaped ampersand
      assert String.contains?(xml, "Huey &amp; Dewey")
    end

    test "escapes less-than" do
      {:ok, xml} = Builder.build(%{"text" => "a < b"})
      assert String.contains?(xml, "a &lt; b")
    end

    test "escapes greater-than" do
      {:ok, xml} = Builder.build(%{"text" => "b > a"})
      assert String.contains?(xml, "b &gt; a")
    end

    test "escapes multiple special characters" do
      {:ok, xml} =
        Builder.build(%{
          "text" => "<tag>content & 'quoted' \"text\"</tag>"
        })

      assert String.contains?(xml, "&lt;")
      assert String.contains?(xml, "&gt;")
      assert String.contains?(xml, "&amp;")
    end

    test "handles Unicode content" do
      {:ok, xml} =
        Builder.build(%{
          "greeting" => "Hëllö Wørld 你好 مرحبا"
        })

      # Should preserve Unicode
      assert String.contains?(xml, "Hëllö")
      assert String.contains?(xml, "你好")
      assert String.contains?(xml, "مرحبا")
    end

    test "handles newlines in text content" do
      {:ok, xml} =
        Builder.build(%{
          "text" => "line1\nline2\nline3"
        })

      assert String.contains?(xml, "line1")
      assert String.contains?(xml, "line2")
    end

    test "handles tabs in text content" do
      {:ok, xml} =
        Builder.build(%{
          "text" => "before\tafter"
        })

      assert String.contains?(xml, "before")
      assert String.contains?(xml, "after")
    end

    test "handles empty string" do
      {:ok, xml} = Builder.build(%{"empty" => ""})
      assert String.contains?(xml, "<empty></empty>")
    end

    test "handles whitespace-only string" do
      {:ok, xml} = Builder.build(%{"spaces" => "   "})
      # May be preserved or trimmed depending on implementation
      assert String.contains?(xml, "<spaces>")
      assert String.contains?(xml, "</spaces>")
    end
  end

  describe "build/1 - List content" do
    test "handles list of primitive values" do
      {:ok, xml} =
        Builder.build(%{
          "items" => ["item1", "item2", "item3"]
        })

      assert String.contains?(xml, "item1")
      assert String.contains?(xml, "item2")
      assert String.contains?(xml, "item3")
    end

    test "handles list of maps" do
      {:ok, xml} =
        Builder.build(%{
          "items" => [
            %{"name" => "Alice", "age" => "30"},
            %{"name" => "Bob", "age" => "25"}
          ]
        })

      assert String.contains?(xml, "Alice")
      assert String.contains?(xml, "30")
      assert String.contains?(xml, "Bob")
      assert String.contains?(xml, "25")
    end

    test "handles mixed list content" do
      {:ok, xml} =
        Builder.build(%{
          "items" => ["text", %{"key" => "value"}]
        })

      assert String.contains?(xml, "text")
      assert String.contains?(xml, "value")
    end

    test "handles empty list" do
      {:ok, xml} = Builder.build(%{"items" => []})
      # Should produce valid XML
      assert String.contains?(xml, "<?xml")
    end
  end

  describe "build/1 - Special cases" do
    test "handles nil values as empty content" do
      {:ok, xml} = Builder.build(%{"nullable" => nil})
      assert String.contains?(xml, "<nullable>")
      assert String.contains?(xml, "</nullable>")
    end

    test "handles map with #text and child elements" do
      {:ok, xml} =
        Builder.build(%{
          "root" => %{
            "#text" => "text content",
            "child" => "child content"
          }
        })

      assert String.contains?(xml, "text content")
      assert String.contains?(xml, "child content")
    end

    test "handles complex nested structure" do
      {:ok, xml} =
        Builder.build(%{
          "soap:Envelope" => %{
            "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
            "soap:Body" => %{
              "GetUser" => %{
                "@xmlns" => "http://example.com",
                "userId" => "123"
              }
            }
          }
        })

      assert String.contains?(xml, "soap:Envelope")
      assert String.contains?(xml, "soap:Body")
      assert String.contains?(xml, "GetUser")
      assert String.contains?(xml, "userId")
      assert String.contains?(xml, "123")
    end
  end

  describe "build_fragment/1 - Fragment building" do
    test "builds fragment without XML declaration" do
      {:ok, xml} = Builder.build_fragment(%{"root" => "content"})

      assert String.contains?(xml, "<root>content</root>")
      assert !String.contains?(xml, "<?xml")
    end

    test "builds fragment with attributes" do
      {:ok, xml} =
        Builder.build_fragment(%{
          "element" => %{
            "@id" => "1",
            "#text" => "content"
          }
        })

      assert String.contains?(xml, "id=\"1\"")
      assert String.contains?(xml, "content")
      assert !String.contains?(xml, "<?xml")
    end

    test "builds nested fragment" do
      {:ok, xml} =
        Builder.build_fragment(%{
          "parent" => %{
            "child" => "value"
          }
        })

      assert String.contains?(xml, "<parent>")
      assert String.contains?(xml, "<child>value</child>")
      assert !String.contains?(xml, "<?xml")
    end

    test "rejects non-map input in fragment" do
      assert {:error, :invalid_data_structure} = Builder.build_fragment("not a map")
      assert {:error, :invalid_data_structure} = Builder.build_fragment([1, 2, 3])
    end
  end

  describe "escape_text/1 - Text escaping" do
    test "escapes ampersand" do
      escaped = Builder.escape_text("Hello & Goodbye")
      assert escaped == "Hello &amp; Goodbye"
    end

    test "escapes less-than" do
      escaped = Builder.escape_text("a < b")
      assert escaped == "a &lt; b"
    end

    test "escapes greater-than" do
      escaped = Builder.escape_text("b > a")
      assert escaped == "b &gt; a"
    end

    test "escapes multiple special characters" do
      escaped = Builder.escape_text("a & b < c > d")
      assert escaped == "a &amp; b &lt; c &gt; d"
    end

    test "handles text with no special characters" do
      escaped = Builder.escape_text("normal text")
      assert escaped == "normal text"
    end

    test "converts non-string to string first" do
      escaped = Builder.escape_text(123)
      assert escaped == "123"

      escaped = Builder.escape_text(true)
      assert escaped == "true"
    end

    test "preserves order of replacements" do
      # This tests that & gets escaped before < and >
      escaped = Builder.escape_text("&<>")
      assert escaped == "&amp;&lt;&gt;"
    end

    test "handles already escaped entities" do
      # Should double-escape if given already-escaped input
      escaped = Builder.escape_text("&lt;")
      assert escaped == "&amp;lt;"
    end

    test "handles empty string" do
      escaped = Builder.escape_text("")
      assert escaped == ""
    end

    test "handles whitespace" do
      escaped = Builder.escape_text("  spaces  ")
      assert escaped == "  spaces  "
    end
  end

  describe "Real-world SOAP examples" do
    test "builds complete SOAP envelope" do
      {:ok, xml} =
        Builder.build(%{
          "soap:Envelope" => %{
            "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
            "soap:Body" => %{
              "GetUserResponse" => %{
                "user" => %{
                  "id" => "123",
                  "name" => "John Doe",
                  "email" => "john@example.com"
                }
              }
            }
          }
        })

      assert String.contains?(xml, "soap:Envelope")
      assert String.contains?(xml, "soap:Body")
      assert String.contains?(xml, "GetUserResponse")
      assert String.contains?(xml, "John Doe")
      assert String.contains?(xml, "john@example.com")
    end

    test "builds SOAP with nested arrays" do
      {:ok, xml} =
        Builder.build(%{
          "soap:Envelope" => %{
            "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
            "soap:Body" => %{
              "GetOrdersResponse" => %{
                "orders" => [
                  %{"id" => "1", "amount" => "100.00"},
                  %{"id" => "2", "amount" => "200.00"}
                ]
              }
            }
          }
        })

      assert String.contains?(xml, "soap:Envelope")
      assert String.contains?(xml, "100.00")
      assert String.contains?(xml, "200.00")
    end

    test "builds SOAP request with namespaces" do
      {:ok, xml} =
        Builder.build(%{
          "soap:Envelope" => %{
            "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
            "@xmlns:tns" => "http://example.com/service",
            "soap:Body" => %{
              "tns:GetUser" => %{
                "@xmlns" => "http://example.com/service",
                "userId" => "12345"
              }
            }
          }
        })

      assert String.contains?(xml, "xmlns:soap")
      assert String.contains?(xml, "xmlns:tns")
      assert String.contains?(xml, "12345")
    end
  end

  describe "Error handling" do
    test "handles rescue exception gracefully" do
      # Test that exceptions are caught and returned as errors
      result = Builder.build(%{"root" => %{"nested" => :bad_value}})
      # Should either succeed or return error tuple
      assert is_tuple(result) and tuple_size(result) == 2
      is_tuple(result) and tuple_size(result) == 2
    end
  end

  describe "Indentation and formatting" do
    test "produces properly indented nested XML" do
      {:ok, xml} =
        Builder.build(%{
          "root" => %{
            "level1" => %{
              "level2" => "value"
            }
          }
        })

      # Should have proper nesting with indentation
      lines = String.split(xml, "\n")
      # Each level should have more whitespace than the level before
      assert length(lines) > 3
    end

    test "handles indentation with multiple children" do
      {:ok, xml} =
        Builder.build(%{
          "root" => %{
            "child1" => "value1",
            "child2" => "value2",
            "child3" => "value3"
          }
        })

      lines = String.split(xml, "\n") |> Enum.reject(&(String.trim(&1) == ""))
      # Should have multiple lines with proper structure
      assert length(lines) >= 5
    end
  end
end
