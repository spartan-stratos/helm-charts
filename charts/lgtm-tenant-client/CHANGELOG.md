# Changelog

All notable changes to this project will be documented in this file.

## 0.1.2 (2026-11-26)

### Features

- Add optional `javaImage` to pin the Java auto-instrumentation agent in the Instrumentation. Defaults to the platform's pinned version; set it to an empty string to use the operator default.

## 0.1.1 (2026-11-23)

### Documentation

- Align the receiver example with the stack README and add IAM trust, cross-account, force-sync and Instrumentation annotation guidance.

## 0.1.0 (2026-11-23)

### Features

* Add a platform-owned shared tenant telemetry client with a ServiceAccount, SecretStore, ExternalSecret and OpenTelemetry Instrumentation.
