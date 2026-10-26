# Windows application routing

Application routing uses Hiddify's existing sing-box TUN mode. It is disabled by
default, preserving the existing routing configuration. Configure it under
**Settings → Routing → Application routing** on Windows. Settings may be edited
outside VPN mode, but take effect only in TUN/VPN mode.

Choose one of two modes:

| Mode | Matching applications | Other TUN traffic |
| --- | --- | --- |
| Exclude selected applications | Direct outbound | Existing routing rules and default outbound |
| Use VPN only for selected applications | Main proxy outbound | Direct outbound |

Add an executable by choosing a file, choosing a running application, or entering
one full path per line. The running-app picker only obtains the executable path;
it does not store a process ID or require the application to remain running.
Inaccessible processes are omitted. File selection remains available.

Process names are also supported, one per line. A name applies to that executable
name in every directory. A full path limits the match to that location. Names
and paths are combined with **OR**, compared without case sensitivity, and do
not accept wildcards. The UI accepts absolute drive and UNC paths to `.exe`
files. A selected file need not currently exist. Moving or updating an
application into a different directory requires updating its saved path.

Press **Save** to apply the complete draft. Turning the feature off retains the
list. Settings are stored separately from subscriptions; refreshing or replacing
a subscription cannot replace the local policy. Changes while connected use the
client's existing configuration-change/reconnect handling.

## DNS and limits

This feature routes connections whose socket owner sing-box can identify. It
does not provide a strict isolation or leak-prevention guarantee.

- A DNS request received through TUN and attributed to a selected application
  follows that application's mode. Unselected applications with an identified
  executable use direct DNS in inclusion mode.
- With `strict_route`, Windows blocks port 53 traffic through interfaces other
  than TUN. An application that explicitly queries a resolver on its physical
  interface can therefore time out before these application rules apply.
  Selecting that application for direct routing does not bypass this filter.
  See the [sing-box TUN DNS behavior](https://sing-box.sagernet.org/configuration/inbound/tun/#dns_mode).
- Shared Windows resolver traffic and DNS without a trustworthy application
  identity use the VPN DNS group in both modes. This is an explicit exception
  to “VPN only for selected applications.” Selecting `svchost.exe` does not
  change that shared-DNS policy.
- FakeIP is disabled in the effective configuration while this feature is on,
  including with an empty list. Stored FakeIP preferences are not changed.
  The pinned DNS implementation separates cache entries by DNS transport tag;
  the compatibility `independent_cache` flag is also set.
- Applications using their own DoH/DoT connections are routed as ordinary
  connections when their owner is identified. The rules do not identify encrypted
  DNS contents or attribute work delegated to another service.
- Child executables and helper services need their own entries. A saved path
  identifies a location, not a signature or file hash.
- If owner lookup fails or identifies a different process, the selected rule may
  not match. Exclusion mode then follows existing routes; inclusion mode uses
  the direct catchall. TCP, UDP, IPv4 and IPv6 rules have no added protocol or
  address-family restriction, but this is not proof of successful runtime
  attribution for every connection.
- Existing connections do not change routes just because a rule is edited.
  Reconnect the VPN and restart the application's connections when validating
  changes in an isolated test environment.
- “Direct” bypasses Hiddify's remote proxy. Windows still chooses the outbound
  interface; another active VPN or system policy may affect that choice.

An empty exclusion list keeps ordinary routing. An empty inclusion list sends
ordinary TUN traffic directly, with the DNS exceptions above. Non-TUN inbounds
keep their existing behavior. Active application routing requires generated
configuration; raw-config startup is rejected by the core rather than silently
ignoring the policy.

## Implementation

### Portable Windows builds

The existing Windows Portable build uses the Dart define `portable=true`.
Extract the complete ZIP into a writable directory and run `Hiddify.exe` from
that directory. Keep the executable, DLLs and `data` directory together.

Profiles and the database use `hiddify_portable_data` beside the executable when
that directory is writable; otherwise the existing implementation falls back to
the application-support directory. Shared preferences, including application
routing settings, still use `%APPDATA%\Hiddify\hiddify\shared_preferences.json`
with the separate `portable.` key prefix. Multiple Portable copies therefore
share these preferences. This mode does not keep every setting beside the EXE.
It does not import the regular installation's `flutter.` preferences.

Portable packaging does not remove the privileges required for TUN or make the
Windows service portable. A service installed from this directory refers to its
executable path. Do not move or delete that directory while its service is in use.

### Configuration integration

The local `windows_app_routing` preference is a single serialized value. The
settings repository exports it as `windows-app-routing` in the existing core
options and reapplies it after profile overrides. Active local policy also
protects the chosen TUN setting and disables execute-config-as-is.

The core validates selectors, escapes them into one `process_path_regex` list,
and places application routes after sniffing and DNS hijacking, before special
destination and user rules. All new rules are limited to the TUN inbound.
Inactive policy adds no new rules and does not change DNS options.

- [Local model and validation](../lib/features/app_based_routing/model/windows_app_routing.dart)
- [Preference storage](../lib/features/app_based_routing/data/windows_app_routing_preferences.dart)
- [Options and profile merge](../lib/features/settings/data/config_option_repository.dart)
- [Core policy and configuration contract](../hiddify-core/v2/config/windows_app_routing.md)
- [sing-box route rule reference](https://sing-box.sagernet.org/configuration/route/rule/)
- [Windows process image path API](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew)

## Safe automated checks

Audit imports and initialization before running tests on a machine with active
VPNs. Do not start the app, native core, smoke tests, services or TUN adapters.
The following focused tests use in-memory preferences, fake process/file
providers and generated configuration data:

```powershell
flutter test test/features/app_based_routing/windows_app_routing_test.dart test/features/app_based_routing/windows_app_routing_config_test.dart test/features/app_based_routing/windows_app_routing_section_test.dart test/features/app_based_routing/windows_process_source_test.dart
Push-Location hiddify-core/v2/config
go test -count=1 -v windows_app_routing.go dns_options.go constant.go windows_app_routing_test.go
Pop-Location
```

The named Go source-file list intentionally excludes the full core package and
its initialization paths. These tests verify storage, UI behavior, profile
override protection, validation, rule construction and JSON. They do not verify
live Windows routing. Full `BuildConfig` integration and the raw startup guard
also require separate qualification beyond these unit tests.

Build the modified core together with the app. An older downloaded core does
not implement this option. Review build recipes before use: the current core
`windows-amd64` Makefile target contains `go run ./cli tunnel exit`. On a live
VPN host use explicit compile-only commands, then package into a separate
directory. Do not use that target, launch the output, install a service, or
replace an installed client as part of a build check.

## Isolated Windows VM qualification plan

Use a disposable Windows VM snapshot, synthetic subscriptions, a controlled
proxy and DNS endpoints, and test applications with known executable paths.
Keep capture and resolver logs inside the test environment. Do not import
production profiles or credentials. Runtime qualification needs explicit
authorization and must not run on the development host.

1. Record the app, core, Windows and sing-box versions and artifact hashes.
   Capture baseline routes, adapters, resolver settings and DNS/proxy logs in
   the VM. Validate feature-off behavior against the unmodified client.
2. Exercise exclusion and inclusion with an empty list, one name, one path,
   combined selectors, case changes, spaces, Unicode and duplicate inputs.
   Distinguish same-name executables in different directories. Test a selected
   file started after configuration, process exit during enumeration and
   inaccessible processes.
3. For each mode, originate TCP and UDP traffic to IPv4 and IPv6 endpoints from
   selected and unselected executables. Confirm the observed egress and proxy
   logs, not just the generated JSON or client status icon. Include QUIC and
   concurrent UDP endpoints with ambiguous owner lookup.
4. Validate app-owned DNS, the shared Windows resolver, failed owner lookup,
   cached answers, A/AAAA, DoH/DoT and resolver failures. Confirm the shared/unknown
   VPN exception in inclusion mode. Alternate direct and remote lookups for
   the same domain and confirm transport-separated caching and no FakeIP answers.
5. Test child executables and brokered/shared services. Confirm that explicit
   additional paths are required and document attribution failures without
   presenting them as a strict guarantee.
6. Save, restart the client, refresh/replace a synthetic subscription, attempt
   conflicting profile overrides and raw-config startup. Check that local
   selectors survive, raw mode cannot silently bypass them, and disabling the
   feature restores stored DNS preferences and ordinary routing.
7. Exercise VPN reconnect, existing TCP/UDP sessions, direct failure, proxy
   failure and network changes. Confirm that a failed direct dial is not
   silently retried through the proxy. Test another VPN only inside a dedicated
   nested scenario; record which Windows route actually wins.
8. Verify permissions, process-handle cleanup, file-picker cancellation, narrow
   windows, keyboard access, screen-reader labels and supported translations.
   Compare final VM routes and DNS state with the baseline after normal shutdown.

Record each scenario as passed, failed or untested, with captures and versions.
Unit-test success and a successful build are prerequisites, not substitutes for
these runtime observations.
