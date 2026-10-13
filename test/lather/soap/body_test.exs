defmodule Lather.Soap.BodyTest do
  use ExUnit.Case, async: true

  alias Lather.Soap.Body
  alias Lather.Xml.Builder

  describe "serialize_params/1 - date/time and boolean values (issue #7)" do
    test "DateTime serializes to ISO 8601" do
      assert Body.serialize_params(~U[2026-01-02 03:04:05Z]) == "2026-01-02T03:04:05Z"
    end

    test "Date serializes to ISO 8601" do
      assert Body.serialize_params(~D[2026-01-02]) == "2026-01-02"
    end

    test "Time serializes to ISO 8601" do
      assert Body.serialize_params(~T[03:04:05]) == "03:04:05"
    end

    test "booleans serialize to true/false strings" do
      assert Body.serialize_params(true) == "true"
      assert Body.serialize_params(false) == "false"
    end

    test "date/time values nested in maps and lists serialize" do
      assert Body.serialize_params(%{
               "when" => ~U[2026-01-02 03:04:05Z],
               "dates" => [~D[2026-01-02], ~D[2026-01-03]],
               "nested" => %{"at" => ~T[03:04:05], "flag" => false}
             }) == %{
               "when" => "2026-01-02T03:04:05Z",
               "dates" => ["2026-01-02", "2026-01-03"],
               "nested" => %{"at" => "03:04:05", "flag" => "false"}
             }
    end

    test "a SOAP body with a DateTime parameter builds to XML" do
      element = Body.create(:Schedule, %{"startsAt" => ~U[2026-01-02 03:04:05Z]})
      {:ok, xml} = Builder.build(element)

      assert String.contains?(xml, "<startsAt>2026-01-02T03:04:05Z</startsAt>")
    end
  end

  test "nested strings remain raw until the XML builder renders them" do
    params = %{
      "notes" => ["Fish & Chips", "<tag>", "literal &amp;"],
      "account" => %{"password" => "A&B<123>"}
    }

    assert {:ok, xml} = Body.create(:Echo, params) |> Builder.build()
    assert {:ok, parsed} = Lather.Xml.Parser.parse(xml)
    assert parsed["Echo"]["notes"] == params["notes"]
    assert parsed["Echo"]["account"]["password"] == "A&B<123>"
  end

  describe "create/3 namespaces" do
    test "a default namespace survives XML rendering" do
      assert {:ok, xml} =
               Body.create(:Echo, %{message: "hello"}, namespace: "urn:example:echo")
               |> Builder.build()

      assert xml =~ ~s(<Echo xmlns="urn:example:echo">)
      assert {:ok, parsed} = Lather.Xml.Parser.parse(xml)
      assert parsed["Echo"]["message"] == "hello"
    end

    test "a prefixed operation declares the matching namespace" do
      assert {:ok, xml} =
               Body.create(:Echo, %{message: "hello"},
                 namespace: "urn:example:echo",
                 namespace_prefix: "e"
               )
               |> Builder.build()

      assert xml =~ ~s(<e:Echo xmlns:e="urn:example:echo">)
      {root, _} = :xmerl_scan.string(String.to_charlist(xml), namespace_conformant: true)
      assert elem(root, 0) == :xmlElement
    end
  end

  describe "validate_params/2" do
    test "required values and types are checked" do
      schema = %{"id" => [:required, :integer], "name" => [:required, :string]}

      assert :ok = Body.validate_params(%{"id" => 3, "name" => "Ada"}, schema)

      assert {:error, errors} = Body.validate_params(%{"id" => "3"}, schema)
      assert "id must be an integer" in errors
      assert "name is required" in errors
    end

    test "an absent optional string passes validation" do
      schema = %{"nickname" => [:optional, :string, {:max_length, 20}]}

      assert :ok = Body.validate_params(%{}, schema)
      assert :ok = Body.validate_params(%{"nickname" => nil}, schema)
    end

    test "maximum length counts characters and rejects longer strings" do
      schema = %{"name" => [:required, :string, {:max_length, 2}]}

      assert :ok = Body.validate_params(%{"name" => "é🙂"}, schema)

      assert {:error, ["name must be at most 2 characters"]} =
               Body.validate_params(%{"name" => "Ada"}, schema)
    end
  end
end
