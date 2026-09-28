# Configlue Research Notes (context for writing the README)

The following is a summary of research on the .NET library **Configlue**. Use this as the only source of information when writing the Japanese explanation for the README.

## 1. What this is

- Configlue is a **.NET library** that takes over configuration management for your application.
- Tagline: "Make easy configuration management."
- Its central idea is to **glue** configuration scattered across multiple locations into a single model. The name comes from configuration + glue.
- Requirements: .NET 10 SDK or later. C# (`LangVersion` must support source generators; the repository builds with `preview`).
- License: Apache-2.0.
- It is currently an "architectural foundation" and is not a complete replacement for `Configuration.Writable`.

## 2. Problems it solves (Why Configlue?)

Reading and writing a JSON file takes only a few lines. In practice, however, requirements pile up like this:

- Configuration lives in multiple places: global config, per-runtime-folder config, environment variables, command-line arguments, encrypted credentials, and remote management such as corporate policies or HTTP APIs.
- When a configuration file is rewritten, you want it reflected without restarting the app (change notifications).
- You want to choose the write destination automatically. Writes to values read from environment variables should raise an error.
- Configuration files are written by humans: don't remove comments, want JSON Schema support, handle broken files.
- If a value is still at its default, don't write it out (but respect a `null` the user explicitly set).
- Version up configuration files (automatic conversion from the old format to the new one).
- Backups and automatic cleanup.
- Write safety: atomicity (no corruption on crash), conflict detection and auto-merge with other processes, automatic retry.

The motivation is that implementing all of this yourself is tedious.

## 3. Core architecture (six concepts)

The dependencies form a straight line, and the learning order is the same:

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| Concept | In one phrase | Example |
| --- | --- | --- |
| Resource | Where the bytes live | File, ZIP entry, HTTP response, memory |
| Codec | Conversion between bytes and values | Reading/writing JSON / XML / YAML |
| Source | A logical contribution (which fields at which priority) | "The `Server` part of the user settings file" |
| Fragment | A diff that remembers presence | A state that has "only `Port`" |
| Patch | An edit of a single field | "Set `Port` to 9000" |
| Options | The facade the app sees | Read, save, watch, explain, diagnose |

**Reads**: each Source fetches bytes from a Resource, and a Codec converts them into a Fragment. The runtime overlays only the fields that are "present", in priority order, into a single model.

**Writes**: the reverse direction. The app edits an ordinary model value. Internally the change becomes a Fragment diff and reaches only the Source named by `WriteRoute` / `WritePlan`. Unrelated Sources are not modified.

- Fragment distinguishes "member is missing" from "present as null/default". Layer composition never lets "unset" overwrite "set to default".
- Patch is the generated `TModel.Patch` (a single-field edit fragment). `Unset()` withdraws only the write destination Source's contribution and exposes lower-priority values again.
- `[ConfiglueMerge]` changes per-member merge behavior (built-in: `Append`, `Deep`, `Replace`, `SetUnion`; custom strategies allowed). Collection layer composition and ordering are decided here.

## 4. Main features

- **Priority merge across multiple sources**: the Source with the larger `Priority` wins. `GetDetailsAsync` lets you inspect "which value came from where".
- **Read-only sources**: environment variables, command line, and the default HTTP source are read-only. Writing to a read-only value does not silently ignore the write; it raises a conflict error.
- **Projection / mounting**: you can reshape an existing Source into another model (projection), or attach a separate Source at a nested path (mount, `AddMounted`).
- **Presets**: `UseCommonSources` assembles a standard layer composition (global/local/environment, etc.).
- **Sparse writes**: only the fields you changed are saved to the target layer. Fields left at their defaults are not written.
- **Edit sessions**: `OpenEditSessionAsync` applies several changes together. They are in-memory until `CommitAsync`. On conflict it fails by default; `WriteConflictResolution.LastWriteWins` is also available.
- **Schema migration / storage migration**: automatic conversion of old-version configuration via `[ConfigluePreviousVersion]` and `Fragment.FromPrevious`. Existing files can be registered as a Source.
- **Backup and restore**: `FileResource` provides atomic writes and backup generation management. One `.bak` generation by default; restore with `RestoreLatestBackupAsync`.
- **Safe writes**: atomicity, conflict detection, retry.
- **Sections**: `JsonSectionResource` / XML elements / YAML mappings let you treat part of a file as an independent Resource. On write, comments, whitespace, quoting, and scalar styles are preserved. Independent sections in the same file are batched into one physical write.
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`, `Configlue.Resource.Http` (ETag conditional writes and polling), `Configlue.Resource.S3`, `Configlue.Resource.Dapr`.
- **JSON Schema generation**: `Configlue.JsonSchema`, because humans write the configuration.
- **Native AOT support**: passing a source-generated `JsonSerializerContext` improves trimming/AOT resistance.
- **Reactive integration (optional)**: `Configlue.Extensions.Reactive` (System.Reactive 7.0.0) and `Configlue.Extensions.R3` (R3 1.3.1). `ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`.
- **DI integration**: `Configlue.Extensions.DI`. Microsoft options adapters in `Configlue.Extensions.MSOptions` (`IOptions<T>` etc. The synchronous getters block while asynchronous sources are read, so `GetValueAsync` is recommended in asynchronous flows).
- **Profiles / dynamic options**: named options and persistent profiles let you create and remove runtimes as a unit.
- **Known limitations**: writes across different Resources are not atomic. Source retirement is scoped to the current options instance and leaves the backing data intact. The source set is fixed for an options runtime.

## 5. Package layout (main ones)

- `Configlue` … user-facing meta-package (bundles Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer; it has no implementation assembly of its own).
- `Configlue.Abstraction` … contracts (provider/codec/resource/generated-model).
- `Configlue.Core` … the resolution and persistence runtime.
- `Configlue.Extensibility` … the provider SDK.
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn analyzer (generates sparse model support).
- `Configlue.Testing` … in-memory test doubles.
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … codecs, section resources, and file registration for each format.
- `Configlue.JsonSchema` … JSON Schema generation and export.
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … AES-GCM encryption and authentication for bytes between a Resource and a Codec.

Installation starts with `dotnet add package Configlue`. Add the capability packages you need.

## 6. Quick Start (code sample from the official README)

Save this to `example.cs` and run it with `dotnet run example.cs` (.NET 10 or later):

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 7. Inspecting where values come from / sparse saving

```csharp
var options = context.GetOptions<AppSettings>();
// 1. Get the current value (merged from all sources)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. Inspect where each value came from
var details = await options.GetDetailsAsync();
Console.WriteLine($"Name came from {details.Name.Source?.Locator}");
Console.WriteLine($"Can write Name? {details.Name.IsEditable}");
foreach (var contribution in details.Name.Sources)
{
    var source = contribution.Source;
    Console.WriteLine(
        $"  {source.Kind} | {source.Locator} | writable: {source.CanWrite} | state: {contribution.State}"
    );
}
```

Save a patch that updates only the members it specifies. `Unset()` removes that Source's contribution so a lower-priority Source can provide the value:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

Other APIs:
- `IReadOnlyOptions<T>` … the everyday read surface is `GetValueAsync` and `OnChange`.
- `SaveAsync(patch => ...)` … sparse save with the generated Patch.
- `OpenEditSessionAsync()` … edit several things together, then `CommitAsync`.
- `ApplyPatchesAsync` + `StateSourcePatch` … explicit per-source multi-write.
- `StateWritePlan.For<T>().Route(...)` … write routing.
- `SourceKey<TModel>` and `options.Source(key)` … per-source operations.

## 8. Intended audience and tone

- Audience: .NET developers, especially those who feel pain around configuration management.
- Tone: technical, concise, not exaggerated. It is good to mention the difference from `Microsoft.Extensions.Configuration` (`IConfiguration` is read-oriented, whereas Configlue is suited to composing independent sources, inspecting provenance, and sparse saving).
