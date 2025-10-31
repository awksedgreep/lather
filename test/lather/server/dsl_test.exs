defmodule Lather.Server.DSLTest do
  use ExUnit.Case, async: true

  # Test module that uses the DSL
  defmodule TestService do
    use Lather.Server

    @service_name "TestService"

    soap_operation "GetUser" do
      description("Retrieves a user by ID")
      soap_action("http://example.com/GetUser")

      input do
        parameter("userId", :string, required: true, description: "User identifier")
        parameter("includeDetails", :boolean, required: false, default: false)
      end

      output do
        parameter("user", "User", description: "User information")
      end
    end

    soap_operation "CreateUser" do
      description("Creates a new user")
      soap_action("http://example.com/CreateUser")

      input do
        parameter("userData", "UserData", required: true)
      end

      output do
        parameter("userId", :string, required: true)
        parameter("success", :boolean, required: true)
      end
    end

    soap_operation "SimpleOperation" do
      # Minimal operation definition
    end

    soap_type "User" do
      type_description("User information")

      element("id", :string, required: true)
      element("name", :string, required: true)
      element("email", :string, required: false)
      element("created_at", :dateTime, required: true)
    end

    soap_type "UserData" do
      element("name", :string, required: true, description: "User's full name")
      element("email", :string, required: true)
      element("age", :int, required: false, min_occurs: 0, max_occurs: 1)
    end

    soap_auth do
      basic_auth(realm: "Test Service")
    end

    # Implement the operation functions
    def get_user(_params), do: {:ok, %{}}
    def create_user(_params), do: {:ok, %{}}
    def simple_operation(_params), do: {:ok, %{}}
  end

  defmodule TestServiceWithWSAuth do
    use Lather.Server

    soap_operation "SecureOperation" do
      description("A secure operation")
    end

    soap_auth do
      ws_security(required: true, timestamp: true)
    end

    def secure_operation(_params), do: {:ok, %{}}
  end

  defmodule TestServiceWithCustomAuth do
    use Lather.Server

    soap_operation "CustomOperation" do
      description("Operation with custom auth")
    end

    soap_auth do
      custom_auth(handler: MyApp.CustomAuth, options: [timeout: 5000])
    end

    def custom_operation(_params), do: {:ok, %{}}
  end

  describe "soap_operation macro" do
    test "defines operation with basic metadata" do
      operations = TestService.__soap_operations__()

      get_user_op = Enum.find(operations, &(&1.name == "GetUser"))
      assert get_user_op != nil
      assert get_user_op.description == "Retrieves a user by ID"
      assert get_user_op.soap_action == "http://example.com/GetUser"
      assert get_user_op.function_name == "get_user"
    end

    test "defines operation with minimal configuration" do
      operations = TestService.__soap_operations__()

      simple_op = Enum.find(operations, &(&1.name == "SimpleOperation"))
      assert simple_op != nil
      assert simple_op.function_name == "simple_operation"
      assert simple_op.description == nil
      assert simple_op.soap_action == nil
    end

    test "generates correct function names from operation names" do
      operations = TestService.__soap_operations__()

      create_user_op = Enum.find(operations, &(&1.name == "CreateUser"))
      assert create_user_op.function_name == "create_user"
    end
  end

  describe "input/output parameter definitions" do
    test "defines input parameters with various options" do
      operations = TestService.__soap_operations__()
      get_user_op = Enum.find(operations, &(&1.name == "GetUser"))

      assert length(get_user_op.input) == 2

      user_id_param = Enum.find(get_user_op.input, &(&1.name == "userId"))
      assert user_id_param.type == :string
      assert user_id_param.required == true
      assert user_id_param.description == "User identifier"

      include_details_param = Enum.find(get_user_op.input, &(&1.name == "includeDetails"))
      assert include_details_param.type == :boolean
      assert include_details_param.required == false
      assert include_details_param.default == false
    end

    test "defines output parameters" do
      operations = TestService.__soap_operations__()
      get_user_op = Enum.find(operations, &(&1.name == "GetUser"))

      assert length(get_user_op.output) == 1

      user_param = Enum.find(get_user_op.output, &(&1.name == "user"))
      assert user_param.type == "User"
      assert user_param.description == "User information"
    end

    test "defines multiple output parameters" do
      operations = TestService.__soap_operations__()
      create_user_op = Enum.find(operations, &(&1.name == "CreateUser"))

      assert length(create_user_op.output) == 2

      user_id_param = Enum.find(create_user_op.output, &(&1.name == "userId"))
      assert user_id_param.type == :string
      assert user_id_param.required == true

      success_param = Enum.find(create_user_op.output, &(&1.name == "success"))
      assert success_param.type == :boolean
      assert success_param.required == true
    end

    test "handles parameters with default values for all options" do
      operations = TestService.__soap_operations__()
      get_user_op = Enum.find(operations, &(&1.name == "GetUser"))

      user_id_param = Enum.find(get_user_op.input, &(&1.name == "userId"))
      assert user_id_param.min_occurs == 0
      assert user_id_param.max_occurs == 1
      assert user_id_param.default == nil
    end
  end

  describe "soap_type macro" do
    test "defines complex types with elements" do
      types = TestService.__soap_types__()

      user_type = Enum.find(types, &(&1.name == "User"))
      assert user_type != nil
      assert user_type.description == "User information"
      assert length(user_type.elements) == 4
    end

    test "defines elements with various options" do
      types = TestService.__soap_types__()
      user_type = Enum.find(types, &(&1.name == "User"))

      id_element = Enum.find(user_type.elements, &(&1.name == "id"))
      assert id_element.type == :string
      assert id_element.required == true

      email_element = Enum.find(user_type.elements, &(&1.name == "email"))
      assert email_element.type == :string
      assert email_element.required == false

      created_at_element = Enum.find(user_type.elements, &(&1.name == "created_at"))
      assert created_at_element.type == :dateTime
      assert created_at_element.required == true
    end

    test "defines elements with min/max occurs" do
      types = TestService.__soap_types__()
      user_data_type = Enum.find(types, &(&1.name == "UserData"))

      age_element = Enum.find(user_data_type.elements, &(&1.name == "age"))
      assert age_element.type == :int
      assert age_element.required == false
      assert age_element.min_occurs == 0
      assert age_element.max_occurs == 1
      assert age_element.description == nil

      name_element = Enum.find(user_data_type.elements, &(&1.name == "name"))
      assert name_element.description == "User's full name"
    end
  end

  describe "soap_auth macro" do
    test "defines basic authentication" do
      auth_config = TestService.__soap_auth__()

      assert auth_config.basic_auth != nil
      assert auth_config.basic_auth.realm == "Test Service"
      assert auth_config.basic_auth.required == true
    end

    test "defines WS-Security authentication" do
      auth_config = TestServiceWithWSAuth.__soap_auth__()

      assert auth_config.ws_security != nil
      assert auth_config.ws_security.required == true
      assert auth_config.ws_security.username_token == true
      assert auth_config.ws_security.timestamp == true
    end

    test "defines custom authentication" do
      auth_config = TestServiceWithCustomAuth.__soap_auth__()

      assert auth_config.custom_auth != nil
      assert auth_config.custom_auth.handler == MyApp.CustomAuth
      assert auth_config.custom_auth.options == [timeout: 5000]
    end
  end

  describe "default values and edge cases" do
    test "parameters have correct default values" do
      operations = TestService.__soap_operations__()
      get_user_op = Enum.find(operations, &(&1.name == "GetUser"))

      user_id_param = Enum.find(get_user_op.input, &(&1.name == "userId"))
      assert user_id_param.min_occurs == 0
      assert user_id_param.max_occurs == 1
      assert user_id_param.default == nil
    end

    test "elements have correct default values" do
      types = TestService.__soap_types__()
      user_type = Enum.find(types, &(&1.name == "User"))

      id_element = Enum.find(user_type.elements, &(&1.name == "id"))
      assert id_element.min_occurs == 0
      assert id_element.max_occurs == 1
      assert id_element.description == nil
    end

    test "basic auth has default realm" do
      defmodule TestServiceDefaultAuth do
        use Lather.Server

        soap_auth do
          basic_auth()
        end
      end

      auth_config = TestServiceDefaultAuth.__soap_auth__()
      assert auth_config.basic_auth.realm == "SOAP Service"
      assert auth_config.basic_auth.required == true
    end

    test "ws_security has correct defaults" do
      defmodule TestServiceDefaultWSAuth do
        use Lather.Server

        soap_auth do
          ws_security()
        end
      end

      auth_config = TestServiceDefaultWSAuth.__soap_auth__()
      assert auth_config.ws_security.required == true
      assert auth_config.ws_security.username_token == true
      assert auth_config.ws_security.timestamp == false
    end
  end

  describe "service introspection" do
    test "__soap_service__ returns service metadata" do
      service_info = TestService.__soap_service__()

      assert service_info.name == "TestService"
      assert service_info.namespace != nil
      assert service_info.operations == TestService.__soap_operations__()
      assert service_info.types == TestService.__soap_types__()
      assert service_info.authentication == TestService.__soap_auth__()
    end

    test "__soap_operation__ returns specific operation" do
      operation = TestService.__soap_operation__("GetUser")

      assert operation.name == "GetUser"
      assert operation.description == "Retrieves a user by ID"

      # Test non-existent operation
      assert TestService.__soap_operation__("NonExistent") == nil
    end

    test "service is properly marked as SOAP service" do
      assert function_exported?(TestService, :__soap_service__, 0)
      assert function_exported?(TestService, :__soap_operations__, 0)
      assert function_exported?(TestService, :__soap_types__, 0)
      assert function_exported?(TestService, :__soap_auth__, 0)
      assert function_exported?(TestService, :__soap_operation__, 1)
    end
  end

  describe "complex scenarios" do
    test "operation with both input and output parameters" do
      operations = TestService.__soap_operations__()
      create_user_op = Enum.find(operations, &(&1.name == "CreateUser"))

      # Input validation
      assert length(create_user_op.input) == 1
      user_data_param = List.first(create_user_op.input)
      assert user_data_param.name == "userData"
      assert user_data_param.type == "UserData"
      assert user_data_param.required == true

      # Output validation
      assert length(create_user_op.output) == 2
      output_names = Enum.map(create_user_op.output, & &1.name)
      assert "userId" in output_names
      assert "success" in output_names
    end

    test "complex type with multiple element types" do
      types = TestService.__soap_types__()
      user_data_type = Enum.find(types, &(&1.name == "UserData"))

      element_types = Enum.map(user_data_type.elements, &{&1.name, &1.type})

      expected_types = [
        {"name", :string},
        {"email", :string},
        {"age", :int}
      ]

      assert element_types == expected_types
    end

    test "operations can reference defined types" do
      operations = TestService.__soap_operations__()
      create_user_op = Enum.find(operations, &(&1.name == "CreateUser"))

      # Input references UserData type
      user_data_param = List.first(create_user_op.input)
      assert user_data_param.type == "UserData"

      # Verify UserData type exists
      types = TestService.__soap_types__()
      user_data_type = Enum.find(types, &(&1.name == "UserData"))
      assert user_data_type != nil
    end
  end

  describe "error cases and validation" do
    test "operations with missing function implementations are still defined" do
      # The DSL should define operations even if functions aren't implemented yet
      operations = TestService.__soap_operations__()

      assert length(operations) == 3
      operation_names = Enum.map(operations, & &1.name)
      assert "GetUser" in operation_names
      assert "CreateUser" in operation_names
      assert "SimpleOperation" in operation_names
    end

    test "multiple auth configurations can coexist" do
      defmodule TestServiceMultiAuth do
        use Lather.Server

        soap_auth do
          basic_auth(realm: "Multi Auth")
          ws_security(required: false)
        end
      end

      auth_config = TestServiceMultiAuth.__soap_auth__()
      assert auth_config.basic_auth != nil
      assert auth_config.ws_security != nil
      assert auth_config.basic_auth.realm == "Multi Auth"
      assert auth_config.ws_security.required == false
    end

    test "empty operation definitions work" do
      defmodule TestEmptyService do
        use Lather.Server

        soap_operation "EmptyOp" do
        end

        def empty_op(_params), do: {:ok, %{}}
      end

      operations = TestEmptyService.__soap_operations__()
      empty_op = List.first(operations)

      assert empty_op.name == "EmptyOp"
      assert empty_op.input == []
      assert empty_op.output == []
      assert empty_op.description == nil
      assert empty_op.soap_action == nil
    end
  end
end
