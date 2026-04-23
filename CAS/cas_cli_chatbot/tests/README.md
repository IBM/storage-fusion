# CAS Chatbot Test Suite

Comprehensive test suite for the CAS Chatbot application with unit tests, integration tests, and end-to-end workflows.

## 📋 Table of Contents

- [Overview](#overview)
- [Test Structure](#test-structure)
- [Installation](#installation)
- [Running Tests](#running-tests)
- [Test Coverage](#test-coverage)
- [Writing Tests](#writing-tests)
- [Test Markers](#test-markers)
- [Continuous Integration](#continuous-integration)

## 🎯 Overview

The test suite includes:
- **250+ test cases** covering all major components
- **Unit tests** for individual services and utilities
- **Integration tests** for service interactions
- **End-to-end tests** for complete workflows
- **Mocks and fixtures** for isolated testing
- **Code coverage reporting** with detailed metrics

## 📁 Test Structure

```
tests/
├── __init__.py
├── conftest.py                 # Shared fixtures and configuration
├── README.md                   # This file
├── unit/                       # Unit tests
│   ├── __init__.py
│   ├── test_auth_service.py   # Authentication service tests
│   ├── test_query_service.py  # Query service tests
│   ├── test_llm_service.py    # LLM service tests
│   └── test_health_check.py   # Health check tests
├── integration/                # Integration tests
│   ├── __init__.py
│   └── test_end_to_end.py     # End-to-end workflow tests
└── fixtures/                   # Test data and mocks
    └── __init__.py
```

## 🚀 Installation

### 1. Install Test Dependencies

```bash
# From the project root
cd chatbot
pip install -r requirements.txt
```

### 2. Verify Installation

```bash
pytest --version
```

## 🧪 Running Tests

### Run All Tests

```bash
# From the chatbot directory
pytest

# With verbose output
pytest -v

# With detailed output
pytest -vv
```

### Run Specific Test Categories

```bash
# Run only unit tests
pytest -m unit

# Run only integration tests
pytest -m integration

# Run only auth-related tests
pytest -m auth

# Run only LLM tests
pytest -m llm
```

### Run Specific Test Files

```bash
# Run auth service tests
pytest tests/unit/test_auth_service.py

# Run query service tests
pytest tests/unit/test_query_service.py

# Run integration tests
pytest tests/integration/
```

### Run Specific Test Classes or Functions

```bash
# Run a specific test class
pytest tests/unit/test_auth_service.py::TestAuthServiceConfiguration

# Run a specific test function
pytest tests/unit/test_auth_service.py::TestAuthServiceConfiguration::test_missing_username_raises_error
```

### Run Tests with Coverage

```bash
# Generate coverage report
pytest --cov=chatbot --cov-report=html

# View coverage in terminal
pytest --cov=chatbot --cov-report=term-missing

# Generate XML report for CI
pytest --cov=chatbot --cov-report=xml
```

### Run Tests in Parallel

```bash
# Install pytest-xdist
pip install pytest-xdist

# Run tests in parallel (4 workers)
pytest -n 4
```

## 📊 Test Coverage

### View Coverage Report

After running tests with coverage:

```bash
# Open HTML report in browser
open htmlcov/index.html  # macOS
xdg-open htmlcov/index.html  # Linux
start htmlcov/index.html  # Windows
```

### Coverage Goals

- **Overall Coverage**: > 80%
- **Critical Services**: > 90%
  - AuthService
  - QueryService
  - LLMService
- **Utilities**: > 85%

### Current Coverage

Run `pytest --cov=chatbot --cov-report=term` to see current coverage statistics.

## ✍️ Writing Tests

### Test File Naming

- Unit tests: `test_<module_name>.py`
- Integration tests: `test_<feature>_integration.py`
- Place in appropriate directory (`unit/` or `integration/`)

### Test Function Naming

```python
def test_<what_is_being_tested>_<expected_behavior>():
    """TC-XXX-NNN: Brief description of test case"""
    # Arrange
    # Act
    # Assert
```

### Example Unit Test

```python
import pytest
from unittest.mock import Mock, patch

@pytest.mark.unit
@pytest.mark.auth
def test_authentication_succeeds_with_valid_credentials(sample_config, mock_logger):
    """TC-AUTH-008: Verify successful authentication with valid credentials"""
    # Arrange
    with patch('subprocess.run') as mock_run:
        mock_run.return_value = Mock(returncode=0, stdout='token')
        auth_service = AuthService(sample_config, mock_logger)
        
        # Act
        result = auth_service.authenticate()
        
        # Assert
        assert result is True
        assert auth_service.token is not None
```

### Using Fixtures

```python
def test_with_fixtures(sample_config, mock_logger, mock_cache_service):
    """Test using multiple fixtures"""
    # Fixtures are automatically injected
    service = MyService(sample_config, mock_logger, mock_cache_service)
    assert service is not None
```

### Mocking External Dependencies

```python
@patch('chatbot.services.query_service.requests.post')
def test_api_call(mock_post, sample_config, mock_logger):
    """Test with mocked HTTP request"""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {'success': True}
    mock_post.return_value = mock_response
    
    # Test code here
```

## 🏷️ Test Markers

Tests are organized using pytest markers:

### Available Markers

- `@pytest.mark.unit` - Unit tests
- `@pytest.mark.integration` - Integration tests
- `@pytest.mark.slow` - Slow-running tests
- `@pytest.mark.auth` - Authentication tests
- `@pytest.mark.query` - Query service tests
- `@pytest.mark.llm` - LLM service tests
- `@pytest.mark.vector_store` - Vector store tests
- `@pytest.mark.health` - Health check tests
- `@pytest.mark.cli` - CLI interface tests
- `@pytest.mark.requires_oc` - Tests requiring oc CLI
- `@pytest.mark.requires_network` - Tests requiring network

### Using Markers

```python
@pytest.mark.unit
@pytest.mark.auth
def test_authentication():
    """Test marked as unit test and auth-related"""
    pass

@pytest.mark.integration
@pytest.mark.slow
def test_end_to_end_workflow():
    """Test marked as integration and slow"""
    pass
```

### Running Tests by Marker

```bash
# Run only unit tests
pytest -m unit

# Run only slow tests
pytest -m slow

# Run tests NOT marked as slow
pytest -m "not slow"

# Run auth OR query tests
pytest -m "auth or query"

# Run integration tests that don't require network
pytest -m "integration and not requires_network"
```

## 🔄 Continuous Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.9'
    
    - name: Install dependencies
      run: |
        cd chatbot
        pip install -r requirements.txt
    
    - name: Run tests with coverage
      run: |
        cd chatbot
        pytest --cov=chatbot --cov-report=xml --cov-report=term
    
    - name: Upload coverage
      uses: codecov/codecov-action@v2
      with:
        file: ./chatbot/coverage.xml
```

## 🐛 Debugging Tests

### Run Tests with Debug Output

```bash
# Show print statements
pytest -s

# Show local variables on failure
pytest -l

# Drop into debugger on failure
pytest --pdb

# Drop into debugger at start of test
pytest --trace
```

### Debug Specific Test

```python
def test_something():
    import pdb; pdb.set_trace()  # Breakpoint
    # Test code
```

## 📝 Best Practices

### 1. Test Independence

- Each test should be independent
- Don't rely on test execution order
- Clean up resources in teardown

### 2. Use Fixtures

- Reuse common setup with fixtures
- Keep fixtures focused and simple
- Use fixture scope appropriately

### 3. Mock External Dependencies

- Mock API calls, file I/O, subprocess calls
- Don't make real network requests in unit tests
- Use integration tests for real interactions

### 4. Descriptive Test Names

- Name tests clearly: `test_<action>_<expected_result>`
- Include test case ID in docstring
- Explain what is being tested

### 5. Arrange-Act-Assert Pattern

```python
def test_example():
    # Arrange - Set up test data
    service = MyService()
    
    # Act - Execute the code being tested
    result = service.do_something()
    
    # Assert - Verify the result
    assert result == expected_value
```

### 6. Test Edge Cases

- Test normal cases
- Test boundary conditions
- Test error conditions
- Test invalid inputs

## 🔍 Troubleshooting

### Common Issues

#### Import Errors

```bash
# Ensure you're in the correct directory
cd chatbot

# Install in development mode
pip install -e .
```

#### Fixture Not Found

```bash
# Check conftest.py is in the right location
# Ensure fixture name matches function parameter
```

#### Tests Not Discovered

```bash
# Check file naming (must start with test_)
# Check function naming (must start with test_)
# Verify pytest.ini configuration
```

### Getting Help

1. Check test output for detailed error messages
2. Run with `-vv` for maximum verbosity
3. Use `--lf` to run only last failed tests
4. Use `--tb=short` for shorter tracebacks

## 📚 Additional Resources

- [Pytest Documentation](https://docs.pytest.org/)
- [Pytest Best Practices](https://docs.pytest.org/en/stable/goodpractices.html)
- [Python Testing with pytest (Book)](https://pragprog.com/titles/bopytest/python-testing-with-pytest/)
- [Real Python - Testing](https://realpython.com/pytest-python-testing/)

## 🤝 Contributing

When adding new tests:

1. Follow existing test structure and naming conventions
2. Add appropriate markers
3. Include test case ID in docstring
4. Update this README if adding new test categories
5. Ensure tests pass before committing
6. Maintain or improve code coverage

## 📞 Support

For questions or issues with tests:
- Check this README first
- Review existing tests for examples
- Consult pytest documentation
- Ask the development team

---

**Happy Testing! 🧪**