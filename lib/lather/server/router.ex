defmodule Lather.Server.Router do
  @moduledoc """
  Convenience macros for mounting Lather SOAP services in a `Plug.Router`
  (or a Phoenix router, which is built on the same machinery).

  `soap_route/2` registers a path for a SOAP service and exposes the whole
  enhanced endpoint set at it: WSDL, OpenAPI spec, Swagger UI, interactive
  forms, SOAP 1.1/1.2 and JSON/REST — including subpaths such as
  `/service/api/OperationName`.

  ## Example

      defmodule MyAppWeb.Router do
        use Lather.Server.Router

        soap_route "/soap", MyApp.UserService

        # Equivalent to:
        #   match "/soap" do ... EnhancedPlug ... end
        #   match "/soap/*rest" do ... EnhancedPlug ... end
      end

  Options are passed through to `Lather.Server.EnhancedPlug.init/1`, e.g.
  `:base_path`, `:enable_json`, `:enable_swagger`, `:auth_handler`.
  """

  defmacro __using__(opts) do
    quote do
      use Plug.Router, unquote_splicing(opts)
      plug(:match)
      plug(:dispatch)

      import Lather.Server.Router, only: [soap_route: 2, soap_route: 3]
    end
  end

  defmacro soap_route(path, service, opts \\ []) do
    quote do
      match unquote(path) do
        config = unquote(opts) ++ [service: unquote(service), base_path: unquote(path)]
        Lather.Server.EnhancedPlug.call(var!(conn), Lather.Server.EnhancedPlug.init(config))
      end

      match unquote(path) <> "/*rest" do
        config = unquote(opts) ++ [service: unquote(service), base_path: unquote(path)]
        Lather.Server.EnhancedPlug.call(var!(conn), Lather.Server.EnhancedPlug.init(config))
      end
    end
  end
end
