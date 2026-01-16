# Contributing

We welcome contributions to Quo.

## Development Setup

### Prerequisites

- Crystal 1.10+
- SQLite3 development libraries
- PostgreSQL (optional, for integration tests)

### Clone and Install

```bash
git clone https://github.com/alex-lairan/Quo.git
cd Quo
shards install
```

### Running Tests

```bash
# All tests
crystal spec

# Unit tests only
crystal spec spec/unit/

# Specific file
crystal spec spec/unit/query_spec.cr
```

## Code Style

- Follow Crystal standard style
- Run formatter before committing:

```bash
crystal tool format
```

- Add tests for new features
- Keep methods focused and small
- Use meaningful names

## Project Structure

```
quo/
├── src/
│   └── quo/
│       ├── adapters/       # Database adapters
│       ├── schema/         # Schema components
│       ├── expression.cr   # Expression types
│       ├── query.cr        # Query builder
│       └── relation.cr     # Relation base class
├── spec/
│   ├── unit/               # Unit tests
│   └── spec_helper.cr
├── examples/               # Example files
└── docs/                   # Documentation
```

## Adding Features

### 1. Write Tests First

```crystal
# spec/unit/my_feature_spec.cr
describe "My Feature" do
  it "does something" do
    # Test code
  end
end
```

### 2. Implement Feature

### 3. Update Documentation

- Add to appropriate guide page
- Update API reference if needed
- Add examples

### 4. Submit PR

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Write tests
4. Implement feature
5. Ensure all tests pass: `crystal spec`
6. Format code: `crystal tool format`
7. Commit with clear message
8. Push to your fork
9. Open Pull Request

### Commit Messages

Use clear, descriptive commit messages:

```
Add ILIKE support for SQLite adapter

- Convert ILIKE to LOWER() LIKE LOWER()
- Add tests for case-insensitive matching
- Update adapter documentation
```

## Reporting Issues

When reporting issues, include:

- Crystal version: `crystal version`
- Quo version
- Database and version
- Minimal reproduction code
- Expected vs actual behavior
- Error messages (full stack trace)

## Feature Requests

Open an issue with:

- Clear description of the feature
- Use case / motivation
- Proposed API (if applicable)
- Willingness to implement

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn

## Questions?

Open an issue or discussion for questions about:

- Implementation approaches
- API design decisions
- Testing strategies
