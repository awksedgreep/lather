defmodule Lather.TypesTest do
  use ExUnit.Case, async: false

  alias Lather.Types.{Generator, Mapper}

  @user_type %{
    name: "User",
    category: :complex_type,
    target_namespace: "urn:example:types",
    elements: [
      %{name: "name", type: "xsd:string", min_occurs: "1", max_occurs: "1"},
      %{name: "age", type: "xsd:int", min_occurs: "1", max_occurs: "1"},
      %{name: "active", type: "xsd:boolean", min_occurs: "1", max_occurs: "1"},
      %{name: "tags", type: "xsd:string", min_occurs: "0", max_occurs: "unbounded"},
      %{name: "address", type: "tns:Address", min_occurs: "0", max_occurs: "1"},
      %{name: "contacts", type: "tns:Address", min_occurs: "0", max_occurs: "unbounded"}
    ]
  }

  @address_type %{
    name: "Address",
    category: :complex_type,
    target_namespace: "urn:example:types",
    elements: [%{name: "street", type: "xsd:string", min_occurs: "1", max_occurs: "1"}]
  }

  @service_info %{
    types: [@user_type, @address_type],
    namespaces: %{"tns" => "urn:example:types"},
    target_namespace: "urn:example:types"
  }

  test "mapper converts a parsed complex type and serializes it back" do
    context = Mapper.create_context(@service_info)

    xml_data = %{
      "name" => "Ada",
      "age" => "30",
      "active" => "false",
      "tags" => ["admin", "editor"]
    }

    assert {:ok, user} = Mapper.xml_to_elixir(xml_data, "User", context)
    assert user == %{name: "Ada", age: 30, active: false, tags: ["admin", "editor"]}
    assert :ok = Mapper.validate_type(user, "User", context)
    assert {:ok, ^xml_data} = Mapper.elixir_to_xml(user, "User", context)
  end

  test "mapper reports missing required fields and invalid array shape" do
    context = Mapper.create_context(@service_info)

    assert {:error, {:missing_required_field, "name"}} =
             Mapper.validate_type(%{age: 30, active: false}, "User", context)

    assert {:error, {:expected_array, "tags"}} =
             Mapper.validate_type(
               %{name: "Ada", age: 30, active: false, tags: "admin"},
               "User",
               context
             )
  end

  test "mapper preserves nested complex values and repeated complex values" do
    context = Mapper.create_context(@service_info)

    xml_data = %{
      "name" => "Ada",
      "age" => "30",
      "active" => "true",
      "address" => %{"street" => "Main"},
      "contacts" => [%{"street" => "First"}, %{"street" => "Second"}]
    }

    assert {:ok, user} = Mapper.xml_to_elixir(xml_data, "User", context)
    assert user.address == %{street: "Main"}
    assert user.contacts == [%{street: "First"}, %{street: "Second"}]
    assert {:ok, ^xml_data} = Mapper.elixir_to_xml(user, "User", context)
  end

  test "generated structs accept parsed values and serialize them" do
    assert {:ok, modules} =
             Generator.generate_structs(@service_info,
               module_prefix: Lather.TypesTest.Generated,
               include_only: ["User"]
             )

    assert is_list(modules)
    assert Generator.struct_exists?("User", modules)

    assert {:ok, user} =
             Generator.create_struct_instance(
               %{
                 "name" => "Ada",
                 "age" => "30",
                 "active" => "false",
                 "tags" => ["admin", "editor"]
               },
               "User",
               modules
             )

    assert user.name == "Ada"
    assert user.age == 30
    assert user.active == false
    assert user.tags == ["admin", "editor"]

    assert Generator.struct_to_xml(user, %{}) ==
             %{
               "name" => "Ada",
               "age" => "30",
               "active" => "false",
               "tags" => ["admin", "editor"]
             }
  end
end
