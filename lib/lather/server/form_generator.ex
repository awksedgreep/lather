defmodule Lather.Server.FormGenerator do
  @moduledoc """
  Generates HTML forms and documentation pages for SOAP operations.

  Creates comprehensive testing interfaces similar to .NET Web Services
  with interactive forms, protocol examples, and complete documentation.
  Supports SOAP 1.1, SOAP 1.2, and JSON protocols.
  """

  @doc """
  Generates a complete HTML page for an operation with testing forms
  and protocol examples.
  """
  def generate_operation_page(service_info, operation, base_url, _options \\ []) do
    service_name = service_info.name
    namespace = service_info.target_namespace

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{service_name} - #{operation.name}</title>
        <style>
            #{generate_css()}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>#{service_name}</h1>
                <p class="service-description">Powered by Lather SOAP Library</p>
                <p><a href="?wsdl">Click here for a complete list of operations.</a></p>
            </div>

            <div class="operation-section">
                <h2>#{operation.name}</h2>
                #{if operation.description, do: "<p class=\"operation-description\">#{operation.description}</p>", else: ""}
            </div>

            <div class="test-section">
                <h3>Test</h3>
                <p>To test the operation using the HTTP POST protocol, click the 'Invoke' button.</p>

                #{generate_test_form(operation, base_url, service_name)}
            </div>

            <div class="examples-section">
                <div class="protocol-section">
                    <h3>SOAP 1.1</h3>
                    <p>The following is a sample SOAP 1.1 request and response. The placeholders shown need to be replaced with actual values.</p>
                    #{generate_soap_1_1_example(operation, base_url, service_name, namespace)}
                </div>

                <div class="protocol-section">
                    <h3>SOAP 1.2</h3>
                    <p>The following is a sample SOAP 1.2 request and response. The placeholders shown need to be replaced with actual values.</p>
                    #{generate_soap_1_2_example(operation, base_url, service_name, namespace)}
                </div>

                <div class="protocol-section">
                    <h3>JSON</h3>
                    <p>The following is a sample JSON request and response. The placeholders shown need to be replaced with actual values.</p>
                    #{generate_json_example(operation, base_url, service_name)}
                </div>
            </div>
        </div>

        <script>
            #{generate_javascript()}
        </script>
    </body>
    </html>
    """
  end

  @doc """
  Generates a service overview page with all operations listed.
  """
  def generate_service_overview(service_info, base_url, _options \\ []) do
    service_name = service_info.name
    namespace = service_info.target_namespace

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{service_name} - Service Overview</title>
        <style>
            #{generate_css()}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>#{service_name}</h1>
                <p class="service-description">Multi-Protocol Web Service</p>
                <p><strong>Namespace:</strong> #{namespace}</p>
                <p><strong>Powered by:</strong> Lather SOAP Library v#{get_version()}</p>
            </div>

            <div class="protocols-section">
                <h2>Supported Protocols</h2>
                <div class="protocol-grid">
                    <div class="protocol-card">
                        <h3>SOAP 1.1</h3>
                        <p>Maximum compatibility with legacy systems</p>
                        <code>#{base_url}soap/v1.1/#{service_name}</code>
                    </div>
                    <div class="protocol-card">
                        <h3>SOAP 1.2</h3>
                        <p>Enhanced error handling and performance</p>
                        <code>#{base_url}soap/v1.2/#{service_name}</code>
                    </div>
                    <div class="protocol-card">
                        <h3>JSON/REST</h3>
                        <p>Modern API for web applications</p>
                        <code>#{base_url}api/#{String.downcase(service_name)}</code>
                    </div>
                </div>
            </div>

            <div class="operations-section">
                <h2>Available Operations</h2>
                <div class="operations-list">
                    #{Enum.map_join(service_info.operations, "\n", &generate_operation_summary(&1, service_name))}
                </div>
            </div>

            #{generate_wsdl_links(base_url, service_name)}
        </div>
    </body>
    </html>
    """
  end

  # Generate the test form for an operation
  defp generate_test_form(operation, base_url, _service_name) do
    # The form posts to the base URL (not a sub-path) for SOAP 1.1
    # Remove trailing slash and use as-is
    form_action = String.trim_trailing(base_url, "/")
    namespace = operation[:namespace] || "http://tempuri.org/"
    soap_action = operation.soap_action || operation.name

    """
    <form id="testForm" class="test-form" data-namespace="#{namespace}" data-soap-action="#{soap_action}">
        <table class="parameter-table">
            <thead>
                <tr>
                    <th>Parameter</th>
                    <th>Value</th>
                </tr>
            </thead>
            <tbody>
                #{Enum.map_join(Map.get(operation, :input, Map.get(operation, :input_parameters, [])), "\n", &generate_parameter_row/1)}
            </tbody>
        </table>
        <div class="form-actions">
            <button type="button" onclick="invokeOperation('#{form_action}', '#{operation.name}')" class="invoke-btn">
                Invoke
            </button>
            <button type="button" onclick="viewJSON('#{operation.name}')" class="json-btn">
                View JSON Format
            </button>
        </div>
    </form>

    <div id="resultSection" class="result-section" style="display: none;">
        <h4>Result</h4>
        <pre id="resultContent"></pre>
    </div>
    """
  end

  # Generate a parameter input row
  defp generate_parameter_row(param) do
    input_type = get_html_input_type(param.type)
    placeholder = get_type_placeholder(param.type)
    required_class = if param.required, do: " required", else: ""

    """
                <tr>
                    <td class="param-name">
                        #{param.name}
                        #{if param.required, do: "<span class=\"required-indicator\">*</span>", else: ""}
                        #{if param.description, do: "<br><small>#{param.description}</small>", else: ""}
                    </td>
                    <td class="param-value">
                        <input type="#{input_type}"
                               name="#{param.name}"
                               placeholder="#{placeholder}"
                               class="param-input#{required_class}" />
                    </td>
                </tr>
    """
  end

  # Generate SOAP 1.1 example
  defp generate_soap_1_1_example(operation, base_url, service_name, namespace) do
    endpoint = "#{base_url}soap/v1.1/#{service_name}"
    soap_action = operation.soap_action || operation.name

    request_params =
      Enum.map_join(
        Map.get(operation, :input, Map.get(operation, :input_parameters, [])),
        "\n",
        fn param ->
          "      <#{param.name}>#{get_type_placeholder(param.type)}</#{param.name}>"
        end
      )

    response_params =
      Enum.map_join(
        Map.get(operation, :output, Map.get(operation, :output_parameters, [])),
        "\n",
        fn param ->
          "      <#{param.name}>#{get_type_placeholder(param.type)}</#{param.name}>"
        end
      )

    """
    <div class="code-example">
        <h4>Request</h4>
        <pre><code>POST #{URI.parse(endpoint).path || "/#{service_name}"} HTTP/1.1
    Host: #{URI.parse(endpoint).host || "localhost"}
    Content-Type: text/xml; charset=utf-8
    SOAPAction: "#{soap_action}"
    Content-Length: length

    &lt;?xml version="1.0" encoding="utf-8"?&gt;
    &lt;soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"&gt;
    &lt;soap:Body&gt;
    &lt;#{operation.name} xmlns="#{namespace}"&gt;
    #{request_params}
    &lt;/#{operation.name}&gt;
    &lt;/soap:Body&gt;
    &lt;/soap:Envelope&gt;</code></pre>

        <h4>Response</h4>
        <pre><code>HTTP/1.1 200 OK
    Content-Type: text/xml; charset=utf-8
    Content-Length: length

    &lt;?xml version="1.0" encoding="utf-8"?&gt;
    &lt;soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"&gt;
    &lt;soap:Body&gt;
    &lt;#{operation.name}Response xmlns="#{namespace}"&gt;
    #{response_params}
    &lt;/#{operation.name}Response&gt;
    &lt;/soap:Body&gt;
    &lt;/soap:Envelope&gt;</code></pre>
    </div>
    """
  end

  # Generate SOAP 1.2 example
  defp generate_soap_1_2_example(operation, base_url, service_name, namespace) do
    endpoint = "#{base_url}soap/v1.2/#{service_name}"
    soap_action = operation.soap_action || operation.name

    request_params =
      Enum.map_join(
        Map.get(operation, :input, Map.get(operation, :input_parameters, [])),
        "\n",
        fn param ->
          "      <#{param.name}>#{get_type_placeholder(param.type)}</#{param.name}>"
        end
      )

    response_params =
      Enum.map_join(
        Map.get(operation, :output, Map.get(operation, :output_parameters, [])),
        "\n",
        fn param ->
          "      <#{param.name}>#{get_type_placeholder(param.type)}</#{param.name}>"
        end
      )

    """
    <div class="code-example">
        <h4>Request</h4>
        <pre><code>POST #{URI.parse(endpoint).path || "/#{service_name}"} HTTP/1.1
    Host: #{URI.parse(endpoint).host || "localhost"}
    Content-Type: application/soap+xml; charset=utf-8; action="#{soap_action}"
    Content-Length: length

    &lt;?xml version="1.0" encoding="utf-8"?&gt;
    &lt;soap12:Envelope xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"&gt;
    &lt;soap12:Body&gt;
    &lt;#{operation.name} xmlns="#{namespace}"&gt;
    #{request_params}
    &lt;/#{operation.name}&gt;
    &lt;/soap12:Body&gt;
    &lt;/soap12:Envelope&gt;</code></pre>

        <h4>Response</h4>
        <pre><code>HTTP/1.1 200 OK
    Content-Type: application/soap+xml; charset=utf-8
    Content-Length: length

    &lt;?xml version="1.0" encoding="utf-8"?&gt;
    &lt;soap12:Envelope xmlns:soap12="http://www.w3.org/2003/05/soap-envelope"&gt;
    &lt;soap12:Body&gt;
    &lt;#{operation.name}Response xmlns="#{namespace}"&gt;
    #{response_params}
    &lt;/#{operation.name}Response&gt;
    &lt;/soap12:Body&gt;
    &lt;/soap12:Envelope&gt;</code></pre>
    </div>
    """
  end

  # Generate JSON example
  defp generate_json_example(operation, base_url, service_name) do
    endpoint =
      "#{base_url}api/#{String.downcase(service_name)}/#{String.downcase(operation.name)}"

    request_json =
      Map.get(operation, :input, Map.get(operation, :input_parameters, []))
      |> Enum.map(fn param -> "  \"#{param.name}\": #{get_json_placeholder(param.type)}" end)
      |> Enum.join(",\n")

    response_json =
      Map.get(operation, :output, Map.get(operation, :output_parameters, []))
      |> Enum.map(fn param -> "  \"#{param.name}\": #{get_json_placeholder(param.type)}" end)
      |> Enum.join(",\n")

    """
    <div class="code-example">
        <h4>Request</h4>
        <pre><code>POST #{URI.parse(endpoint).path || "/api/#{service_name}"} HTTP/1.1
    Host: #{URI.parse(endpoint).host || "localhost"}
    Content-Type: application/json; charset=utf-8
    Content-Length: length

    {
    #{request_json}
    }</code></pre>

        <h4>Response</h4>
        <pre><code>HTTP/1.1 200 OK
    Content-Type: application/json; charset=utf-8
    Content-Length: length

    {
    #{response_json}
    }</code></pre>
    </div>
    """
  end

  # Generate operation summary for overview page
  defp generate_operation_summary(operation, _service_name) do
    """
    <div class="operation-item">
        <h4><a href="?op=#{operation.name}">#{operation.name}</a></h4>
        #{if operation.description, do: "<p>#{operation.description}</p>", else: ""}
        <div class="operation-details">
            <span class="param-count">#{length(Map.get(operation, :input, Map.get(operation, :input_parameters, [])))} input(s)</span>
            <span class="param-count">#{length(Map.get(operation, :output, Map.get(operation, :output_parameters, [])))} output(s)</span>
        </div>
    </div>
    """
  end

  # Generate WSDL download links
  defp generate_wsdl_links(_base_url, _service_name) do
    """
    <div class="wsdl-section">
        <h2>Service Description</h2>
        <div class="wsdl-links">
            <a href="?wsdl" class="wsdl-link">Download WSDL</a>
            <a href="?wsdl&enhanced=true" class="wsdl-link">Download Enhanced WSDL (Multi-Protocol)</a>
        </div>
    </div>
    """
  end

  # Generate CSS styles
  defp generate_css do
    """
    body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        margin: 0;
        padding: 20px;
        background-color: #f5f5f5;
        color: #333;
        line-height: 1.6;
    }

    .container {
        max-width: 1200px;
        margin: 0 auto;
        background-color: white;
        border-radius: 8px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        padding: 30px;
    }

    .header {
        border-bottom: 2px solid #e0e0e0;
        padding-bottom: 20px;
        margin-bottom: 30px;
    }

    .header h1 {
        color: #2c3e50;
        margin: 0;
        font-size: 2.5em;
    }

    .service-description {
        color: #7f8c8d;
        font-size: 1.1em;
        margin: 10px 0;
    }

    .operation-section {
        margin-bottom: 30px;
    }

    .operation-section h2 {
        color: #34495e;
        border-left: 4px solid #3498db;
        padding-left: 15px;
    }

    .operation-description {
        background-color: #ecf0f1;
        padding: 15px;
        border-radius: 5px;
        font-style: italic;
    }

    .test-section {
        background-color: #f8f9fa;
        padding: 25px;
        border-radius: 8px;
        margin-bottom: 30px;
        border: 1px solid #dee2e6;
    }

    .test-form {
        margin-top: 20px;
    }

    .parameter-table {
        width: 100%;
        border-collapse: collapse;
        margin-bottom: 20px;
    }

    .parameter-table th,
    .parameter-table td {
        padding: 12px;
        text-align: left;
        border-bottom: 1px solid #ddd;
    }

    .parameter-table th {
        background-color: #f2f2f2;
        font-weight: 600;
    }

    .param-name {
        font-weight: 500;
        width: 30%;
    }

    .required-indicator {
        color: #e74c3c;
        font-weight: bold;
    }

    .param-input {
        width: 100%;
        padding: 8px 12px;
        border: 1px solid #ddd;
        border-radius: 4px;
        font-size: 14px;
    }

    .param-input.required {
        border-color: #3498db;
    }

    .form-actions {
        text-align: center;
    }

    .invoke-btn, .json-btn {
        background-color: #3498db;
        color: white;
        border: none;
        padding: 12px 25px;
        border-radius: 5px;
        cursor: pointer;
        font-size: 16px;
        margin: 0 10px;
        transition: background-color 0.3s;
    }

    .invoke-btn:hover, .json-btn:hover {
        background-color: #2980b9;
    }

    .json-btn {
        background-color: #27ae60;
    }

    .json-btn:hover {
        background-color: #229954;
    }

    .result-section {
        margin-top: 20px;
        padding: 20px;
        background-color: #e8f5e8;
        border-radius: 5px;
        border: 1px solid #27ae60;
    }

    .examples-section {
        margin-top: 40px;
    }

    .protocol-section {
        margin-bottom: 40px;
        padding: 25px;
        border: 1px solid #ddd;
        border-radius: 8px;
        background-color: #fefefe;
    }

    .protocol-section h3 {
        color: #2c3e50;
        margin-top: 0;
        padding-bottom: 10px;
        border-bottom: 2px solid #ecf0f1;
    }

    .code-example {
        margin-top: 20px;
    }

    .code-example h4 {
        color: #34495e;
        margin-bottom: 10px;
    }

    .code-example pre {
        background-color: #f8f8f8;
        border: 1px solid #e1e1e1;
        border-radius: 4px;
        padding: 15px;
        overflow-x: auto;
        font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
        font-size: 13px;
        line-height: 1.4;
    }

    .code-example code {
        color: #333;
    }

    .protocol-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
        gap: 20px;
        margin: 20px 0;
    }

    .protocol-card {
        background-color: #f8f9fa;
        padding: 20px;
        border-radius: 8px;
        border: 1px solid #dee2e6;
        text-align: center;
    }

    .protocol-card h3 {
        margin-top: 0;
        color: #2c3e50;
    }

    .protocol-card code {
        background-color: #e9ecef;
        padding: 5px 10px;
        border-radius: 3px;
        font-size: 12px;
        display: block;
        margin-top: 10px;
        word-break: break-all;
    }

    .operations-list {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
        gap: 20px;
    }

    .operation-item {
        background-color: #f8f9fa;
        padding: 20px;
        border-radius: 8px;
        border: 1px solid #dee2e6;
    }

    .operation-item h4 {
        margin-top: 0;
    }

    .operation-item a {
        color: #3498db;
        text-decoration: none;
    }

    .operation-item a:hover {
        text-decoration: underline;
    }

    .operation-details {
        margin-top: 10px;
    }

    .param-count {
        background-color: #e9ecef;
        padding: 3px 8px;
        border-radius: 12px;
        font-size: 12px;
        margin-right: 10px;
        color: #495057;
    }

    .wsdl-section {
        margin-top: 40px;
        padding: 25px;
        background-color: #f8f9fa;
        border-radius: 8px;
        border: 1px solid #dee2e6;
        text-align: center;
    }

    .wsdl-links {
        margin-top: 15px;
    }

    .wsdl-link {
        display: inline-block;
        background-color: #6c757d;
        color: white;
        padding: 10px 20px;
        text-decoration: none;
        border-radius: 5px;
        margin: 0 10px;
        transition: background-color 0.3s;
    }

    .wsdl-link:hover {
        background-color: #545b62;
    }

    @media (max-width: 768px) {
        .container {
            padding: 15px;
        }

        .parameter-table,
        .parameter-table thead,
        .parameter-table tbody,
        .parameter-table th,
        .parameter-table td,
        .parameter-table tr {
            display: block;
        }

        .parameter-table thead tr {
            display: none;
        }

        .parameter-table tr {
            border: 1px solid #ccc;
            margin-bottom: 10px;
            padding: 10px;
            border-radius: 5px;
        }

        .parameter-table td {
            border: none;
            position: relative;
            padding-left: 25%;
        }

        .parameter-table td:before {
            content: attr(data-label);
            position: absolute;
            left: 6px;
            width: 45%;
            padding-right: 10px;
            white-space: nowrap;
            font-weight: bold;
        }
    }

    /* Dark mode support */
    @media (prefers-color-scheme: dark) {
        body {
            background-color: #1a1a1a;
            color: #e0e0e0;
        }

        .container {
            background-color: #2d2d2d;
            box-shadow: 0 2px 10px rgba(0,0,0,0.3);
        }

        .header {
            border-bottom-color: #444;
        }

        .header h1 {
            color: #ffffff;
        }

        .header p {
            color: #b0b0b0;
        }

        .header a {
            color: #64b5f6;
        }

        .service-description {
            color: #b0b0b0;
        }

        h2, h3, h4 {
            color: #ffffff;
        }

        .operation-section h2 {
            color: #ffffff;
            border-left-color: #64b5f6;
        }

        .operation-description {
            background-color: #3a3a3a;
            color: #d0d0d0;
        }

        .test-section {
            background-color: #333333;
            border-color: #555;
        }

        .test-section h3 {
            color: #ffffff;
        }

        .test-section p {
            color: #b0b0b0;
        }

        .parameter-table th {
            background-color: #404040;
            color: #ffffff;
        }

        .parameter-table th,
        .parameter-table td {
            border-bottom-color: #555;
        }

        .parameter-table td {
            color: #e0e0e0;
        }

        .param-input {
            background-color: #404040;
            border-color: #666;
            color: #ffffff;
        }

        .param-input::placeholder {
            color: #888;
        }

        .param-input:focus {
            border-color: #64b5f6;
            box-shadow: 0 0 0 2px rgba(100, 181, 246, 0.2);
            outline: none;
        }

        input[type="text"],
        input[type="number"],
        input[type="email"],
        input[type="date"],
        input[type="datetime-local"],
        input[type="time"],
        select {
            background-color: #404040;
            border-color: #666;
            color: #ffffff;
        }

        input[type="text"]:focus,
        input[type="number"]:focus,
        input[type="email"]:focus,
        input[type="date"]:focus,
        input[type="datetime-local"]:focus,
        input[type="time"]:focus,
        select:focus {
            border-color: #64b5f6;
            box-shadow: 0 0 0 2px rgba(100, 181, 246, 0.2);
        }

        .invoke-btn {
            background-color: #1976d2;
        }

        .invoke-btn:hover {
            background-color: #1565c0;
        }

        .json-btn {
            background-color: #2e7d32;
        }

        .json-btn:hover {
            background-color: #1b5e20;
        }

        .examples-section {
            background-color: #2d2d2d;
        }

        .protocol-section {
            background-color: #333333;
            border-color: #555;
        }

        .protocol-section h3 {
            color: #ffffff;
            border-bottom-color: #555;
        }

        .protocol-section p {
            color: #b0b0b0;
        }

        .protocol-card {
            background-color: #333333;
            border-color: #555;
        }

        .protocol-card h3 {
            color: #ffffff;
        }

        .protocol-card p {
            color: #b0b0b0;
        }

        .protocol-card code {
            background-color: #404040;
            color: #64b5f6;
        }

        .code-example h4 {
            color: #64b5f6;
        }

        .code-example pre {
            background-color: #1e1e1e;
            border-color: #555;
            color: #f8f8f2;
        }

        .code-example code {
            color: #f8f8f2;
        }

        .result-section {
            background-color: #2a3a2a;
            border-color: #4a7c4a;
        }

        .result-section h4 {
            color: #90ee90;
        }

        .result-section pre {
            background-color: #1e1e1e;
            color: #f8f8f2;
        }

        .protocols-section h2 {
            color: #ffffff;
        }

        .operations-section h2 {
            color: #ffffff;
        }

        .operation-item {
            background-color: #333333;
            border-color: #555;
        }

        .operation-item h4 a {
            color: #64b5f6;
        }

        .operation-item h4 a:hover {
            color: #90caf9;
        }

        .operation-item p {
            color: #b0b0b0;
        }

        .param-count {
            background-color: #404040;
            color: #e0e0e0;
        }

        .wsdl-section {
            background-color: #333333;
            border-color: #555;
        }

        .wsdl-section h2 {
            color: #ffffff;
        }

        .wsdl-link {
            background-color: #555;
            color: #ffffff;
        }

        .wsdl-link:hover {
            background-color: #666;
        }

        .required-indicator {
            color: #f44336;
        }

        small {
            color: #999;
        }

        a {
            color: #64b5f6;
        }

        a:hover {
            color: #90caf9;
        }
    }
    """
  end

  # Generate JavaScript for form interaction
  defp generate_javascript do
    """
    function invokeOperation(endpoint, operationName) {
        const form = document.getElementById('testForm');
        const formData = new FormData(form);
        const params = {};
        const namespace = form.dataset.namespace || 'http://tempuri.org/';
        const soapAction = form.dataset.soapAction || operationName;

        for (let [key, value] of formData.entries()) {
            if (value.trim() !== '') {
                params[key] = value;
            }
        }

        // Build SOAP envelope with namespace
        const soapEnvelope = buildSoapEnvelope(operationName, params, namespace);

        // Show loading
        const resultSection = document.getElementById('resultSection');
        const resultContent = document.getElementById('resultContent');
        resultSection.style.display = 'block';
        resultContent.textContent = 'Loading...';

        // Make SOAP request
        fetch(endpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'text/xml; charset=utf-8',
                'SOAPAction': soapAction
            },
            body: soapEnvelope
        })
        .then(response => response.text())
        .then(data => {
            resultContent.textContent = formatXml(data);
        })
        .catch(error => {
            resultContent.textContent = 'Error: ' + error.message;
        });
    }

    function buildSoapEnvelope(operationName, params, namespace) {
        let paramElements = '';
        for (const [key, value] of Object.entries(params)) {
            paramElements += '      <' + key + '>' + escapeXml(value) + '</' + key + '>\\n';
        }

        return '<?xml version="1.0" encoding="utf-8"?>\\n' +
            '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">\\n' +
            '  <soap:Body>\\n' +
            '    <' + operationName + ' xmlns="' + namespace + '">\\n' +
            paramElements +
            '    </' + operationName + '>\\n' +
            '  </soap:Body>\\n' +
            '</soap:Envelope>';
    }

    function escapeXml(text) {
        return text.toString()
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatXml(xml) {
        try {
            const parser = new DOMParser();
            const xmlDoc = parser.parseFromString(xml, 'text/xml');
            const serializer = new XMLSerializer();
            let formatted = serializer.serializeToString(xmlDoc);
            // Simple formatting: add newlines after closing tags
            formatted = formatted.replace(/></g, '>\\n<');
            return formatted;
        } catch (e) {
            return xml;
        }
    }

    function viewJSON(operationName) {
        const form = document.getElementById('testForm');
        const formData = new FormData(form);
        const params = {};

        for (let [key, value] of formData.entries()) {
            if (value.trim() !== '') {
                params[key] = value;
            }
        }

        const resultSection = document.getElementById('resultSection');
        const resultContent = document.getElementById('resultContent');
        resultSection.style.display = 'block';
        resultContent.textContent = JSON.stringify(params, null, 2);
    }
    """
  end

  # Helper functions for generating appropriate input types and placeholders
  defp get_html_input_type(:string), do: "text"
  defp get_html_input_type(:int), do: "number"
  defp get_html_input_type(:integer), do: "number"
  defp get_html_input_type(:boolean), do: "checkbox"
  defp get_html_input_type(:decimal), do: "number"
  defp get_html_input_type(:float), do: "number"
  defp get_html_input_type(:dateTime), do: "datetime-local"
  defp get_html_input_type(:date), do: "date"
  defp get_html_input_type(:time), do: "time"
  defp get_html_input_type(_), do: "text"

  defp get_type_placeholder(:string), do: "string"
  defp get_type_placeholder(:int), do: "int"
  defp get_type_placeholder(:integer), do: "integer"
  defp get_type_placeholder(:boolean), do: "boolean"
  defp get_type_placeholder(:decimal), do: "decimal"
  defp get_type_placeholder(:float), do: "float"
  defp get_type_placeholder(:dateTime), do: "dateTime"
  defp get_type_placeholder(:date), do: "date"
  defp get_type_placeholder(:time), do: "time"
  defp get_type_placeholder(type) when is_binary(type), do: type
  defp get_type_placeholder(type), do: to_string(type)

  defp get_json_placeholder(:string), do: "\"string\""
  defp get_json_placeholder(:int), do: "0"
  defp get_json_placeholder(:integer), do: "0"
  defp get_json_placeholder(:boolean), do: "true"
  defp get_json_placeholder(:decimal), do: "0.0"
  defp get_json_placeholder(:float), do: "0.0"
  defp get_json_placeholder(:dateTime), do: "\"2024-01-01T00:00:00Z\""
  defp get_json_placeholder(:date), do: "\"2024-01-01\""
  defp get_json_placeholder(:time), do: "\"00:00:00\""
  defp get_json_placeholder(type) when is_binary(type), do: "\"#{type}\""
  defp get_json_placeholder(type), do: "\"#{type}\""

  # Get current library version
  defp get_version do
    case Application.spec(:lather, :vsn) do
      version when is_list(version) -> List.to_string(version)
      _ -> "1.0.0"
    end
  end
end
