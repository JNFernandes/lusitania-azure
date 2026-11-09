"""
Read a secret from Key Vault WITHOUT any password in the code or in a file.

    pip install -r requirements.txt            (once, in Project 2's venv)
    python scripts\\read_secret.py demo-greeting

DefaultAzureCredential tries the available logins in order: environment variables, a MANAGED
IDENTITY (when this runs in Azure), your `az login` (on the laptop), ... and uses the first one
that works. So this same file runs unchanged on your laptop and inside Azure.
"""
import sys

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

VAULT_URL = "https://kv-lusitania-dev-jf01.vault.azure.net/"


def main() -> None:
    name = sys.argv[1] if len(sys.argv) > 1 else "demo-greeting"
    client = SecretClient(vault_url=VAULT_URL, credential=DefaultAzureCredential())
    secret = client.get_secret(name)
    print(f"secret '{secret.name}' (version {secret.properties.version[:8]}…): {secret.value}")


if __name__ == "__main__":
    main()
