# Usage: sops-edit [path/to/secrets.yaml]
# Defaults to secrets/secrets.yaml if no path is given.

def main [file: string = "secrets/secrets.yaml"] {
    let key_file = (mktemp)

    # Derive a plain age key from the persisted SSH host key.
    # This step genuinely should fail loudly if it breaks.
    nix shell nixpkgs#ssh-to-age -c bash -c $"sudo cat /persist/etc/ssh/ssh_host_ed25519_key | ssh-to-age -private-key -o '($key_file)'"
    sudo chmod 644 $key_file

    # Open the file for editing with sops. sops exits non-zero for benign
    # reasons too (e.g. "File has not changed, exiting." if you close
    # without editing), so don't treat that as a script failure -- just
    # make sure the derived key is always cleaned up afterward.
    nix shell nixpkgs#sops -c bash -c $"SOPS_AGE_KEY_FILE='($key_file)' sops \"($file)\""

    rm -f $key_file
}
