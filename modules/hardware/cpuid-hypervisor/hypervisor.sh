# hypervisor <enable|disable|status> swaps between the cpuid-faulting module and
# the amd kvm stack for legacy proton titles that trip on hypervisor or umip checks.
# writeShellApplication supplies the shebang and runtime path.
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