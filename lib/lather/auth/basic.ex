defmodule Lather.Auth.Basic do
  @moduledoc """
  HTTP Basic authentication for SOAP services.

  This module provides utilities for HTTP Basic authentication,
  which can be used in HTTP headers for SOAP requests.
  """

  @doc """
  Creates an HTTP Basic authentication header.

  ## Parameters

    * `username` - The username for authentication
    * `password` - The password for authentication

  ## Examples

      iex> Lather.Auth.Basic.header("admin", "password")
      {"Authorization", "Basic YWRtaW46cGFzc3dvcmQ="}
  """
  @spec header(String.t(), String.t()) :: {String.t(), String.t()}
  def header(username, password) do
    credentials = username <> ":" <> password
    encoded = Base.encode64(credentials)
    {"Authorization", "Basic " <> encoded}
  end

  @doc """
  Creates an HTTP Basic authentication header value only.

  ## Parameters

    * `username` - The username for authentication
    * `password` - The password for authentication

  ## Examples

      iex> Lather.Auth.Basic.header_value("admin", "password")
      "Basic YWRtaW46cGFzc3dvcmQ="
  """
  @spec header_value(String.t(), String.t()) :: String.t()
  def header_value(username, password) do
    credentials = username <> ":" <> password
    encoded = Base.encode64(credentials)
    "Basic " <> encoded
  end

  @doc """
  Decodes an HTTP Basic authentication header.

  ## Parameters

    * `header_value` - The Basic authentication header value

  ## Examples

      iex> Lather.Auth.Basic.decode("Basic YWRtaW46cGFzc3dvcmQ=")
      {:ok, {"admin", "password"}}

      iex> Lather.Auth.Basic.decode("Invalid")
      {:error, :invalid_format}
  """
  @spec decode(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, atom()}
  def decode("Basic " <> encoded) do
    case Base.decode64(encoded) do
      {:ok, credentials} ->
        # Split on first colon only - everything after first colon is the password
        case String.split(credentials, ":", parts: 2) do
          [username, password] ->
            {:ok, {username, password}}

          _ ->
            {:error, :invalid_credentials}
        end

      :error ->
        {:error, :invalid_encoding}
    end
  end

  def decode(_) do
    {:error, :invalid_format}
  end

  @doc """
  Validates Basic authentication credentials against a validation function.

  ## Parameters

    * `header_value` - The Basic authentication header value
    * `validator` - A function that takes username and password and returns boolean

  ## Examples

      iex> validator = fn "admin", "password" -> true; _, _ -> false end
      iex> Lather.Auth.Basic.validate("Basic YWRtaW46cGFzc3dvcmQ=", validator)
      {:ok, {"admin", "password"}}

      iex> Lather.Auth.Basic.validate("Basic d3Jvbmc6d3Jvbmc=", validator)
      {:error, :invalid_credentials}
  """
  @spec validate(String.t(), (String.t(), String.t() -> boolean())) ::
          {:ok, {String.t(), String.t()}} | {:error, atom()}
  def validate(header_value, validator) when is_function(validator, 2) do
    case decode(header_value) do
      {:ok, {username, password}} ->
        try do
          if validator.(username, password) do
            {:ok, {username, password}}
          else
            {:error, :invalid_credentials}
          end
        rescue
          _ ->
            {:error, :validator_error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
