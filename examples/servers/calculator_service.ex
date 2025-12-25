defmodule Examples.Servers.CalculatorService do
  @moduledoc """
  A SOAP calculator service demonstrating numeric operations with Lather.

  This service provides arithmetic operations to showcase:
  - Integer and decimal arithmetic
  - Input validation for numeric types
  - Error handling with SOAP faults (e.g., division by zero)
  - Complex operations with multiple operands
  - Different numeric data types in responses

  ## Operations

  - Add - Add two numbers
  - Subtract - Subtract two numbers
  - Multiply - Multiply two numbers
  - Divide - Divide two numbers (with division by zero handling)
  - Power - Raise a number to a power
  - SquareRoot - Calculate square root
  - Calculate - Perform a chain of operations on multiple operands
  - DecimalDivide - Divide with specified decimal precision

  ## Usage

  Start the service and access WSDL:

      curl http://localhost:4000/soap/calculator?wsdl

  Call operations:

      # Add operation
      curl -X POST http://localhost:4000/soap/calculator \\
        -H "Content-Type: text/xml" \\
        -H "SOAPAction: Add" \\
        -d '<?xml version="1.0"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <Add>
              <a>10</a>
              <b>5</b>
            </Add>
          </soap:Body>
        </soap:Envelope>'

      # Divide operation (demonstrates error handling)
      curl -X POST http://localhost:4000/soap/calculator \\
        -H "Content-Type: text/xml" \\
        -H "SOAPAction: Divide" \\
        -d '<?xml version="1.0"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <Divide>
              <dividend>100</dividend>
              <divisor>0</divisor>
            </Divide>
          </soap:Body>
        </soap:Envelope>'
  """

  use Lather.Server

  @namespace "http://examples.com/calculator"
  @service_name "CalculatorService"

  # Define complex types for advanced operations
  soap_type "CalculationStep" do
    description "A single step in a calculation chain"

    element "operation", :string, required: true, description: "Operation: add, subtract, multiply, divide"
    element "operand", :decimal, required: true, description: "The operand for this step"
  end

  soap_type "CalculationResult" do
    description "Result of a calculation with metadata"

    element "result", :decimal, required: true, description: "The final result"
    element "inputValue", :decimal, required: true, description: "The initial input value"
    element "stepsPerformed", :int, required: true, description: "Number of operations performed"
    element "operationsApplied", :string, required: true, description: "Comma-separated list of operations"
  end

  # ============================================================================
  # Basic Integer Operations
  # ============================================================================

  # Add operation - adds two numbers
  soap_operation "Add" do
    description "Adds two numbers together"

    input do
      parameter "a", :decimal, required: true, description: "First number"
      parameter "b", :decimal, required: true, description: "Second number"
    end

    output do
      parameter "result", :decimal, description: "Sum of a and b"
    end

    soap_action "Add"
  end

  def add(%{"a" => a, "b" => b}) do
    with {:ok, num_a} <- parse_number(a),
         {:ok, num_b} <- parse_number(b) do
      {:ok, %{"result" => num_a + num_b}}
    else
      {:error, reason} -> soap_fault("Client", reason)
    end
  end

  # Subtract operation - subtracts second number from first
  soap_operation "Subtract" do
    description "Subtracts the second number from the first"

    input do
      parameter "a", :decimal, required: true, description: "Number to subtract from"
      parameter "b", :decimal, required: true, description: "Number to subtract"
    end

    output do
      parameter "result", :decimal, description: "Difference of a minus b"
    end

    soap_action "Subtract"
  end

  def subtract(%{"a" => a, "b" => b}) do
    with {:ok, num_a} <- parse_number(a),
         {:ok, num_b} <- parse_number(b) do
      {:ok, %{"result" => num_a - num_b}}
    else
      {:error, reason} -> soap_fault("Client", reason)
    end
  end

  # Multiply operation - multiplies two numbers
  soap_operation "Multiply" do
    description "Multiplies two numbers together"

    input do
      parameter "a", :decimal, required: true, description: "First number"
      parameter "b", :decimal, required: true, description: "Second number"
    end

    output do
      parameter "result", :decimal, description: "Product of a and b"
    end

    soap_action "Multiply"
  end

  def multiply(%{"a" => a, "b" => b}) do
    with {:ok, num_a} <- parse_number(a),
         {:ok, num_b} <- parse_number(b) do
      {:ok, %{"result" => num_a * num_b}}
    else
      {:error, reason} -> soap_fault("Client", reason)
    end
  end

  # Divide operation - divides first number by second (integer division)
  soap_operation "Divide" do
    description "Divides the dividend by the divisor. Returns SOAP fault for division by zero."

    input do
      parameter "dividend", :decimal, required: true, description: "Number to be divided"
      parameter "divisor", :decimal, required: true, description: "Number to divide by"
    end

    output do
      parameter "quotient", :decimal, description: "Result of division"
      parameter "remainder", :decimal, description: "Remainder (for integer division)"
    end

    soap_action "Divide"
  end

  def divide(%{"dividend" => dividend, "divisor" => divisor}) do
    with {:ok, num_dividend} <- parse_number(dividend),
         {:ok, num_divisor} <- parse_number(divisor),
         :ok <- validate_non_zero(num_divisor) do
      quotient = num_dividend / num_divisor
      # Calculate remainder for integer-like inputs
      remainder = if is_integer_like?(num_dividend) and is_integer_like?(num_divisor) do
        trunc(num_dividend) - trunc(num_divisor) * trunc(quotient)
      else
        0.0
      end

      {:ok, %{
        "quotient" => quotient,
        "remainder" => remainder
      }}
    else
      {:error, :division_by_zero} ->
        soap_fault("Client", "Division by zero is not allowed", %{
          dividend: dividend,
          divisor: divisor,
          errorCode: "MATH_ERR_001"
        })

      {:error, reason} ->
        soap_fault("Client", reason)
    end
  end

  # ============================================================================
  # Advanced Mathematical Operations
  # ============================================================================

  # Power operation - raises a number to a power
  soap_operation "Power" do
    description "Raises a base number to the specified exponent"

    input do
      parameter "base", :decimal, required: true, description: "The base number"
      parameter "exponent", :decimal, required: true, description: "The exponent (power)"
    end

    output do
      parameter "result", :decimal, description: "base raised to the power of exponent"
    end

    soap_action "Power"
  end

  def power(%{"base" => base, "exponent" => exponent}) do
    with {:ok, num_base} <- parse_number(base),
         {:ok, num_exponent} <- parse_number(exponent) do
      result = :math.pow(num_base, num_exponent)
      {:ok, %{"result" => result}}
    else
      {:error, reason} -> soap_fault("Client", reason)
    end
  end

  # SquareRoot operation - calculates square root
  soap_operation "SquareRoot" do
    description "Calculates the square root of a number. Returns SOAP fault for negative numbers."

    input do
      parameter "number", :decimal, required: true, description: "Number to find square root of"
    end

    output do
      parameter "result", :decimal, description: "Square root of the input"
    end

    soap_action "SquareRoot"
  end

  def square_root(%{"number" => number}) do
    with {:ok, num} <- parse_number(number),
         :ok <- validate_non_negative(num) do
      result = :math.sqrt(num)
      {:ok, %{"result" => result}}
    else
      {:error, :negative_number} ->
        soap_fault("Client", "Cannot calculate square root of a negative number", %{
          input: number,
          errorCode: "MATH_ERR_002"
        })

      {:error, reason} ->
        soap_fault("Client", reason)
    end
  end

  # ============================================================================
  # Precision Operations
  # ============================================================================

  # DecimalDivide - division with specified precision
  soap_operation "DecimalDivide" do
    description "Divides two numbers with specified decimal precision"

    input do
      parameter "dividend", :decimal, required: true, description: "Number to be divided"
      parameter "divisor", :decimal, required: true, description: "Number to divide by"
      parameter "precision", :int, required: false, description: "Decimal places (default: 2, max: 10)"
    end

    output do
      parameter "result", :string, description: "Division result as formatted string"
      parameter "rawResult", :decimal, description: "Raw division result"
      parameter "precision", :int, description: "Precision used"
    end

    soap_action "DecimalDivide"
  end

  def decimal_divide(%{"dividend" => dividend, "divisor" => divisor} = params) do
    precision = parse_precision(Map.get(params, "precision", "2"))

    with {:ok, num_dividend} <- parse_number(dividend),
         {:ok, num_divisor} <- parse_number(divisor),
         :ok <- validate_non_zero(num_divisor) do
      raw_result = num_dividend / num_divisor
      formatted_result = :erlang.float_to_binary(raw_result, decimals: precision)

      {:ok, %{
        "result" => formatted_result,
        "rawResult" => raw_result,
        "precision" => precision
      }}
    else
      {:error, :division_by_zero} ->
        soap_fault("Client", "Division by zero is not allowed", %{
          dividend: dividend,
          divisor: divisor,
          errorCode: "MATH_ERR_001"
        })

      {:error, reason} ->
        soap_fault("Client", reason)
    end
  end

  # ============================================================================
  # Complex Operations
  # ============================================================================

  # Calculate operation - performs a chain of operations
  soap_operation "Calculate" do
    description """
    Performs a chain of operations on an initial value.
    Each step applies an operation (add, subtract, multiply, divide) with an operand.
    Operations are applied in order.
    """

    input do
      parameter "initialValue", :decimal, required: true, description: "Starting value"
      parameter "steps", "CalculationStep", required: true,
        max_occurs: "unbounded", description: "List of calculation steps to apply"
    end

    output do
      parameter "calculationResult", "CalculationResult", description: "Detailed calculation result"
    end

    soap_action "Calculate"
  end

  def calculate(%{"initialValue" => initial_value, "steps" => steps}) do
    with {:ok, start_value} <- parse_number(initial_value),
         {:ok, result, operations} <- apply_calculation_steps(start_value, steps) do
      {:ok, %{
        "calculationResult" => %{
          "result" => result,
          "inputValue" => start_value,
          "stepsPerformed" => length(operations),
          "operationsApplied" => Enum.join(operations, ", ")
        }
      }}
    else
      {:error, {:step_error, step_index, reason}} ->
        soap_fault("Client", "Error in calculation step #{step_index + 1}: #{reason}", %{
          stepIndex: step_index,
          errorCode: "CALC_ERR_001"
        })

      {:error, reason} ->
        soap_fault("Client", reason)
    end
  end

  # Sum operation - adds multiple numbers
  soap_operation "Sum" do
    description "Adds a list of numbers together"

    input do
      parameter "numbers", :decimal, required: true,
        max_occurs: "unbounded", description: "List of numbers to add"
    end

    output do
      parameter "result", :decimal, description: "Sum of all numbers"
      parameter "count", :int, description: "Number of values summed"
      parameter "average", :decimal, description: "Average of the numbers"
    end

    soap_action "Sum"
  end

  def sum(%{"numbers" => numbers}) do
    number_list = List.wrap(numbers)

    with {:ok, parsed_numbers} <- parse_number_list(number_list) do
      total = Enum.sum(parsed_numbers)
      count = length(parsed_numbers)
      average = if count > 0, do: total / count, else: 0.0

      {:ok, %{
        "result" => total,
        "count" => count,
        "average" => average
      }}
    else
      {:error, reason} -> soap_fault("Client", reason)
    end
  end

  # ============================================================================
  # Comparison Operations
  # ============================================================================

  # Compare operation - compares two numbers
  soap_operation "Compare" do
    description "Compares two numbers and returns their relationship"

    input do
      parameter "a", :decimal, required: true, description: "First number"
      parameter "b", :decimal, required: true, description: "Second number"
    end

    output do
      parameter "comparison", :string, description: "Comparison result: 'less', 'equal', or 'greater'"
      parameter "difference", :decimal, description: "Absolute difference between the numbers"
      parameter "percentDifference", :decimal, description: "Percentage difference (relative to first number)"
    end

    soap_action "Compare"
  end

  def compare(%{"a" => a, "b" => b}) do
    with {:ok, num_a} <- parse_number(a),
         {:ok, num_b} <- parse_number(b) do
      comparison = cond do
        num_a < num_b -> "less"
        num_a > num_b -> "greater"
        true -> "equal"
      end

      difference = abs(num_a - num_b)
      percent_difference = if num_a != 0 do
        (difference / abs(num_a)) * 100
      else
        if num_b != 0, do: 100.0, else: 0.0
      end

      {:ok, %{
        "comparison" => comparison,
        "difference" => difference,
        "percentDifference" => percent_difference
      }}
    else
      {:error, reason} -> soap_fault("Client", reason)
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Parses a string or number into a numeric value
  defp parse_number(value) when is_number(value), do: {:ok, value}

  defp parse_number(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:error, "Empty value is not a valid number"}

      String.contains?(value, ".") ->
        case Float.parse(value) do
          {num, ""} -> {:ok, num}
          _ -> {:error, "Invalid decimal number: #{value}"}
        end

      true ->
        case Integer.parse(value) do
          {num, ""} -> {:ok, num}
          _ -> {:error, "Invalid integer: #{value}"}
        end
    end
  end

  defp parse_number(_value) do
    {:error, "Value must be a number or numeric string"}
  end

  # Parses a list of numbers
  defp parse_number_list(numbers) do
    results = Enum.map(numbers, &parse_number/1)

    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil -> {:ok, Enum.map(results, fn {:ok, n} -> n end)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Validates that a number is not zero (for division)
  defp validate_non_zero(0), do: {:error, :division_by_zero}
  defp validate_non_zero(0.0), do: {:error, :division_by_zero}
  defp validate_non_zero(_), do: :ok

  # Validates that a number is not negative (for square root)
  defp validate_non_negative(num) when num < 0, do: {:error, :negative_number}
  defp validate_non_negative(_), do: :ok

  # Checks if a number is effectively an integer
  defp is_integer_like?(num) when is_integer(num), do: true
  defp is_integer_like?(num) when is_float(num), do: trunc(num) == num
  defp is_integer_like?(_), do: false

  # Parses precision parameter with bounds
  defp parse_precision(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> min(max(num, 0), 10)
      _ -> 2
    end
  end

  defp parse_precision(value) when is_integer(value), do: min(max(value, 0), 10)
  defp parse_precision(_), do: 2

  # Applies a chain of calculation steps
  defp apply_calculation_steps(initial_value, steps) when is_list(steps) do
    steps
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, initial_value, []}, fn {step, index}, {:ok, current, ops} ->
      case apply_single_step(current, step) do
        {:ok, new_value, op_name} ->
          {:cont, {:ok, new_value, ops ++ [op_name]}}

        {:error, reason} ->
          {:halt, {:error, {:step_error, index, reason}}}
      end
    end)
  end

  defp apply_calculation_steps(initial_value, step) when is_map(step) do
    apply_calculation_steps(initial_value, [step])
  end

  # Applies a single calculation step
  defp apply_single_step(current_value, %{"operation" => operation, "operand" => operand}) do
    with {:ok, num_operand} <- parse_number(operand) do
      case String.downcase(operation) do
        "add" ->
          {:ok, current_value + num_operand, "add(#{num_operand})"}

        "subtract" ->
          {:ok, current_value - num_operand, "subtract(#{num_operand})"}

        "multiply" ->
          {:ok, current_value * num_operand, "multiply(#{num_operand})"}

        "divide" ->
          case validate_non_zero(num_operand) do
            :ok -> {:ok, current_value / num_operand, "divide(#{num_operand})"}
            {:error, :division_by_zero} -> {:error, "Division by zero"}
          end

        unknown ->
          {:error, "Unknown operation: #{unknown}"}
      end
    end
  end
end
