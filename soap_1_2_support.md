# SOAP 1.2 Support Implementation Plan

**Project**: Lather SOAP Library SOAP 1.2 Support  
**Target Version**: v1.0.0  
**Estimated Total Effort**: 6-8 hours (1 development day)  
**Status**: Ready to begin  
**Created**: January 2025

---

## Overview

This document outlines the implementation plan to add comprehensive SOAP 1.2 support to the Lather SOAP library. SOAP 1.2 support is a key milestone for the v1.0 release and will enable integration with modern SOAP services that require the updated protocol.

### Current Status ✅

**Already Implemented:**
- ✅ SOAP 1.2 namespace constant defined (`@soap_1_2_namespace`)
- ✅ Version parameter support in `Envelope.build/3` (`:v1_1` or `:v1_2`)
- ✅ WSDL analyzer handles both SOAP 1.1 and 1.2 bindings
- ✅ Basic SOAP 1.2 envelope generation working
- ✅ SOAP 1.2 response parsing (partial)
- ✅ Some test coverage exists

**Key Files with Existing Support:**
- `lib/lather/soap/envelope.ex` - Core envelope handling
- `lib/lather/wsdl/analyzer.ex` - WSDL parsing for both versions
- `lib/lather/http/transport.ex` - HTTP transport layer
- `test/lather/soap/envelope_test.exs` - Basic SOAP 1.2 tests

### What Needs Implementation 🔧

1. **HTTP Content-Type Headers** - SOAP 1.2 uses different MIME types
2. **SOAPAction Header Handling** - SOAP 1.2 embeds action in Content-Type
3. **Enhanced Fault Structure** - More robust SOAP 1.2 fault parsing
4. **Integration Layer** - Version propagation through request pipeline
5. **Comprehensive Testing** - Full test coverage for SOAP 1.2 scenarios

---

## Implementation Phases

### Phase 1: Core HTTP Transport Updates
**Effort**: 2-3 hours  
**Priority**: High  
**Dependencies**: None

#### Objectives
- Update HTTP transport to use correct Content-Type headers for SOAP 1.2
- Implement SOAPAction vs Content-Type action handling
- Ensure backward compatibility with SOAP 1.1

#### Tasks

##### 1.1 Update Content-Type Headers
**File**: `lib/lather/http/transport.ex`
**Lines**: 15-19 (current `@default_headers`)

```elixir
# Current implementation:
@default_headers [
  {"content-type", "text/xml; charset=utf-8"},
  {"accept", "text/xml"},
  {"soapaction", ""}
]

# Needs to become version-aware
```

**Implementation:**
- [ ] Create `build_headers/2` function that accepts SOAP version
- [ ] SOAP 1.1: `text/xml; charset=utf-8`
- [ ] SOAP 1.2: `application/soap+xml; charset=utf-8`
- [ ] Update `post/3` function to accept version parameter

##### 1.2 SOAPAction Header Handling
**SOAP 1.1**: Uses separate `SOAPAction: "action"` header  
**SOAP 1.2**: Embeds in Content-Type: `application/soap+xml; charset=utf-8; action="action"`

**Implementation:**
- [ ] Update `build_headers/1` to handle version-specific action embedding
- [ ] SOAP 1.1: Keep existing SOAPAction header behavior
- [ ] SOAP 1.2: Embed action in Content-Type header
- [ ] Remove SOAPAction header for SOAP 1.2 requests

##### 1.3 Transport Integration
**File**: `lib/lather/http/transport.ex`

**Implementation:**
- [ ] Add `:soap_version` option to `post/3` function
- [ ] Update function signature: `post(url, body, options \\ [])`
- [ ] Default to `:v1_1` for backward compatibility
- [ ] Pass version to header building functions

#### Deliverables
- [ ] Updated `Transport.post/3` with version support
- [ ] Version-aware header generation
- [ ] Backward compatible SOAP 1.1 support
- [ ] Unit tests for header generation

#### Acceptance Criteria
- [ ] SOAP 1.1 requests use `text/xml` Content-Type
- [ ] SOAP 1.2 requests use `application/soap+xml` Content-Type
- [ ] SOAP 1.1 uses SOAPAction header
- [ ] SOAP 1.2 embeds action in Content-Type header
- [ ] All existing tests pass (backward compatibility)
- [ ] New tests cover both SOAP versions

---

### Phase 2: Enhanced Envelope and Parsing
**Effort**: 2-3 hours  
**Priority**: High  
**Dependencies**: Phase 1 complete

#### Objectives
- Improve SOAP 1.2 fault structure parsing
- Ensure robust version detection in responses
- Enhance envelope building for version-specific features

#### Tasks

##### 2.1 Enhanced Fault Parsing
**File**: `lib/lather/soap/envelope.ex`
**Lines**: 129-135 (current `extract_fault/1`)

**Current Implementation Issues:**
- Basic fault parsing that works but could be more robust
- SOAP 1.2 has nested structure: `soap:Code/soap:Value`, `soap:Reason/soap:Text`

**Implementation:**
- [ ] Create `extract_soap_1_1_fault/1` function
- [ ] Create `extract_soap_1_2_fault/1` function  
- [ ] Update `extract_fault/1` to detect version and route appropriately
- [ ] Handle SOAP 1.2 nested fault elements properly
- [ ] Support multiple reason text elements (language support)

**SOAP 1.2 Fault Structure to Support:**
```xml
<soap:Fault>
  <soap:Code>
    <soap:Value>soap:Sender</soap:Value>
    <soap:Subcode>
      <soap:Value>m:MessageTimeout</soap:Value>
    </soap:Subcode>
  </soap:Code>
  <soap:Reason>
    <soap:Text xml:lang="en">Message Timeout</soap:Text>
    <soap:Text xml:lang="de">Nachricht Timeout</soap:Text>
  </soap:Reason>
  <soap:Detail>
    <m:MaxTime>60</m:MaxTime>
  </soap:Detail>
</soap:Fault>
```

##### 2.2 Version Detection in Responses
**File**: `lib/lather/soap/envelope.ex`

**Implementation:**
- [ ] Create `detect_soap_version/1` function to analyze response XML
- [ ] Check envelope namespace to determine version
- [ ] Use version info to route fault parsing appropriately
- [ ] Update `parse_response/1` to use version detection

##### 2.3 Envelope Building Enhancements
**File**: `lib/lather/soap/envelope.ex`
**Lines**: 32-47 (current `build/3`)

**Implementation:**
- [ ] Ensure version parameter properly propagates
- [ ] Add SOAP 1.2 specific envelope features if needed
- [ ] Validate namespace usage consistency
- [ ] Update tests for enhanced building

#### Deliverables
- [ ] Robust SOAP 1.2 fault parsing
- [ ] Version detection in responses
- [ ] Enhanced envelope building
- [ ] Comprehensive fault structure tests

#### Acceptance Criteria
- [ ] SOAP 1.2 faults parsed correctly with nested structure
- [ ] SOAP 1.1 faults continue to work (backward compatibility)
- [ ] Version detection works for both envelope formats  
- [ ] Multiple language reasons supported in SOAP 1.2 faults
- [ ] Subcodes extracted properly from SOAP 1.2 faults

---

### Phase 3: Integration Layer Updates
**Effort**: 1-2 hours  
**Priority**: Medium  
**Dependencies**: Phase 2 complete

#### Objectives
- Propagate SOAP version through the entire request pipeline
- Update DynamicClient to support SOAP version selection
- Ensure WSDL analysis correctly determines protocol version

#### Tasks

##### 3.1 DynamicClient Updates
**File**: `lib/lather/dynamic_client.ex`

**Implementation:**
- [ ] Add `:soap_version` option to `new/2` function
- [ ] Auto-detect SOAP version from WSDL if not specified
- [ ] Store version in client state
- [ ] Pass version to Transport layer in `call/3`

##### 3.2 WSDL Version Detection
**File**: `lib/lather/wsdl/analyzer.ex`
**Lines**: 325-335 (existing SOAP 1.1/1.2 handling)

**Implementation:**
- [ ] Create `detect_soap_version_from_wsdl/1` function
- [ ] Check for `soap:` vs `soap12:` bindings
- [ ] Return detected version in service info
- [ ] Add version to `ServiceInfo` struct

##### 3.3 Request Pipeline Integration
**Files**: 
- `lib/lather/dynamic_client.ex`
- `lib/lather/soap/envelope.ex`
- `lib/lather/http/transport.ex`

**Implementation:**
- [ ] Ensure version flows from DynamicClient → Envelope → Transport
- [ ] Update all intermediate function signatures
- [ ] Maintain backward compatibility with default version
- [ ] Add version to request context/options

#### Deliverables
- [ ] Version-aware DynamicClient
- [ ] WSDL-based version detection
- [ ] End-to-end version propagation
- [ ] Integration tests

#### Acceptance Criteria
- [ ] Version can be specified explicitly in DynamicClient
- [ ] Version auto-detected from WSDL when possible
- [ ] Entire request pipeline uses consistent version
- [ ] Both SOAP 1.1 and 1.2 requests work end-to-end
- [ ] Version information preserved throughout request lifecycle

---

### Phase 4: Comprehensive Testing and Documentation
**Effort**: 2-3 hours  
**Priority**: High  
**Dependencies**: Phases 1-3 complete

#### Objectives
- Add comprehensive test coverage for SOAP 1.2 scenarios
- Update documentation and examples
- Performance and compatibility testing
- Edge case handling

#### Tasks

##### 4.1 Test Suite Expansion
**Files**:
- `test/lather/soap/envelope_test.exs`
- `test/lather/http/transport_test.exs`  
- `test/lather/dynamic_client_test.exs`
- `test/integration/soap_1_2_integration_test.exs` (new)

**Test Categories:**
- [ ] **Header Tests**: Content-Type and action handling
- [ ] **Fault Tests**: SOAP 1.2 fault structure parsing
- [ ] **Version Detection**: Auto-detection from WSDL/responses
- [ ] **Integration Tests**: End-to-end SOAP 1.2 requests
- [ ] **Error Handling**: Malformed SOAP 1.2 responses
- [ ] **Backward Compatibility**: Ensure SOAP 1.1 still works

**Specific Test Cases:**
```elixir
# test/integration/soap_1_2_integration_test.exs
describe "SOAP 1.2 Integration" do
  test "makes successful SOAP 1.2 request with correct headers"
  test "handles SOAP 1.2 faults with nested structure"  
  test "auto-detects SOAP 1.2 from WSDL"
  test "handles mixed SOAP 1.1/1.2 WSDLs"
  test "processes complex SOAP 1.2 fault with subcodes"
  test "supports multiple language fault reasons"
end
```

##### 4.2 Documentation Updates
**Files**:
- `README.md`
- `API.md`
- `CHANGELOG.md`
- `examples/soap_1_2_example.ex` (new)

**Documentation Tasks:**
- [ ] Update README with SOAP 1.2 support announcement
- [ ] Add SOAP 1.2 examples to API documentation
- [ ] Create example showing version selection
- [ ] Update CHANGELOG with SOAP 1.2 features
- [ ] Document version auto-detection behavior

##### 4.3 Performance Testing
**Implementation:**
- [ ] Benchmark SOAP 1.1 vs SOAP 1.2 performance
- [ ] Memory usage comparison
- [ ] Ensure no performance regressions
- [ ] Document any performance differences

##### 4.4 Edge Case Testing
**Test Scenarios:**
- [ ] Malformed SOAP 1.2 responses
- [ ] Mixed version environments
- [ ] Version mismatch error handling
- [ ] Large SOAP 1.2 fault structures
- [ ] Unicode in SOAP 1.2 fault reasons

#### Deliverables
- [ ] Comprehensive test suite (90%+ coverage)
- [ ] Updated documentation
- [ ] Performance benchmarks
- [ ] Edge case handling
- [ ] Example implementations

#### Acceptance Criteria
- [ ] Test coverage ≥90% for SOAP 1.2 code paths
- [ ] All edge cases handled gracefully
- [ ] Documentation examples work correctly
- [ ] Performance within 5% of SOAP 1.1
- [ ] No backward compatibility regressions

---

## Testing Strategy

### Unit Tests
- **Transport Layer**: Header generation, version handling
- **Envelope Layer**: Building, parsing, fault extraction
- **Client Layer**: Version propagation, option handling

### Integration Tests
- **External API Tests**: Use existing SOAP 1.2 services (when enabled)
- **Mock Service Tests**: Controlled SOAP 1.2 scenarios
- **Version Detection**: WSDL analysis and response parsing

### Compatibility Tests
- **Regression Tests**: Ensure SOAP 1.1 functionality unchanged
- **Mixed Environment**: Both versions in same application
- **Version Migration**: Upgrading existing SOAP 1.1 usage

### Performance Tests
- **Throughput**: Requests per second comparison
- **Memory Usage**: Heap allocation analysis
- **Latency**: Response time measurement

---

## Implementation Order

### Day 1 (6-8 hours)
1. **Phase 1**: Core HTTP Transport (2-3 hours)
2. **Phase 2**: Enhanced Parsing (2-3 hours) 
3. **Phase 3**: Integration (1-2 hours)

### Phase 4 can be done in parallel or as follow-up
- Testing and documentation (2-3 hours)
- Can be spread across multiple sessions

---

## Rollout Plan

### Development
1. ✅ **Phase 1**: Transport layer updates
2. ✅ **Phase 2**: Enhanced parsing  
3. ✅ **Phase 3**: Integration layer
4. ✅ **Phase 4**: Testing and docs

### Release Strategy
1. **v0.9.1**: Internal testing release with SOAP 1.2 support
2. **v1.0.0-rc1**: Release candidate with full documentation
3. **v1.0.0**: Official release with SOAP 1.2 support

### Backward Compatibility
- All existing SOAP 1.1 code continues to work unchanged
- SOAP 1.1 remains the default version
- SOAP 1.2 is opt-in via explicit version parameter

---

## Success Metrics

### Technical Metrics
- [ ] 100% backward compatibility maintained
- [ ] SOAP 1.2 test coverage ≥90%
- [ ] No performance regression >5%
- [ ] All phases completed within effort estimate

### Feature Completeness  
- [ ] SOAP 1.2 envelope building ✓
- [ ] SOAP 1.2 response parsing ✓
- [ ] SOAP 1.2 fault handling ✓
- [ ] Version auto-detection ✓
- [ ] Content-Type header handling ✓

### Quality Gates
- [ ] All existing tests pass
- [ ] New SOAP 1.2 tests pass
- [ ] Documentation examples work
- [ ] Integration tests with real services pass
- [ ] Performance benchmarks acceptable

---

## Risk Mitigation

### Technical Risks
**Risk**: Breaking backward compatibility  
**Mitigation**: Comprehensive regression testing, default to SOAP 1.1

**Risk**: Performance degradation  
**Mitigation**: Benchmarking, performance tests

**Risk**: Incomplete fault parsing  
**Mitigation**: Extensive fault structure test cases

### Timeline Risks
**Risk**: Scope creep beyond 8 hours  
**Mitigation**: Well-defined phases, clear acceptance criteria

**Risk**: Integration complexity  
**Mitigation**: Phase-based approach, early integration testing

---

## Getting Started

### Prerequisites
- [ ] Current codebase understanding ✅
- [ ] Development environment ready ✅
- [ ] Test suite running ✅

### Next Steps
1. **Review this document** and adjust phases if needed
2. **Begin Phase 1** with HTTP transport updates
3. **Run existing tests** to establish baseline
4. **Implement incrementally** with tests at each step

### Phase 1 Starting Point
**First task**: Update `lib/lather/http/transport.ex` header handling
**First test**: Verify SOAP 1.2 Content-Type headers generated correctly
**Expected time**: 30 minutes to first working test

---

**Ready to begin implementation!** 🚀

The foundation is solid, the plan is clear, and the effort is well-scoped. SOAP 1.2 support will be a major milestone toward the v1.0 release.