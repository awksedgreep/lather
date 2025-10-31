defmodule Lather.Application do
  @moduledoc """
  Lather application supervisor.

  Starts and manages the Finch HTTP client pool for SOAP requests.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: Lather.Finch}
    ]

    opts = [strategy: :one_for_one, name: Lather.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
