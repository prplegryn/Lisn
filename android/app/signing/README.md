# Lisn development release signing

`lisn-dev-release.p12` is a committed development/internal release keystore.

It exists so GitHub Actions release APKs are always signed with the same
certificate and can be installed over older Lisn builds without uninstalling.

This key is not a production or Play Store signing key.
