defmodule Lather.TestUtils do
  @moduledoc """
  Utilities for Lather integration tests.
  """

  @doc """
  Starts a Bandit server on an OS-assigned port and returns the actual port.

  The requested port argument is retained for existing test callers. Letting
  the OS choose the port avoids races with other tests and processes.
  """
  def start_server(plug, _requested_port, scheme \\ :http, extra_opts \\ []) do
    opts = [plug: plug, port: 0, scheme: scheme] ++ extra_opts

    with {:ok, pid} <- Bandit.start_link(opts),
         {:ok, {_address, actual_port}} <- ThousandIsland.listener_info(pid) do
      {:ok, pid, actual_port}
    end
  end
end
