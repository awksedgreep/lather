defmodule Lather.Server.DslEnhancementsTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule EnhancedService do
    @moduledoc false
    use Lather.Server

    @service_name "EnhancedService"
    @namespace "urn:enhanced:service"

    soap_operation "BoundedEcho" do
      input do
        parameter("message", :string, required: true)
        parameter("mode", :string, enum: ["upper", "lower"], default: "upper")
        parameter("repeats", :integer, min: 1, max: 3, default: 1)
        parameter("code", :string, pattern: ~r/^[A-Z]{3}$/)
      end

      output do
        parameter("result", :string)
      end
    end

    def bounded_echo(params) do
      message = params["message"]
      mode = params["mode"]

      repeats =
        case params["repeats"] do
          n when is_integer(n) -> n
          n -> String.to_integer(to_string(n))
        end

      text =
        case mode do
          "upper" -> String.upcase(message)
          "lower" -> String.downcase(message)
          _ -> message
        end

      {:ok, %{"result" => String.duplicate(text, repeats)}}
    end

    def ok_condition(params), do: params["ok"] == "yes"

    soap_operation "ConditionalPing", condition: &__MODULE__.ok_condition/1 do
      input do
        parameter("ok", :string, required: true)
      end

      output do
        parameter("pong", :string)
      end
    end

    def conditional_ping(_params), do: {:ok, %{"pong" => "pong"}}

    soap_operation "FindUser" do
      error("UserNotFound",
        match: {:error, :not_found},
        code: "Sender",
        subcode: "BadRequest",
        message: "The requested user does not exist"
      )

      input do
        parameter("id", :integer, required: true)
      end

      output do
        parameter("name", :string)
      end
    end

    def find_user(%{"id" => id}) do
      if id == 1 do
        {:ok, %{"name" => "Ada"}}
      else
        {:error, :not_found}
      end
    end
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: EnhancedService, validate_params: true]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  defp fault_text(fault) do
    text = fault[:fault_string]

    case text do
      %{"#text" => t} -> t
      other -> to_string(other)
    end
  end

  test "defaults are applied" do
    {:ok, response} =
      Lather.DynamicClient.call(client_fixture(), "BoundedEcho", %{"message" => "hi"})

    assert response["result"] == "HI"
  end

  defp client_fixture do
    {:ok, _pid, port} =
      TestUtils.start_server(
        {Lather.Server.EnhancedPlug, [service: EnhancedService, validate_params: true]},
        0
      )

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")
    client
  end

  test "enum values are validated" do
    {:ok, response} =
      Lather.DynamicClient.call(client_fixture(), "BoundedEcho", %{
        "message" => "hi",
        "mode" => "lower"
      })

    assert response["result"] == "hi"

    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client_fixture(), "BoundedEcho", %{
        "message" => "hi",
        "mode" => "invalid"
      })

    assert fault_text(fault) =~ "must be one of"
  end

  test "min/max bounds are validated" do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client_fixture(), "BoundedEcho", %{
        "message" => "hi",
        "repeats" => "5"
      })

    assert fault_text(fault) =~ "must be <= 3"
  end

  test "patterns are validated" do
    {:ok, response} =
      Lather.DynamicClient.call(client_fixture(), "BoundedEcho", %{
        "message" => "hi",
        "code" => "ABC"
      })

    assert response["result"] == "HI"

    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client_fixture(), "BoundedEcho", %{
        "message" => "hi",
        "code" => "abc"
      })

    assert fault_text(fault) =~ "does not match pattern"
  end

  test "condition blocks execution when false" do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client_fixture(), "ConditionalPing", %{"ok" => "no"})

    assert fault_text(fault) =~ "Precondition failed"
  end

  test "condition allows execution when true" do
    {:ok, response} =
      Lather.DynamicClient.call(client_fixture(), "ConditionalPing", %{"ok" => "yes"})

    assert response["pong"] == "pong"
  end

  test "error DSL maps handler errors to custom faults" do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client_fixture(), "FindUser", %{"id" => "42"})

    assert fault_text(fault) =~ "The requested user does not exist"
  end
end
