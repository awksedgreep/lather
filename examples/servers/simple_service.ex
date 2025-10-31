defmodule Examples.Servers.SimpleService do
  @moduledoc """
  A minimal SOAP service demonstrating basic Lather server functionality.

  This service provides simple string manipulation operations to showcase:
  - Basic operation definition
  - Input/output parameter handling
  - Simple error responses
  - WSDL generation

  ## Usage

  Start the service and access WSDL:

      curl http://localhost:4000/soap/simple?wsdl

  Call operations:

      # Echo operation
      curl -X POST http://localhost:4000/soap/simple \\
        -H "Content-Type: text/xml" \\
        -H "SOAPAction: Echo" \\
        -d '<?xml version="1.0"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <Echo>
              <message>Hello, SOAP!</message>
            </Echo>
          </soap:Body>
        </soap:Envelope>'
  """

  use Lather.Server

  @namespace "http://examples.com/simple"
  @service_name "SimpleService"

  # Echo operation - returns the same message
  soap_operation "Echo" do
    description "Returns the input message unchanged"

    input do
      parameter "message", :string, required: true, description: "Message to echo"
    end

    output do
      parameter "result", :string, description: "Echoed message"
    end

    soap_action "Echo"
  end

  def echo(%{"message" => message}) do
    {:ok, %{"result" => message}}
  end

  # Uppercase operation - converts message to uppercase
  soap_operation "Uppercase" do
    description "Converts input message to uppercase"

    input do
      parameter "text", :string, required: true, description: "Text to convert"
    end

    output do
      parameter "result", :string, description: "Uppercased text"
    end

    soap_action "Uppercase"
  end

  def uppercase(%{"text" => text}) do
    {:ok, %{"result" => String.upcase(text)}}
  end

  # Reverse operation - reverses the input string
  soap_operation "Reverse" do
    description "Reverses the input string"

    input do
      parameter "text", :string, required: true, description: "Text to reverse"
    end

    output do
      parameter "result", :string, description: "Reversed text"
    end

    soap_action "Reverse"
  end

  def reverse(%{"text" => text}) do
    {:ok, %{"result" => String.reverse(text)}}
  end

  # Length operation - returns string length
  soap_operation "Length" do
    description "Returns the length of the input string"

    input do
      parameter "text", :string, required: true, description: "Text to measure"
    end

    output do
      parameter "length", :int, description: "Length of the text"
    end

    soap_action "Length"
  end

  def length(%{"text" => text}) do
    {:ok, %{"length" => String.length(text)}}
  end

  # Concat operation - concatenates two strings
  soap_operation "Concat" do
    description "Concatenates two strings with optional separator"

    input do
      parameter "first", :string, required: true, description: "First string"
      parameter "second", :string, required: true, description: "Second string"
      parameter "separator", :string, required: false, description: "Separator between strings"
    end

    output do
      parameter "result", :string, description: "Concatenated string"
    end

    soap_action "Concat"
  end

  def concat(%{"first" => first, "second" => second} = params) do
    separator = Map.get(params, "separator", "")
    result = first <> separator <> second
    {:ok, %{"result" => result}}
  end

  # Error example - operation that can return a SOAP fault
  soap_operation "ValidateEmail" do
    description "Validates an email address format"

    input do
      parameter "email", :string, required: true, description: "Email address to validate"
    end

    output do
      parameter "isValid", :boolean, description: "Whether the email is valid"
      parameter "message", :string, description: "Validation message"
    end

    soap_action "ValidateEmail"
  end

  def validate_email(%{"email" => email}) do
    case validate_email_format(email) do
      true ->
        {:ok, %{"isValid" => true, "message" => "Email is valid"}}
      false ->
        # Return a SOAP fault for invalid email
        soap_fault("Client", "Invalid email format: #{email}")
    end
  end

  # Helper function to validate email format
  defp validate_email_format(email) do
    email_regex = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
    Regex.match?(email_regex, email)
  end
end
