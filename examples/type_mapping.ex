defmodule TypeMappingExample do
  @moduledoc """
  Example of using Lather's type mapping and struct generation features.

  This example demonstrates:
  - Dynamic struct generation from WSDL types
  - Type validation and conversion
  - Custom type mappers
  - Working with complex nested structures
  """

  def run do
    IO.puts("Type Mapping Example")
    IO.puts("===================")

    # Simulate WSDL types that would be extracted from a real WSDL
    wsdl_types = sample_wsdl_types()

    demo_struct_generation(wsdl_types)
    demo_type_validation(wsdl_types)
    demo_custom_type_mapping()
    demo_complex_nested_types()
  end

  defp demo_struct_generation(wsdl_types) do
    IO.puts("\n🏗️  Generating Elixir structs from WSDL types...")

    case Lather.Types.Generator.generate_structs(wsdl_types, "MyApp.Types") do
      {:ok, modules} ->
        IO.puts("✓ Generated #{length(modules)} struct modules:")
        Enum.each(modules, fn module ->
          IO.puts("   - #{inspect(module)}")
        end)

        # Demonstrate using generated structs
        demo_struct_usage()

      {:error, error} ->
        IO.puts("✗ Failed to generate structs: #{inspect(error)}")
    end
  end

  defp demo_struct_usage do
    IO.puts("\n📝 Using generated structs...")

    # This would use the generated modules in a real scenario
    # For demonstration, we'll show the concept with maps

    user_data = %{
      "personalInfo" => %{
        "firstName" => "John",
        "lastName" => "Doe",
        "email" => "john@example.com",
        "birthDate" => "1990-05-15"
      },
      "workInfo" => %{
        "employeeId" => "EMP001",
        "department" => "Engineering",
        "title" => "Software Engineer",
        "salary" => 75000.00
      },
      "preferences" => %{
        "notifications" => true,
        "theme" => "dark",
        "language" => "en"
      }
    }

    IO.puts("✓ Created user struct with data:")
    IO.puts("   Name: #{user_data["personalInfo"]["firstName"]} #{user_data["personalInfo"]["lastName"]}")
    IO.puts("   Department: #{user_data["workInfo"]["department"]}")
    IO.puts("   Email: #{user_data["personalInfo"]["email"]}")
  end

  defp demo_type_validation(wsdl_types) do
    IO.puts("\n✅ Demonstrating type validation...")

    # Valid data
    valid_user = %{
      "firstName" => "Jane",
      "lastName" => "Smith",
      "email" => "jane@example.com",
      "age" => 30
    }

    case Lather.Types.Mapper.validate_type(valid_user, wsdl_types["User"], []) do
      :ok ->
        IO.puts("✓ Valid user data passed validation")
      {:error, error} ->
        IO.puts("✗ Validation failed: #{inspect(error)}")
    end

    # Invalid data
    invalid_user = %{
      "firstName" => "Bob",
      "lastName" => nil,  # Invalid - should be string
      "email" => "not-an-email",  # Invalid format
      "age" => "thirty"  # Invalid - should be integer
    }

    case Lather.Types.Mapper.validate_type(invalid_user, wsdl_types["User"], []) do
      :ok ->
        IO.puts("✓ Invalid user data somehow passed validation")
      {:error, error} ->
        IO.puts("✗ Invalid user data correctly failed validation:")
        IO.puts("   #{Lather.Error.format_error(error)}")
    end
  end

  defp demo_custom_type_mapping do
    IO.puts("\n🔄 Demonstrating custom type mapping...")

    # XML data that needs custom parsing
    xml_data = %{
      "User" => %{
        "PersonalInfo" => %{
          "Name" => "John Doe",
          "BirthDate" => "1990-05-15T00:00:00Z",
          "ContactInfo" => %{
            "Email" => "john@example.com",
            "Phone" => "+1-555-0123"
          }
        },
        "Preferences" => %{
          "StringList" => "item1,item2,item3",  # Comma-separated string
          "DateRange" => "2024-01-01/2024-12-31"  # Date range format
        }
      }
    }

    # Custom mappers for special formats
    custom_mappers = %{
      "StringList" => &parse_comma_separated_list/1,
      "DateRange" => &parse_date_range/1,
      "DateTime" => &parse_iso_datetime/1
    }

    case Lather.Types.Mapper.xml_to_elixir(xml_data, sample_wsdl_types(), custom_parsers: custom_mappers) do
      {:ok, elixir_data} ->
        IO.puts("✓ Successfully mapped XML to Elixir with custom parsers:")
        IO.inspect(elixir_data, pretty: true)

      {:error, error} ->
        IO.puts("✗ Custom mapping failed: #{inspect(error)}")
    end
  end

  defp demo_complex_nested_types do
    IO.puts("\n🏢 Working with complex nested enterprise data...")

    # Complex enterprise data structure
    enterprise_data = %{
      "organization" => %{
        "company" => %{
          "name" => "Acme Corporation",
          "address" => %{
            "street" => "123 Business Ave",
            "city" => "Metropolis",
            "state" => "NY",
            "zipCode" => "10001",
            "country" => "USA"
          },
          "contact" => %{
            "phone" => "+1-555-ACME",
            "email" => "info@acme.com",
            "website" => "https://acme.com"
          }
        },
        "departments" => [
          %{
            "name" => "Engineering",
            "budget" => 2500000.00,
            "employees" => [
              %{
                "id" => "ENG001",
                "personalInfo" => %{
                  "firstName" => "Alice",
                  "lastName" => "Johnson",
                  "title" => "Senior Engineer"
                },
                "skills" => ["Elixir", "Phoenix", "PostgreSQL"],
                "projects" => [
                  %{
                    "name" => "Project Alpha",
                    "status" => "active",
                    "deadline" => "2024-06-30"
                  }
                ]
              }
            ]
          },
          %{
            "name" => "Marketing",
            "budget" => 1500000.00,
            "employees" => [
              %{
                "id" => "MKT001",
                "personalInfo" => %{
                  "firstName" => "Bob",
                  "lastName" => "Wilson",
                  "title" => "Marketing Manager"
                },
                "skills" => ["Digital Marketing", "Analytics", "Campaign Management"],
                "projects" => []
              }
            ]
          }
        ]
      }
    }

    # Convert to XML for SOAP request
    case Lather.Types.Mapper.elixir_to_xml(enterprise_data, sample_complex_types(), []) do
      {:ok, xml_structure} ->
        IO.puts("✓ Successfully converted complex data to XML structure")
        xml_string = Lather.XML.Builder.build(xml_structure)
        IO.puts("   XML size: #{byte_size(xml_string)} bytes")

        # Show a snippet of the XML
        snippet = String.slice(xml_string, 0, 200)
        IO.puts("   XML snippet: #{snippet}...")

        # Parse it back
        case Lather.XML.Parser.parse(xml_string) do
          {:ok, parsed_back} ->
            IO.puts("✓ Successfully parsed XML back to Elixir data")

            # Verify round-trip integrity
            verify_round_trip(enterprise_data, parsed_back)

          {:error, error} ->
            IO.puts("✗ Failed to parse XML back: #{inspect(error)}")
        end

      {:error, error} ->
        IO.puts("✗ Failed to convert to XML: #{inspect(error)}")
    end
  end

  # Helper functions for custom type parsing
  defp parse_comma_separated_list(value) when is_binary(value) do
    {:ok, String.split(value, ",", trim: true)}
  end
  defp parse_comma_separated_list(_), do: {:error, :invalid_format}

  defp parse_date_range(value) when is_binary(value) do
    case String.split(value, "/") do
      [start_date, end_date] ->
        {:ok, %{start: start_date, end: end_date}}
      _ ->
        {:error, :invalid_date_range_format}
    end
  end
  defp parse_date_range(_), do: {:error, :invalid_format}

  defp parse_iso_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}
      {:error, reason} ->
        {:error, {:invalid_datetime, reason}}
    end
  end
  defp parse_iso_datetime(_), do: {:error, :invalid_format}

  defp verify_round_trip(original, parsed) do
    # Simple verification - in practice you'd want more thorough checking
    org_name = get_in(original, ["organization", "company", "name"])
    parsed_name = get_in(parsed, ["organization", "company", "name"])

    if org_name == parsed_name do
      IO.puts("✓ Round-trip verification successful")
    else
      IO.puts("✗ Round-trip verification failed")
      IO.puts("   Original: #{org_name}")
      IO.puts("   Parsed: #{parsed_name}")
    end
  end

  # Sample WSDL types for demonstration
  defp sample_wsdl_types do
    %{
      "User" => %{
        type: :complex,
        elements: %{
          "firstName" => %{type: :string, required: true},
          "lastName" => %{type: :string, required: true},
          "email" => %{type: :string, required: true, format: :email},
          "age" => %{type: :integer, required: false, min: 0, max: 150},
          "personalInfo" => %{type: "PersonalInfo", required: false},
          "workInfo" => %{type: "WorkInfo", required: false},
          "preferences" => %{type: "UserPreferences", required: false}
        }
      },
      "PersonalInfo" => %{
        type: :complex,
        elements: %{
          "firstName" => %{type: :string, required: true},
          "lastName" => %{type: :string, required: true},
          "email" => %{type: :string, required: true},
          "birthDate" => %{type: :date, required: false},
          "address" => %{type: "Address", required: false}
        }
      },
      "WorkInfo" => %{
        type: :complex,
        elements: %{
          "employeeId" => %{type: :string, required: true},
          "department" => %{type: :string, required: true},
          "title" => %{type: :string, required: true},
          "salary" => %{type: :decimal, required: false}
        }
      },
      "UserPreferences" => %{
        type: :complex,
        elements: %{
          "notifications" => %{type: :boolean, required: false, default: true},
          "theme" => %{type: :string, required: false, enum: ["light", "dark"]},
          "language" => %{type: :string, required: false, default: "en"}
        }
      },
      "Address" => %{
        type: :complex,
        elements: %{
          "street" => %{type: :string, required: true},
          "city" => %{type: :string, required: true},
          "state" => %{type: :string, required: false},
          "zipCode" => %{type: :string, required: true},
          "country" => %{type: :string, required: true}
        }
      }
    }
  end

  defp sample_complex_types do
    %{
      "Organization" => %{
        type: :complex,
        elements: %{
          "company" => %{type: "Company", required: true},
          "departments" => %{type: "Department", array: true, required: true}
        }
      },
      "Company" => %{
        type: :complex,
        elements: %{
          "name" => %{type: :string, required: true},
          "address" => %{type: "Address", required: true},
          "contact" => %{type: "ContactInfo", required: true}
        }
      },
      "Department" => %{
        type: :complex,
        elements: %{
          "name" => %{type: :string, required: true},
          "budget" => %{type: :decimal, required: true},
          "employees" => %{type: "Employee", array: true, required: false}
        }
      },
      "Employee" => %{
        type: :complex,
        elements: %{
          "id" => %{type: :string, required: true},
          "personalInfo" => %{type: "PersonalInfo", required: true},
          "skills" => %{type: :string, array: true, required: false},
          "projects" => %{type: "Project", array: true, required: false}
        }
      },
      "Project" => %{
        type: :complex,
        elements: %{
          "name" => %{type: :string, required: true},
          "status" => %{type: :string, required: true, enum: ["active", "completed", "cancelled"]},
          "deadline" => %{type: :date, required: false}
        }
      },
      "ContactInfo" => %{
        type: :complex,
        elements: %{
          "phone" => %{type: :string, required: false},
          "email" => %{type: :string, required: false},
          "website" => %{type: :string, required: false}
        }
      }
    }
  end
end

# Run the example
if __name__ == :main do
  TypeMappingExample.run()
end
