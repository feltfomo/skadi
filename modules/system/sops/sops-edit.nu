# usage is sops-edit [path/to/host.yaml]

def main [file?: string] {
    let target = if $file == null {
        let host = (hostname | str trim)
        $"secrets/($host).yaml"
    } else {
        $file
    }
    let key_file = (mktemp)

    # derive an age key from the persisted ssh host key
    nix shell nixpkgs#ssh-to-age -c bash -c $"sudo cat /persist/etc/ssh/ssh_host_ed25519_key | ssh-to-age -private-key -o '($key_file)'"
    sudo chmod 644 $key_file

    # sops returns nonzero when the editor closes without a change
    nix shell nixpkgs#sops -c bash -c $"SOPS_AGE_KEY_FILE='($key_file)' sops \"($target)\""

    rm -f $key_file
}
