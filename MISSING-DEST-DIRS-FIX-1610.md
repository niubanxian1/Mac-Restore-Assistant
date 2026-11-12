# Missing Helper destination directories fix — RC 20261112.1610

Confirmed macOS 26 failure:

```text
install: /Library/PrivilegedHelperTools/INS@...: No such file or directory
```

The installer assumed `/Library/PrivilegedHelperTools` and
`/Library/LaunchDaemons` already existed. On a fresh macOS 26 installation one
or both can be absent; `install` then cannot create its temporary file.

## Fix

- Before snapshot, bootout or copy, create the Helper/backend parent and launchd
  plist parent.
- System parents are created with owner `root:wheel`, mode `0755`.
- A parent that is a symbolic link is rejected.
- Isolated test destinations are created only inside their scratch root.
- No device path, payload hash, launchd label, Helper protocol or command logic
  changed.

## Verification

- New isolated regression starts with all destination parents absent.
- Current fix reports `DESTINATION_DIRECTORIES_READY=YES`.
- Full Swift suite exits 0; 200 passed, 1 skipped.
- No real system directory was created while testing.
