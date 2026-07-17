# hypervisor <enable|disable|status>: swap between the CPUID-faulting module and
# the AMD KVM stack. For legacy Proton titles that trip on hypervisor/UMIP checks.
# No shebang: embedded via writeShellApplication (see cpuid-hypervisor.nix).
case "${1:-}" in
  enable)
    sudo modprobe -r kvm_amd kvm
    sudo modprobe cpuid_fault_emulation
    ;;
  disable)
    sudo modprobe -r cpuid_fault_emulation
    sudo modprobe kvm_amd kvm
    ;;
  status)
    if [ -d /sys/module/cpuid_fault_emulation ]; then
      echo "hypervisor: ENABLED (cpuid module loaded, kvm unloaded)"
    else
      echo "hypervisor: disabled (kvm loaded)"
    fi
    ;;
  *)
    echo "usage: hypervisor <enable|disable|status>" >&2
    exit 1
    ;;
esac