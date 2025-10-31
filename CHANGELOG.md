# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2025-10-30

### Added
- 🚀 **Complete SOAP Client Framework**
  - Generic SOAP client with dynamic operation discovery
  - WSDL parsing and analysis with comprehensive type extraction
  - Dynamic client generation from any WSDL
  - Support for complex types, arrays, and nested structures
  - Automatic type mapping and struct generation

- 🛡️ **Authentication & Security**
  - WS-Security UsernameToken support (PasswordText & PasswordDigest)
  - HTTP Basic Authentication
  - Custom authentication headers
  - Timestamp and nonce generation
  - Pluggable authentication system

- 🖥️ **SOAP Server Framework**
  - Complete server-side SOAP implementation
  - Macro-based DSL for defining SOAP services
  - Automatic WSDL generation from service definitions
  - Phoenix integration via Plug
  - Generic HTTP handler for standalone deployment
  - Operation dispatch and request/response handling

- 🏗️ **Core Infrastructure**
  - Robust XML parsing and generation
  - SOAP envelope construction and parsing
  - HTTP transport with Finch (connection pooling, SSL/TLS)
  - Comprehensive error handling with structured error types
  - Telemetry integration for observability
  - Support for SOAP 1.1 standard

- 📚 **Documentation & Examples**
  - 5 comprehensive Livebook tutorials
  - Interactive client examples with real SOAP services
  - Server implementation guides
  - Type system and debugging tutorials
  - Enterprise integration patterns
  - Complete API documentation

### Features
- **Universal WSDL Support**: Works with any SOAP service without hardcoded implementations
- **Type Safety**: Automatic type validation and conversion
- **Phoenix Integration**: Seamless integration with Phoenix applications
- **Production Ready**: Comprehensive error handling, logging, and monitoring
- **Extensible**: Pluggable architecture for custom authentication and transport

### Technical Details
- Built on Elixir 1.14+ and OTP 25+
- Uses Finch for HTTP transport with connection pooling
- SweetXml for robust XML parsing
- Custom XML builder for reliable SOAP envelope generation
- Telemetry for metrics and observability
- Optional Plug dependency for Phoenix integration

### Compatibility
- SOAP 1.1 (SOAP 1.2 planned for v1.0)
- WSDL 1.1 with XSD schema support
- HTTP and HTTPS transport
- Works with any SOAP service (tested with multiple public APIs)

## [Unreleased]

### Planned for v1.0.0
- SOAP 1.2 support
- Enhanced WS-Security features
- Performance optimizations
- Additional server examples
- Binary attachment support (MTOM)
- Advanced WS-* standards support

---

**Note**: This library went from concept to full-featured SOAP ecosystem in record time, 
delivering both client and server capabilities that were originally planned across multiple phases.