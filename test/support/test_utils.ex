defmodule Lather.TestUtils do
  @moduledoc """
  Utilities for Lather integration tests.
  """

  @doc """
  Starts a Bandit server on the given port, incrementing the port if it's already in use.
  """
  def start_server(plug, port, scheme \\ :http, extra_opts \\ []) do
    opts = [plug: plug, port: port, scheme: scheme] ++ extra_opts

    case Bandit.start_link(opts) do
      {:ok, pid} ->
        {:ok, pid, port}

      {:error, reason} ->
        # If Bandit returns an error tuple for port in use, retry
        if reason == :eaddrinuse or (is_binary(reason) and String.contains?(reason, "address already in use")) do
          start_server(plug, port + 1, scheme, extra_opts)
        else
          {:error, reason}
        end
    end
  rescue
    _e ->
      # If it crashes with :eaddrinuse, retry
      start_server(plug, port + 1, scheme, extra_opts)
  end
end
