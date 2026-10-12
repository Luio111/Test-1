# 0001 – Projektstruktur: XcodeGen + lokales Swift-Package

**Kontext.** Der Code entsteht teilweise in einer Linux-Umgebung ohne Xcode. Eine handgeschriebene `project.pbxproj` ist fehleranfällig und erzeugt unlesbare Diffs.

**Entscheidung.**
- Das Xcode-Projekt wird aus `project.yml` per XcodeGen erzeugt und nie eingecheckt.
- Build-Einstellungen stehen in `Config/*.xcconfig`; persönliche Werte (Team, Bundle-ID-Präfix) in der lokalen `Signing.local.xcconfig`.
- Logik liegt im Swift-Package `CopyPalKit` (Core, Storage, System, Services). Das App-Target bleibt dünn.
- macOS-spezifische Quellen sind in `#if os(macOS)` gekapselt, damit `swift build`/`swift test` auch unter Linux laufen.

**Folgen.**
- Die CI kann die plattformneutralen Teile günstig unter Linux testen; der macOS-Job baut die App.
- Nach jedem `git pull` muss `./scripts/bootstrap.sh` laufen.
- Unter Linux sind die macOS-Adapter leer – ihre Tests laufen nur auf macOS.
