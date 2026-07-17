# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in StrataSolidity, please report it
responsibly by emailing the maintainers directly rather than opening a public
issue.

**Contact:** Open a private security advisory via GitHub's
[Security Advisories](https://github.com/strata-org/strata-solidity/security/advisories/new)
feature, or email the repository owner listed in the commit history.

## Scope

StrataSolidity is a *verification tool* — it analyzes Solidity contracts but
does not deploy, hold, or transfer any assets. Security concerns relevant to
this project include:

- Soundness bugs where the tool reports a property as verified when it is not
  (false negatives — a verified contract that actually has a bug).
- Vulnerabilities in the build or CI pipeline that could lead to supply-chain
  compromise of published artifacts.

## Response

We aim to acknowledge reports within 72 hours and provide a fix or mitigation
plan within 30 days for confirmed issues.
