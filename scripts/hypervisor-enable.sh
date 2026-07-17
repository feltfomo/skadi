# Unload the AMD KVM stack, load the CPUID-faulting module. For legacy Proton
# titles that trip on hypervisor/UMIP checks.
# No shebang: embedded via writeShellApplication (see cpuid-hypervisor.nix).
sudo modprobe -r kvm_amd kvm
sudo modprobe cpuid_fault_emulation