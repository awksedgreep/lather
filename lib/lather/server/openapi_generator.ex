defmodule Lather.Server.OpenAPIGenerator do
  @moduledoc """
  Generates OpenAPI 3.1 specifications from Lather SOAP service definitions.

  The generated document describes the service's JSON/REST endpoints
  (`POST {base_path}/api/{OperationName}`), which are the protocol an
  OpenAPI toolchain can consume: spec validators, code generators such as
  Infusion, Swagger UI, and OpenAPI clients all work against these paths.

  It also documents the built-in observability endpoints
  (`GET {base_path}/health` and `GET {base_path}/metrics`) so Swagger UI and
  OpenAPI clients can discover them. Pass `health_path: nil` or
  `metrics_path: nil` to omit an endpoint your application serves itself, or
  a different path to reflect a relocated one.

  ## Usage

      service_info = MyApp.UserService.__soap_service__()
      spec = Lather.Server.OpenAPIGenerator.generate(service_info, "http://localhost:4000/soap")
      Jason.encode!(spec)

  ## Options

    - `:version` - API version reported in `info.version`. Defaults to the
      service's `@api_version` attribute, or `"1.0.0"` when neither is set.
    - `:description` - description reported in `info.description`
  """

  @integer_types ~w(int integer long short byte unsignedInt unsignedLong unsignedShort unsignedByte)
  @decimal_types ~w(decimal float double)
  @datetime_types ~w(dateTime datetime)

  @doc """
  Generates an OpenAPI 3.1 document (as a map) for a service.
  """
  def generate(service_info, base_url, opts \\ []) do
    version =
      Keyword.get(opts, :version) ||
        Map.get(service_info, :version) ||
        "1.0.0"

    description = Keyword.get(opts, :description)

    schemas = build_component_schemas(service_info)
    schema_names = Map.keys(schemas)
    paths = build_paths(service_info, schema_names, opts)

    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "#{service_info.name} API",
        "version" => version,
        "description" =>
          description ||
            "REST/JSON interface for the #{service_info.name} SOAP service. " <>
              "The same operations are also available over SOAP 1.1 and SOAP 1.2."
      },
      "servers" => [%{"url" => normalize_url(base_url)}],
      "paths" => paths,
      "components" => %{"schemas" => schemas}
    }
  end

  defp normalize_url(url) do
    url |> String.trim() |> String.trim_trailing("/")
  end

  defp build_paths(service_info, schema_names, opts) do
    operations =
      service_info.operations
      |> Enum.reduce(%{}, fn operation, acc ->
        Map.put(
          acc,
          "/api/#{operation.name}",
          %{"post" => build_operation(operation, schema_names)}
        )
      end)

    paths = Map.merge(operations, observability_paths(opts))
    paths
  end

  defp observability_paths(opts) do
    %{}
    |> maybe_put_path(Keyword.get(opts, :health_path, "/health"), health_spec())
    |> maybe_put_path(Keyword.get(opts, :metrics_path, "/metrics"), metrics_spec())
  end

  defp maybe_put_path(paths, nil, _spec), do: paths
  defp maybe_put_path(paths, path, spec), do: Map.put(paths, path, spec)

  defp health_spec do
    %{
      "get" => %{
        "operationId" => "health",
        "summary" => "Service health check",
        "tags" => ["Observability"],
        "responses" => %{
          "200" => %{
            "description" => "Service is running",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "required" => ["status", "service", "operations", "uptime_seconds"],
                  "properties" => %{
                    "status" => %{"type" => "string"},
                    "service" => %{"type" => "string"},
                    "version" => %{"type" => "string"},
                    "operations" => %{"type" => "integer"},
                    "uptime_seconds" => %{"type" => "integer"}
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  defp metrics_spec do
    %{
      "get" => %{
        "operationId" => "metrics",
        "summary" => "Request analytics for this service instance",
        "description" =>
          "Returned when the service is started with `enable_metrics: true`; otherwise " <>
            "the endpoint responds with 404.",
        "tags" => ["Observability"],
        "responses" => %{
          "200" => %{
            "description" => "Usage analytics",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "required" => ["requests", "errors", "average_duration_ms"],
                  "properties" => %{
                    "requests" => %{"type" => "integer"},
                    "errors" => %{"type" => "integer"},
                    "total_duration_us" => %{"type" => "integer"},
                    "average_duration_ms" => %{"type" => "number"},
                    "status_counts" => %{
                      "type" => "object",
                      "additionalProperties" => %{"type" => "integer"}
                    },
                    "operation_counts" => %{
                      "type" => "object",
                      "additionalProperties" => %{"type" => "integer"}
                    }
                  }
                }
              }
            }
          },
          "404" => %{
            "description" => "Metrics are not enabled for this service"
          }
        }
      }
    }
  end

  defp build_operation(operation, schema_names) do
    %{
      "operationId" => operation.name,
      "summary" => operation_description(operation),
      "tags" => [service_tag(operation)],
      "requestBody" => %{
        "description" => "Parameters for #{operation.name}",
        "required" => true,
        "content" => %{
          "application/json" => %{
            "schema" => object_schema(operation.input, schema_names)
          }
        }
      },
      "responses" => %{
        "200" => %{
          "description" => "Successful operation result",
          "content" => %{
            "application/json" => %{
              "schema" => %{
                "type" => "object",
                "required" => ["success"],
                "properties" => %{
                  "success" => %{"type" => "boolean"},
                  "data" => object_schema(operation.output, schema_names)
                }
              }
            }
          }
        },
        "400" => %{
          "description" => "Invalid request or failed validation",
          "content" => %{
            "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/Error"}}
          }
        },
        "500" => %{
          "description" => "Server error",
          "content" => %{
            "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/Error"}}
          }
        }
      }
    }
  end

  defp operation_description(operation) do
    Map.get(operation, :description) || operation.name
  end

  defp service_tag(_operation) do
    "operations"
  end

  defp build_component_schemas(service_info) do
    type_names = Enum.map(service_info.types, &schema_name(&1.name))

    type_schemas =
      service_info.types
      |> Enum.reduce(%{}, fn type, acc ->
        schema =
          object_schema(type.elements, type_names)
          |> put_if("description", Map.get(type, :description))

        Map.put(acc, schema_name(type.name), schema)
      end)

    Map.merge(
      %{
        "Error" => %{
          "type" => "object",
          "required" => ["code", "message"],
          "properties" => %{
            "code" => %{"type" => "string"},
            "message" => %{"type" => "string"},
            "detail" => %{}
          }
        }
      },
      type_schemas
    )
  end

  # Named complex types are emitted as component schemas so operations can
  # reference them with $ref. Types with no matching schema become free-form
  # objects rather than dangling references.
  defp object_schema(params, schema_names) do
    properties =
      params
      |> Enum.reduce(%{}, fn param, acc ->
        Map.put(acc, param.name, param_schema(param, schema_names))
      end)

    required =
      params
      |> Enum.filter(&(&1.required || Map.get(&1, :min_occurs, 0) >= 1))
      |> Enum.map(& &1.name)

    schema = %{"type" => "object", "properties" => properties}

    if required == [] do
      schema
    else
      Map.put(schema, "required", required)
    end
  end

  defp param_schema(param, schema_names) do
    schema = type_schema(param.type, schema_names)

    schema =
      if Map.get(param, :max_occurs, 1) > 1 do
        %{"type" => "array", "items" => schema}
      else
        schema
      end

    schema = put_if(schema, "description", Map.get(param, :description))
    put_if(schema, "default", Map.get(param, :default))
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp type_schema(type, schema_names) do
    normalized = normalize_type(type)

    cond do
      normalized in @integer_types ->
        %{"type" => "integer"}

      normalized in @decimal_types ->
        %{"type" => "number"}

      normalized == "string" ->
        %{"type" => "string"}

      normalized == "boolean" ->
        %{"type" => "boolean"}

      normalized in @datetime_types ->
        %{"type" => "string", "format" => "date-time"}

      normalized == "date" ->
        %{"type" => "string", "format" => "date"}

      normalized == "time" ->
        %{"type" => "string", "format" => "time"}

      schema_name(normalized) in schema_names ->
        %{"$ref" => "#/components/schemas/#{schema_name(normalized)}"}

      true ->
        %{"type" => "object"}
    end
  end

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)

  defp normalize_type(type) when is_binary(type) do
    type |> String.replace_prefix("xsd:", "") |> String.replace_prefix("xs:", "")
  end

  defp normalize_type(type), do: to_string(type)

  defp schema_name(name) do
    name |> normalize_type() |> String.replace(~r/[^A-Za-z0-9_]/, "")
  end
end
