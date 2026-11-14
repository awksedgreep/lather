defmodule Lather.Wsdl.SchemaTest do
  use ExUnit.Case, async: true

  doctest Lather.Wsdl.Schema

  defmodule ExampleService do
    @moduledoc false
    use Lather.Server

    @service_name "ExampleService"
    @namespace "urn:example"

    soap_operation "Register" do
      input do
        parameter("email", :string, required: true, pattern: "^[a-z]+@[a-z]+$")
        parameter("age", :integer, min: 18, max: 120)
        parameter("role", :string, enum: ["admin", "user"], default: "user")
      end

      output do
        parameter("ok", :boolean)
      end
    end

    def register(params), do: {:ok, %{"ok" => true, "params" => params}}
  end

  test "generates XSD elements for operations" do
    schema = Lather.Wsdl.Schema.from_operations(ExampleService.__soap_operations__())

    assert schema =~ "<xs:element name=\"Register\""
    assert schema =~ "type=\"xs:integer\""
    assert schema =~ "use=\"required\""
    assert schema =~ "default=\"user\""
  end

  test "client-side validation accepts good params" do
    assert {:ok, params} =
             Lather.Wsdl.Schema.validate(ExampleService, "Register", %{
               "email" => "a@b",
               "age" => 30
             })

    assert params["role"] == "user"
  end

  test "client-side validation rejects bad params" do
    assert {:error, [reason]} =
             Lather.Wsdl.Schema.validate(ExampleService, "Register", %{
               "email" => "BAD",
               "age" => 7
             })

    assert reason =~ "email"
  end

  test "unknown operation is an error" do
    assert {:error, ["unknown operation: Nope"]} =
             Lather.Wsdl.Schema.validate(ExampleService, "Nope", %{})
  end
end
