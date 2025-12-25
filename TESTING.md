# Testing Guide: Responsible API Testing Practices

## Overview

The Lather SOAP library includes comprehensive integration tests that validate functionality against real-world SOAP APIs. However, these tests make actual HTTP requests to public services, which raises important considerations about responsible usage.

## The Challenge with Live API Testing

### Benefits of Live API Testing ✅
- **Real-world validation**: Tests against actual SOAP service implementations
- **Edge case discovery**: Uncovers issues that mocks might miss
- **Protocol compliance**: Ensures compatibility with diverse SOAP standards
- **Production confidence**: Validates the library works with actual services

### Risks and Concerns ⚠️
- **API abuse**: Too many automated requests can overload public services
- **Rate limiting**: Services may block or throttle excessive usage
- **Unreliable tests**: Network issues cause false test failures
- **Slow test suite**: HTTP calls add significant latency
- **Ethical concerns**: Public APIs aren't meant for heavy automated testing

## Current Live API Test Coverage

### Services Tested
1. **National Weather Service NDFD** 
   - URL: `https://graphical.weather.gov/xml/SOAP_server/ndfdXMLserver.php?wsdl`
   - Style: document/encoded
   - Tests: 3 integration tests

2. **Country Info Service**
   - URL: `http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso?WSDL`
   - Style: document/literal
   - Tests: 12 integration tests (~20+ HTTP calls per run)

### Call Volume Analysis
A single full test run makes approximately **25+ HTTP requests** to public APIs:
- Weather Service: ~6 calls
- Country Info Service: ~20+ calls

**This is excessive for regular testing!**

## Responsible Testing Strategy

### Environment-Controlled Live Testing

Live API tests are **disabled by default** and only run when explicitly enabled:

```bash
# Regular test run (live API tests skipped by default)
mix test

# Enable live API testing (use sparingly!)
mix test --include external_api

# Run only specific integration tests
mix test --include external_api test/integration/country_info_service_test.exs
```

### When to Enable Live API Tests

✅ **Appropriate use cases:**
- Initial development and debugging
- Before major releases
- When investigating reported issues with specific services
- Manual testing during development cycles
- CI/CD pipeline for releases (not every commit)

❌ **Avoid for:**
- Regular development workflow
- Every commit/push
- Automated testing that runs frequently
- Learning or experimentation

### Alternative Testing Approaches

#### 1. Mock-Based Testing
```elixir
# Example: Mock SOAP responses for unit testing
defmodule Lather.MockSoapService do
  def country_list_response do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <m:ListOfCountryNamesByNameResponse xmlns:m="http://www.oorsprong.org/websamples.countryinfo">
          <m:ListOfCountryNamesByNameResult>
            <m:tCountryCodeAndName>
              <m:sISOCode>US</m:sISOCode>
              <m:sName>United States</m:sName>
            </m:tCountryCodeAndName>
          </m:ListOfCountryNamesByNameResult>
        </m:ListOfCountryNamesByNameResponse>
      </soap:Body>
    </soap:Envelope>
    """
  end
end
```

#### 2. Recorded Response Testing
- Record real API responses once
- Replay them in tests without live calls
- Update recordings when API changes

#### 3. Local Test Services
- Set up local SOAP services for testing
- Use Docker containers with SOAP servers
- Control the service behavior and responses

## Implementation Details

### Test Control Mechanism

Live API tests use the `@moduletag :external_api` tag and are excluded by default in the test configuration:

```elixir
# In test/test_helper.exs
ExUnit.configure(exclude: [:external_api])

# In integration test files
@moduletag :external_api

setup do
  # Proceed with live API testing when tag is included
  case DynamicClient.new(@wsdl_url) do
    {:ok, client} -> {:ok, client: client}
    {:error, reason} -> {:skip, "Service unavailable: #{inspect(reason)}"}
  end
end
```

### Test Tags

Live API tests are tagged for easy identification:

```elixir
@moduletag :external_api    # External API dependency
@moduletag :slow           # Takes significant time
@moduletag timeout: 30_000 # Extended timeout
```

## Best Practices for Contributors

### For Library Development

1. **Default to Mocks**: Write unit tests with mocked responses first
2. **Minimal Live Testing**: Use live APIs only for critical validation
3. **Batch Testing**: Run live API tests in batches, not continuously
4. **Cache Results**: Cache WSDL parsing results when possible
5. **Fail Gracefully**: Handle network errors as skips, not failures

### For CI/CD Pipelines

```yaml
# Example GitHub Actions configuration
- name: Run Unit Tests
  run: mix test

- name: Run Integration Tests (Release Only)
  if: github.event_name == 'release'
  run: mix test --include external_api
```

### For Local Development

```bash
# Daily development (fast, no network calls)
mix test

# Before committing significant changes
mix test --only external_api

# Full validation before release (unit + integration tests)
mix test --include external_api
```

## Service-Specific Considerations

### National Weather Service
- **Rate Limits**: Unknown, but government service should be used respectfully
- **Availability**: Generally reliable but can have maintenance windows
- **Usage Policy**: Public service meant for general use

### Country Info Service
- **Rate Limits**: Unknown, appears to be a demo/example service
- **Availability**: Third-party service, may have limitations
- **Usage Policy**: Appears to be for demonstration/learning purposes

### General Guidelines
- **Respect robots.txt** if present
- **Add delays** between requests if needed
- **Monitor for rate limiting** responses
- **Use appropriate User-Agent** headers
- **Consider alternatives** like documented mock services

## Future Improvements

### Short Term
- [ ] Implement response recording/playback system
- [ ] Add configurable delays between requests
- [ ] Create comprehensive mock responses
- [ ] Add rate limiting detection

### Long Term
- [ ] Set up local SOAP test services with Docker
- [ ] Implement property-based testing with generated data
- [ ] Create service-agnostic integration test framework
- [ ] Add performance benchmarking without live calls

## Conclusion

Live API testing is valuable but must be used responsibly. The tag-based exclusion system ensures that:

- **Default behavior is respectful** (no live calls)
- **Live testing is intentional** (explicit opt-in via `--include external_api`)
- **Tests remain fast** for regular development
- **Integration validation** is still possible when needed

**Remember**: Public APIs are shared resources. Use them thoughtfully and sparingly in automated testing.

---

*For questions about testing practices or to report issues with specific services, please open an issue in the repository.*