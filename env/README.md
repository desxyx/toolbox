# Dev Environment Audit Tool

Simple Windows batch script to scan and record the full development environment.

This tool generates a detailed report of:

- System information (OS, CPU, RAM)
- PATH entries (including duplicates)
- Installed package managers (winget, choco, scoop)
- Programming languages (Python, Java, Node, .NET, Go, Rust, Ruby)
- DevOps tools (Terraform, AWS CLI, Docker, Kubernetes, Helm)
- Git / SSH / GPG
- Database clients
- Installed programs (registry dump)
- Visual C++ runtimes and Windows SDKs

