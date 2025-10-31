# Simplified Forms and Enhanced WSDL Generation Demo for Lather
# Demonstrates the new multi-protocol capabilities without Plug dependencies

# Define a test service similar to the CountryInfo service you referenced
defmodule CountryInfoTestService do
  use Lather.Server

  @namespace "http://www.oorsprong.org/websamples.countryinfo"
  @service_name "CountryInfoService"

  # Define complex types
  soap_type "Country" do
    description "Country information with flag and details"

    element "sISOCode", :string, required: true, description: "ISO country code (2 letters)"
    element "sName", :string, required: true, description: "Country name"
    element "sCurrencyISOCode", :string, required: true, description: "Currency ISO code"
    element "sCapitalCity", :string, required: true, description: "Capital city name"
    element "sContinentCode", :string, required: true, description: "Continent code"
    element "sPhoneCode", :string, required: true, description: "International phone code"
    element "sFlagUrl", :anyURI, required: false, description: "URL to country flag image"
  end

  soap_type "Currency" do
    description "Currency information"

    element "sISOCode", :string, required: true, description: "ISO currency code (3 letters)"
    element "sName", :string, required: true, description: "Currency name"
    element "sSymbol", :string, required: false, description: "Currency symbol"
  end

  # CountryFlag operation - matches the example you showed
  soap_operation "CountryFlag" do
    description "Returns a link to a picture of the country flag"

    input do
      parameter "sCountryISOCode", :string, required: true, description: "ISO country code"
    end

    output do
      parameter "CountryFlagResult", :string, description: "URL to country flag image"
    end

    soap_action "http://www.oorsprong.org/websamples.countryinfo/CountryFlag"
  end

  def country_flag(%{"sCountryISOCode" => country_code}) do
    {:ok, %{"CountryFlagResult" => "https://flagpedia.net/data/flags/w580/#{String.downcase(country_code)}.png"}}
  end

  # CountryName operation
  soap_operation "CountryName" do
    description "Returns the country name for the specified ISO country code"

    input do
      parameter "sCountryISOCode", :string, required: true, description: "ISO country code"
    end

    output do
      parameter "CountryNameResult", :string, description: "Country name"
    end

    soap_action "http://www.oorsprong.org/websamples.countryinfo/CountryName"
  end

  def country_name(%{"sCountryISOCode" => country_code}) do
    country_names = %{
      "US" => "United States",
      "CA" => "Canada",
      "GB" => "United Kingdom",
      "DE" => "Germany",
      "FR" => "France"
    }

    name = Map.get(country_names, String.upcase(country_code), "Unknown Country")
    {:ok, %{"CountryNameResult" => name}}
  end

  # More complex operation
  soap_operation "FullCountryInfo" do
    description "Returns complete country information including currency and capital"

    input do
      parameter "sCountryISOCode", :string, required: true, description: "ISO country code"
    end

    output do
      parameter "FullCountryInfoResult", "Country", description: "Complete country information"
    end

    soap_action "http://www.oorsprong.org/websamples.countryinfo/FullCountryInfo"
  end

  def full_country_info(%{"sCountryISOCode" => country_code}) do
    {:ok, %{"FullCountryInfoResult" => %{
      "sISOCode" => country_code,
      "sName" => "United States",
      "sCurrencyISOCode" => "USD",
      "sCapitalCity" => "Washington, D.C.",
      "sContinentCode" => "AM",
      "sPhoneCode" => "1",
      "sFlagUrl" => "https://flagpedia.net/data/flags/w580/us.png"
    }}}
  end
end

# Generate the demonstrations
IO.puts("🌟 LATHER ENHANCED FORMS & WSDL GENERATION DEMO")
IO.puts("=" * 80)
IO.puts("")

service_info = CountryInfoTestService.__soap_service__()
base_url = "http://webservices.example.org/countryinfo/"

IO.puts("📋 SERVICE INFORMATION")
IO.puts("- Service: #{service_info.name}")
IO.puts("- Namespace: #{service_info.namespace}")
IO.puts("- Operations: #{length(service_info.operations)}")
IO.puts("- Types: #{length(service_info.types)}")
IO.puts("")

# Generate Standard WSDL
IO.puts("📄 1. STANDARD WSDL (SOAP 1.1 Only)")
IO.puts("-" * 60)
standard_wsdl = Lather.Server.WSDLGenerator.generate(service_info, base_url)
standard_lines = String.split(standard_wsdl, "\n")
IO.puts("Total lines: #{length(standard_lines)}")
IO.puts("Contains SOAP 1.1 binding: #{String.contains?(standard_wsdl, "soap:binding")}")
IO.puts("Contains SOAP 1.2 binding: #{String.contains?(standard_wsdl, "soap12:binding")}")
IO.puts("")

# Generate Enhanced Multi-Protocol WSDL
IO.puts("🚀 2. ENHANCED MULTI-PROTOCOL WSDL")
IO.puts("-" * 60)
enhanced_wsdl = Lather.Server.EnhancedWSDLGenerator.generate(
  service_info,
  base_url,
  protocols: [:soap_1_1, :soap_1_2, :http],
  base_path: "/api",
  include_json: true
)
enhanced_lines = String.split(enhanced_wsdl, "\n")
IO.puts("Total lines: #{length(enhanced_lines)}")
IO.puts("Contains SOAP 1.1 binding: #{String.contains?(enhanced_wsdl, "soap:binding")}")
IO.puts("Contains SOAP 1.2 binding: #{String.contains?(enhanced_wsdl, "soap12:binding")}")
IO.puts("Contains HTTP binding: #{String.contains?(enhanced_wsdl, "http:binding")}")
IO.puts("Contains multi-protocol documentation: #{String.contains?(enhanced_wsdl, "Multi-Protocol")}")
IO.puts("")

# Show a sample of the enhanced WSDL
IO.puts("📝 ENHANCED WSDL SAMPLE (First 50 lines):")
IO.puts("-" * 40)
enhanced_wsdl
|> String.split("\n")
|> Enum.take(50)
|> Enum.with_index(1)
|> Enum.each(fn {line, num} ->
  IO.puts("#{String.pad_leading(to_string(num), 3)}: #{line}")
end)
IO.puts("... (#{length(enhanced_lines) - 50} more lines)")
IO.puts("")

# Generate HTML Form for CountryFlag operation (like the example you showed)
IO.puts("🖥️  3. INTERACTIVE HTML FORM (CountryFlag Operation)")
IO.puts("-" * 60)
country_flag_op = Enum.find(service_info.operations, &(&1.name == "CountryFlag"))
form_html = Lather.Server.FormGenerator.generate_operation_page(
  service_info,
  country_flag_op,
  base_url
)
IO.puts("Generated HTML form: #{String.length(form_html)} characters")
IO.puts("Contains SOAP 1.1 example: #{String.contains?(form_html, "SOAP 1.1")}")
IO.puts("Contains SOAP 1.2 example: #{String.contains?(form_html, "SOAP 1.2")}")
IO.puts("Contains JSON example: #{String.contains?(form_html, "JSON")}")
IO.puts("Contains interactive form: #{String.contains?(form_html, "<form")}")
IO.puts("Contains JavaScript: #{String.contains?(form_html, "<script>")}")
IO.puts("")

# Generate Service Overview
IO.puts("🏠 4. SERVICE OVERVIEW PAGE")
IO.puts("-" * 60)
overview_html = Lather.Server.FormGenerator.generate_service_overview(service_info, base_url)
IO.puts("Generated overview page: #{String.length(overview_html)} characters")
IO.puts("Lists all operations: #{String.contains?(overview_html, "Available Operations")}")
IO.puts("Shows protocol endpoints: #{String.contains?(overview_html, "Supported Protocols")}")
IO.puts("Includes WSDL links: #{String.contains?(overview_html, "Download WSDL")}")
IO.puts("")

# Show the form structure for CountryFlag (matching your example)
IO.puts("📋 5. COUNTRYLAG OPERATION FORM DETAILS")
IO.puts("-" * 60)
IO.puts("Operation: #{country_flag_op.name}")
IO.puts("Description: #{country_flag_op.description}")
IO.puts("Input Parameters:")
for param <- country_flag_op.input do
  IO.puts("  - #{param.name}: #{param.type} #{if param.required, do: "(required)", else: "(optional)"}")
  if param.description, do: IO.puts("    #{param.description}")
end
IO.puts("Output Parameters:")
for param <- country_flag_op.output do
  IO.puts("  - #{param.name}: #{param.type}")
  if param.description, do: IO.puts("    #{param.description}")
end
IO.puts("")

# Show the URLs that would be generated
IO.puts("🌐 6. GENERATED URLS (Like CountryInfo Service)")
IO.puts("-" * 60)
service_name = service_info.name
IO.puts("Service Overview:")
IO.puts("  #{base_url}#{service_name}")
IO.puts("")
IO.puts("CountryFlag Operation Form:")
IO.puts("  #{base_url}#{service_name}?op=CountryFlag")
IO.puts("")
IO.puts("WSDL Downloads:")
IO.puts("  #{base_url}#{service_name}?wsdl")
IO.puts("  #{base_url}#{service_name}?wsdl&enhanced=true")
IO.puts("")
IO.puts("SOAP Endpoints:")
IO.puts("  POST #{base_url}#{service_name}  (SOAP 1.1)")
IO.puts("  POST #{base_url}#{service_name}/v1.2  (SOAP 1.2)")
IO.puts("")
IO.puts("REST/JSON Endpoint:")
IO.puts("  POST #{base_url}api/#{String.downcase(service_name)}/countryflag")
IO.puts("")

# Show what the form would look like (text representation)
IO.puts("📝 7. FORM INTERFACE PREVIEW")
IO.puts("-" * 60)
IO.puts("CountryInfoService - CountryFlag")
IO.puts("")
IO.puts("Returns a link to a picture of the country flag")
IO.puts("")
IO.puts("Test")
IO.puts("To test the operation using the HTTP POST protocol, click the 'Invoke' button.")
IO.puts("")
IO.puts("┌─────────────────┬─────────────────────────────────────────────┐")
IO.puts("│ Parameter       │ Value                                       │")
IO.puts("├─────────────────┼─────────────────────────────────────────────┤")
IO.puts("│ sCountryISOCode │ [_________________________] (required)      │")
IO.puts("└─────────────────┴─────────────────────────────────────────────┘")
IO.puts("")
IO.puts("                [Invoke] [View JSON Format]")
IO.puts("")

# Show protocol examples
IO.puts("📡 8. PROTOCOL EXAMPLES")
IO.puts("-" * 60)
IO.puts("")
IO.puts("SOAP 1.1 Request:")
IO.puts("POST /CountryInfoService.wso HTTP/1.1")
IO.puts("Host: webservices.example.org")
IO.puts("Content-Type: text/xml; charset=utf-8")
IO.puts("SOAPAction: \"http://www.oorsprong.org/websamples.countryinfo/CountryFlag\"")
IO.puts("")
IO.puts("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
IO.puts("<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\">")
IO.puts("  <soap:Body>")
IO.puts("    <CountryFlag xmlns=\"http://www.oorsprong.org/websamples.countryinfo\">")
IO.puts("      <sCountryISOCode>US</sCountryISOCode>")
IO.puts("    </CountryFlag>")
IO.puts("  </soap:Body>")
IO.puts("</soap:Envelope>")
IO.puts("")

IO.puts("SOAP 1.2 Request:")
IO.puts("POST /CountryInfoService.wso HTTP/1.1")
IO.puts("Host: webservices.example.org")
IO.puts("Content-Type: application/soap+xml; charset=utf-8; action=\"http://www.oorsprong.org/websamples.countryinfo/CountryFlag\"")
IO.puts("")
IO.puts("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
IO.puts("<soap12:Envelope xmlns:soap12=\"http://www.w3.org/2003/05/soap-envelope\">")
IO.puts("  <soap12:Body>")
IO.puts("    <CountryFlag xmlns=\"http://www.oorsprong.org/websamples.countryinfo\">")
IO.puts("      <sCountryISOCode>US</sCountryISOCode>")
IO.puts("    </CountryFlag>")
IO.puts("  </soap12:Body>")
IO.puts("</soap12:Envelope>")
IO.puts("")

IO.puts("JSON Request:")
IO.puts("POST /api/countryinfoservice/countryflag HTTP/1.1")
IO.puts("Host: webservices.example.org")
IO.puts("Content-Type: application/json; charset=utf-8")
IO.puts("")
IO.puts("{")
IO.puts("  \"sCountryISOCode\": \"US\"")
IO.puts("}")
IO.puts("")

# Summary of features
IO.puts("✨ 9. FEATURES IMPLEMENTED")
IO.puts("-" * 60)
IO.puts("✅ Enhanced WSDL Generation:")
IO.puts("   - SOAP 1.1 bindings (maximum compatibility)")
IO.puts("   - SOAP 1.2 bindings (enhanced features)")
IO.puts("   - HTTP/REST bindings (modern APIs)")
IO.puts("   - Multiple service endpoints")
IO.puts("   - Comprehensive documentation")
IO.puts("")
IO.puts("✅ Interactive HTML Forms:")
IO.puts("   - Web-based operation testing")
IO.puts("   - Parameter validation")
IO.puts("   - Protocol examples (SOAP 1.1, 1.2, JSON)")
IO.puts("   - Responsive design")
IO.puts("   - JavaScript form submission")
IO.puts("")
IO.puts("✅ Service Overview Pages:")
IO.puts("   - Complete operation listing")
IO.puts("   - Protocol endpoint documentation")
IO.puts("   - WSDL download links")
IO.puts("   - Professional appearance")
IO.puts("")
IO.puts("✅ Multi-Protocol Support:")
IO.puts("   - Legacy SOAP 1.1 clients")
IO.puts("   - Modern SOAP 1.2 clients")
IO.puts("   - REST/JSON web applications")
IO.puts("   - Automatic content negotiation")
IO.puts("")

IO.puts("🎉 SUCCESS: Enhanced WSDL and Forms Generation Complete!")
IO.puts("   This implementation provides the same layered API approach")
IO.puts("   as modern .NET and Java web services with:")
IO.puts("   📄 SOAP 1.1 at the top (maximum compatibility)")
IO.puts("   🚀 SOAP 1.2 in the middle (enhanced features)")
IO.puts("   🌐 REST/JSON at the bottom (modern web apps)")
IO.puts("")
IO.puts("=" * 80)
