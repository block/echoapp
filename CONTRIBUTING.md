# Contributing to EchoApp

Welcome, and thank you for your interest in contributing to EchoApp! This guide follows
[Block's general contribution guidelines](https://github.com/block/.github/blob/main/CONTRIBUTING.md);
the project-specific details below add to them.

## Getting Started

Whether you're fixing a typo, improving documentation, or adding a new feature, every contribution matters.

1. **Fork the Repository**
   * Great instructions for cloning to your personal fork and using that for branches are provided by GitHub [here](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo).
2. **Create a Branch**
   * Create a branch for your work: `git checkout -b feature/your-feature-name`
   * Use descriptive branch names that reflect the changes you're making
3. **Set Up Development Environment**
   * Follow the setup instructions in [README.md](./README.md)
   * Build and test with Swift Package Manager: `xcrun swift build` and `xcrun swift test`

## Making Changes

1. **Discuss Your Plans:** Join the [Block open source Discord community](https://discord.gg/block-opensource) or use the issue tracker to discuss your proposed changes with project maintainers. For substantial changes:
   1. Open an issue describing your proposed changes before starting work
   2. Wait for maintainer feedback and discussion
   3. Get alignment on the implementation approach
   4. Break down large changes into smaller, manageable pull requests
2. **Write Good Code**
   * Follow the project's coding style and conventions
   * Keep functions and methods focused and concise
   * Write or update tests as needed
3. **Commit Guidelines**
   * Make focused, atomic commits that address a single concern
   * Follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format: `type(scope): description`
   * Common types include: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
   * EchoApp is licensed under [Apache-2.0](./LICENSE) and requires a [Developer Certificate of Origin](https://en.wikipedia.org/wiki/Developer_Certificate_of_Origin) sign-off on all commits. This is a statement indicating that you are allowed to make the contribution and that the project has the right to distribute it under its license. When you are ready to commit, use the `--signoff` flag: `git commit --signoff ...`

## Submitting Changes

1. **Before Submitting**
   * Run all tests and ensure they pass
   * Check code formatting and linting
   * Rebase your branch on the latest upstream `main`
2. **Creating a Pull Request**
   * Push your changes to your fork and create a pull request from your branch
   * Link to any related issues and provide a clear description of your changes
   * Keep PRs focused and reasonable in size - generally as small as possible to fulfill one atomic feature, task, or bug fix
   * Include screenshots or examples for UI changes, and list any breaking changes

## Review Process

* All submissions require review; be open to feedback and suggestions
* Ensure all CI checks pass, and fix any failing tests or lint issues
* Respond to review feedback promptly

## Security

* Never commit sensitive information
* Report security vulnerabilities privately - see [SECURITY.md](./SECURITY.md)
* Use dependencies with no known security vulnerabilities

## License

By contributing to EchoApp, you agree that your contributions will be licensed under the
[Apache License 2.0](./LICENSE). Make sure you understand and agree to the license terms before contributing.

## Code of Conduct

By participating in our community, you agree to abide by our [Code of Conduct](./CODE_OF_CONDUCT.md).
We are committed to providing a welcoming and inclusive environment for all contributors, regardless of
background or experience level. The Code of Conduct is maintained and upheld by the
[Block Open Source Governance Committee](./GOVERNANCE.md).

## Questions?

If you have questions about contributing that aren't covered here, open a discussion in the repository
or reach out to the project maintainers. Thank you for contributing to EchoApp!
