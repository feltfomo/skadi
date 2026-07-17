# Reverse of hypervisor-enable: unload the module, bring the AMD KVM stack back.
# No shebang: embedded via writeShellApplication (see cpuid-hypervisor.nix).
sudo modprobe -r cpuid_fault_emulation
sudo modprobe kvm_amd kvm