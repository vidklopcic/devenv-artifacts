# devenv-device releases

Builds of devenv-device, the program that links a computer to a devenv host. Each build and `release.json` are
signed with the release key (`ssh-keygen -Y verify -n devenv-device`); devices take nothing else. Release 12.

Install: the command a devenv host shows in Resources → Devices (`install.sh` on Linux and macOS,
`install.ps1` in an administrator's PowerShell on Windows).
