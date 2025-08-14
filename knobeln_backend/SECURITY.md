# Security Policy

## Supported Versions

This section lists the versions of the Knobeln Game Backend that are currently being supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security issues seriously and appreciate your efforts to responsibly disclose your findings. Please help us ensure the security and privacy of our users by following these guidelines.

### How to Report a Vulnerability

If you believe you've found a security vulnerability in the Knobeln Game Backend, please report it to us as soon as possible by emailing [security@example.com](mailto:security@example.com). Please do not report security vulnerabilities through public GitHub issues.

In your report, please include the following information:

- A description of the vulnerability
- Steps to reproduce the issue
- The potential impact of the vulnerability
- Any mitigations or workarounds you're aware of
- Your name and affiliation (if any) for credit

### Our Commitment

- We will acknowledge receipt of your report within 3 business days
- We will confirm the vulnerability and determine its impact
- We will keep you informed of the progress towards resolving the issue
- We will notify you when the vulnerability has been fixed
- We will publicly acknowledge your responsible disclosure (unless you prefer to remain anonymous)

### Bug Bounty

At this time, we do not offer a paid bug bounty program. However, we are happy to publicly acknowledge your contribution if you wish.

## Security Best Practices

### For Users

- Always keep your AWS credentials secure and never commit them to version control
- Use IAM roles and policies to follow the principle of least privilege
- Regularly rotate your AWS access keys and credentials
- Enable MFA for all AWS accounts
- Monitor your AWS resources using CloudWatch and set up appropriate alerts

### For Developers

- Always validate and sanitize user inputs
- Use parameterized queries to prevent SQL injection
- Implement proper authentication and authorization checks
- Keep all dependencies up to date
- Follow the principle of least privilege for IAM roles and policies
- Encrypt sensitive data at rest and in transit
- Implement proper logging and monitoring

## Security Updates

Security updates will be released as patch versions (e.g., 1.0.0 → 1.0.1). We recommend always running the latest version of the software to ensure you have all security fixes.

## Security Advisories

Security advisories will be published in the [GitHub Security Advisories](https://github.com/your-org/knobeln-backend/security/advisories) section of the repository.

## Contact

For security-related inquiries, please contact [security@example.com](mailto:security@example.com).
