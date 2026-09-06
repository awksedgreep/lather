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
end
