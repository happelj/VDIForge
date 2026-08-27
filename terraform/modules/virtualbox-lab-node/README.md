# VirtualBox Lab Node Module

This module records and validates the expected VirtualBox VM specification for one VDIForge lab node.

It intentionally does not use a third-party VirtualBox Terraform provider. The older `terra-farm/virtualbox` provider is alpha and currently signals a maintainer gap, so Phase 2 avoids making it authoritative for VM lifecycle. The actual VM lifecycle for this host is VirtualBox GUI or `VBoxManage`; Terraform remains the reviewed infrastructure specification and output source.
