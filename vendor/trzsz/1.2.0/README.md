# trzsz-go v1.2.0

Official upstream: https://github.com/trzsz/trzsz-go
Tag commit: b1eaca3c8a2777cdfcf575964ef34a633c0f0710

Unmodified macOS arm64 release binaries from:
https://github.com/trzsz/trzsz-go/releases/download/v1.2.0/trzsz_1.2.0_macos_aarch64.tar.gz

Archive SHA-256 (verified against upstream release checksums):
`b6f290e2b6f4d70783797d2fd96eabef9ec789eee402f05e7aa20253cb09b592`

SHA256SUMS.txt records the extracted binaries. The build bundles only `trzsz`,
then applies the app's ad-hoc signature to that copy. `trz` and `tsz` are local
integration-test fixtures; remote servers install their own compatible tools.
The client invokes `trzsz --dragfile /usr/bin/ssh ...` with literal argv, keeping
OpenSSH authentication, proxies, jumps and forwarding. ZMODEM filtering in
trzsz is disabled so MyTerm's existing bridge continues to receive its stream.

MIT license: LICENSE. Dependency and Go runtime notices: THIRD-PARTY-NOTICES.txt.
No runtime download or automatic executable update is performed.
