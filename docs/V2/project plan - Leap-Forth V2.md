# 2068-Leap Forth V2 --- Project Plan

## 1. Project Purpose

2068-Leap Forth V2 will modernize the existing Leap-Forth V1 environment
by selectively adopting the mature platform services developed for
2068-Leap V2 while preserving the execution model, immediacy,
compactness, and performance characteristics that make the existing
Forth effective on the Timex Sinclair 2068.

This is not a rewrite of Forth on top of the Leap BASIC V2 virtual
machine.

The Forth inner interpreter, dictionary, compilation model, data stack,
return stack, and native primitives remain independent unless
measurement proves that a different implementation is superior.

The project should provide a clear improvement over Leap-Forth V1 in
development environment and platform capability without accepting
unnecessary runtime overhead.

## 2. Mandatory Hardware Target

The base system must run on an original, unexpanded Timex Sinclair 2068:

-   Z80A-compatible CPU.
-   48 KB RAM.
-   24 KB replacement HOME ROM architecture as appropriate to the Leap
    platform.
-   TS2068 memory banking/EXROM facilities.
-   Native TS2068 video hardware.
-   AY-3-8912 sound.
-   Keyboard and joystick hardware.
-   Cassette storage.

No RAM expansion may be required for the core Forth environment.

## 3. Central Design Rule

> Keep Forth Forth.

V2 platform code is not adopted merely because it is newer.

For every proposed V2 component, determine:

1.  Does it improve capability?
2.  Does it reduce duplicate code?
3.  Does it save ROM or RAM?
4.  Does it improve reliability?
5.  Does it preserve or improve Forth performance?
6.  Does it introduce runtime overhead when unused?

If a V1 mechanism is smaller, faster, or more appropriate to Forth,
retain it.

## 4. User-Interface Model

Leap-Forth V2 should deliberately provide two complementary editing
environments.

### 4.1 Interactive Forth console

The existing Forth-style command-line interaction remains the primary
interface:

    OK
    10 20 + .
    30 OK

    : SQUARE DUP * ;
    OK

The console should remain fast and immediate. It must not require
entering a full-screen editor for ordinary Forth interaction.

### 4.2 Full-screen source editor

The Leap V2 full-screen editor infrastructure should be evaluated for
use as an additional development tool.

Target uses include:

    EDIT SPIRAL

to edit a saved/source-backed definition, and a mechanism conceptually
similar to:

    EDIT "GRAPHICS"

to edit a larger source unit.

The exact syntax is not fixed by this plan.

The full-screen editor should support larger Forth development without
replacing the normal Forth command line.

### 4.3 Editor performance

The mature Leap V2 redraw logic should be reused where appropriate.

The known redraw/flicker regression tests from Leap V1/V2 should be
retained or adapted.

Full-screen editing must not introduce execution overhead into ordinary
Forth word execution.

## 5. Performance Baseline

Leap-Forth V1 is the formal baseline.

Before modifying the execution engine, record:

-   Inner-interpreter/NEXT implementation.
-   Threading model.
-   Register allocation.
-   Dictionary representation.
-   Data-stack implementation.
-   Return-stack implementation.
-   Primitive-call mechanism.
-   Colon-definition execution mechanism.
-   Compilation behavior.
-   Representative word sizes.
-   Dictionary overhead.
-   Available RAM.
-   HOME/EXROM usage where applicable.

Benchmark representative programs before V2 changes begin.

No claim that V2 is faster or slower should be made without
measurements.

## Phase 0 --- Freeze Leap-Forth V1

### Objectives

Establish a reproducible reference version.

### Tasks

-   Identify the current known-good V1 revision.
-   Build from a clean tree.
-   Run existing tests.
-   Record ROM/RAM maps.
-   Record dictionary and stack layouts.
-   Record free memory.
-   Document the editor/console implementation.
-   Record existing platform dependencies.
-   Create the V1 benchmark suite.
-   Run benchmarks in the current emulator/simulator environment.
-   Run representative benchmarks on real TS2068 hardware where
    practical.

### Deliverable

`docs/FORTH_V1_BASELINE.md`

### Exit criteria

V1 can be reproduced and measured throughout the V2 project.

## Phase 1 --- Leap V2 Platform Reuse Audit

### Objectives

Determine what the Forth environment can gain from the completed
2068-Leap V2 platform.

### Audit categories

Classify every candidate service as:

1.  Reuse unchanged.
2.  Adapt behind a Forth interface.
3.  Reuse only if measurement justifies it.
4.  Retain Forth V1 implementation.
5.  Not needed.

### Audit areas

-   Startup/kernel.
-   HOME/EXROM banking.
-   Display.
-   Full-screen editor.
-   Keyboard/input.
-   Graphics.
-   Video modes.
-   ULAplus.
-   Sprites.
-   AY sound.
-   Storage.
-   Package loader.
-   Extension registry/ABI.
-   Error handling.
-   Timing.
-   Numeric services.
-   Debugger/emulator support.

Do not include the Leap BASIC V2 compiler, parser, decompiler, or BASIC
VM merely because they exist.

### Deliverable

`docs/FORTH_V2_REUSE_AUDIT.md`

Include byte-level ROM/RAM costs where measurable.

## Phase 2 --- Performance Characterization

### Objectives

Understand where Leap-Forth V1 spends its execution time before changing
it.

### Benchmarks

Include:

-   Empty colon definition/call overhead.
-   DUP/DROP/SWAP/OVER.
-   Integer addition/subtraction.
-   Multiplication/division.
-   Tight DO/LOOP.
-   BEGIN/UNTIL.
-   Memory fetch/store.
-   Nested word calls.
-   Recursive calls if supported.
-   Dictionary lookup.
-   Compilation speed.
-   Graphics calls.
-   Screen output.
-   Representative application.

Record elapsed cycles/time where the available tools permit reliable
measurement.

### Exit criteria

Optimization decisions can be based on measured hot paths.

## Phase 3 --- Forth Core Architecture Audit

### Objectives

Determine whether any execution-engine change is justified.

### Investigate

-   Existing threading model.
-   Direct threading.
-   Indirect threading.
-   Token/subroutine threading where relevant.
-   Register allocation.
-   Top-of-stack caching.
-   NEXT implementation.
-   Primitive dispatch.
-   Common primitive inlining.
-   Colon-call/return path.

Experiments must be isolated branches or prototypes.

### Rule

The project must not replace the V1 inner interpreter merely for
architectural consistency with Leap V2.

### Exit criteria

Either:

A. V1 execution core is retained because it remains the best measured
choice,

or

B. a replacement demonstrably improves the chosen balance of speed, ROM,
RAM, and dictionary density.

## Phase 4 --- Platform ABI Adaptation

### Objectives

Separate the Forth language engine from TS2068 platform implementations.

### Define Forth-facing services for

-   Character output.
-   Character/input polling.
-   Keyboard.
-   Display control.
-   Graphics.
-   Sound.
-   Storage.
-   Video modes.
-   Sprites.
-   Timing.
-   Banking.
-   Package services.

Where practical, expose these through normal Forth words whose
implementation calls a stable platform ABI.

### Goal

The Forth execution core should not need to know whether a service
originated in Leap-Forth V1 or Leap V2.

### Deliverable

`docs/FORTH_PLATFORM_ABI.md`

## Phase 5 --- Basic V2 Platform Port

### Objectives

Produce the first Forth build using selected V2 platform services while
retaining the V1 Forth execution model.

### Initial scope

Prefer low-risk infrastructure:

-   Startup.
-   Banking where beneficial.
-   Keyboard/input.
-   Display output.
-   Error paths.
-   Timing.

### Tests

Run the complete V1 language and performance suite after each meaningful
substitution.

### Exit criteria

The hybrid build behaves like V1 and has no unexplained performance
regression.

## Phase 6 --- Graphics and Video Integration

### Objectives

Expose the mature Leap V2 graphics system as idiomatic Forth words.

### Candidate words/services

-   CLS.
-   INK.
-   PAPER.
-   BORDER.
-   PLOT.
-   LINE.
-   CIRCLE.
-   RECT.
-   FILL.
-   MODE.
-   UDG facilities.
-   ULAplus/palette facilities.

Exact stack effects must be documented.

Example style:

    x y PLOT
    x0 y0 x1 y1 LINE

### Requirements

-   Avoid duplicate graphics implementations where V2 code is
    demonstrably suitable.
-   Measure service-call overhead.
-   Keep low-level access possible where useful.

### Exit criteria

Graphics demonstrations run correctly on real hardware.

## Phase 7 --- Sprite Integration

### Objectives

Expose the proven Leap sprite subsystem to Forth.

### Candidate operations

-   GRAB.
-   SHOW.
-   HIDE.
-   MOVE.
-   HIT/collision support where present in the platform.

Define idiomatic stack effects rather than copying BASIC syntax.

### Exit criteria

A representative animated sprite program runs from Forth.

## Phase 8 --- AY Sound Integration

### Objectives

Expose both convenient and low-level sound facilities.

### Candidate words

-   BEEP.
-   SOUND.
-   Tone.
-   Noise.
-   Mixer.
-   Volume.
-   Envelope.
-   AY register access where appropriate.

Reuse mature V2 services when they outperform or simplify the V1
equivalents.

### Exit criteria

Sound tests pass on physical AY hardware.

## Phase 9 --- Storage Modernization

### Objectives

Adopt the mature Leap storage architecture where it improves Forth.

### Requirements

Support saving/loading at least:

-   Forth source units.
-   Dictionary/application images if the architecture supports them
    safely.
-   Optional packages/modules where applicable.

Respect physical cassette limitations.

Do not introduce a tape catalog requiring impractical reel traversal.

### Tests

-   Real cassette save/load.
-   Interrupted load.
-   Bad block/checksum.
-   Truncated input.
-   Memory exhaustion.
-   Recovery to a usable Forth prompt after failure where possible.

## Phase 10 --- Full-Screen Editor Prototype

### Objectives

Add the V2 full-screen editor without disturbing the interactive
console.

### Prototype modes

#### Definition editing

Conceptual interface:

    EDIT SPIRAL

Open source associated with a Forth definition, permit editing, then
recompile/update appropriately.

#### Source-unit editing

Conceptual interface:

    EDIT "GRAPHICS"

Edit a larger Forth source unit for later compilation/inclusion.

### Requirements

-   Command-line Forth remains available and primary.
-   Editor code should reuse V2 display/redraw infrastructure.
-   Editor workspace should be reclaimed/reused when practical.
-   Editing must not permanently consume excessive dictionary space.
-   Existing Forth source should remain ordinary Forth text where
    possible.

### Exit criteria

A multi-definition program can be comfortably edited full-screen and
compiled into the Forth environment.

## Phase 11 --- Source and Dictionary Model

### Objectives

Define how full-screen source relates to the live dictionary.

### Resolve

-   Whether dictionary entries retain source references.
-   How EDIT locates a word's source.
-   How edited words are replaced/redefined.
-   Whether source units have names.
-   INCLUDE/LOAD semantics.
-   Dependency behavior.
-   Forgotten/redefined words.
-   Source storage format.
-   Interaction with cassette storage.

### Principle

Do not burden every dictionary entry with substantial source metadata
merely to support the editor.

### Deliverable

`docs/FORTH_SOURCE_MODEL.md`

## Phase 12 --- Dictionary-Aware Development Tools

### Objectives

Improve development ergonomics while preserving Forth simplicity.

### Candidate features

-   WORDS.
-   SEE.
-   EDIT `<word>`{=html}.
-   Source lookup.
-   Vocabulary browsing.
-   Stack-effect/help metadata where inexpensive.
-   Cross-reference tools as optional development facilities.

These are not all mandatory.

Measure their ROM/RAM cost before making them resident.

## Phase 13 --- Package and Extension Integration

### Objectives

Make Forth a first-class consumer of the V2 package architecture.

Forth is naturally extensible, so package integration should complement
rather than fight the dictionary model.

### Investigate

-   Loading native packages.
-   Registering package words.
-   Package ownership.
-   Dictionary entries referring to package code.
-   Safe unload behavior.
-   Package dependencies.
-   Memory reclamation.
-   ABI versioning.

### Critical safety rule

A package must not be unloadable while live dictionary words can still
execute code within it unless those references are safely invalidated.

### Exit criteria

At least one optional package can be loaded, used through Forth words,
and safely unloaded or explicitly declared non-unloadable.

## Phase 14 --- Memory and Banking Optimization

### Objectives

Use V2 experience to improve Forth's effective memory without slowing
the language unnecessarily.

### Measure

-   Resident Forth core.
-   Platform services.
-   Dictionary.
-   Data stack.
-   Return stack.
-   Editor workspace.
-   Source buffers.
-   Package memory.
-   Graphics/sprite workspace.
-   Free application RAM.

Investigate whether editor/compiler/source buffers can overlay memory
used for mutually exclusive activities.

### Rule

Memory banking must not be introduced into the hot Forth execution path
unless its benefit clearly outweighs its cost.

## Phase 15 --- Performance Regression Gate

### Objectives

Compare the mature V2 build directly against V1.

### Required comparison

For every benchmark record:

  Test                       V1    V2   Delta Explanation
  ----------------------- ----- ----- ------- -------------
  Primitive execution       TBD   TBD     TBD 
  Colon call                TBD   TBD     TBD 
  Tight loop                TBD   TBD     TBD 
  Memory access             TBD   TBD     TBD 
  Dictionary lookup         TBD   TBD     TBD 
  Compilation               TBD   TBD     TBD 
  Graphics                  TBD   TBD     TBD 
  Text output               TBD   TBD     TBD 
  Application benchmark     TBD   TBD     TBD 

### Acceptance policy

Core Forth execution should ideally equal or exceed V1.

Any regression must be:

-   measured,
-   understood,
-   localized,
-   and justified by a meaningful benefit.

Platform features that are not being used should impose essentially no
runtime cost on ordinary Forth execution.

## Phase 16 --- Real-Hardware Qualification

### Required physical tests

-   Cold boot.
-   Forth prompt.
-   Interactive line editing.
-   Definition compilation.
-   Dictionary operation.
-   Stack behavior.
-   Full-screen editor.
-   Editor redraw/flicker.
-   Keyboard.
-   Graphics.
-   Video modes.
-   Sprites.
-   AY sound.
-   Cassette save/load.
-   Package loading.
-   Banking.
-   Long-running execution.
-   Recovery from expected errors.

Use ZEsarUX and project debugging/simulation tools during development,
but do not substitute emulator success for final hardware validation.

## Phase 17 --- Representative Programs

Maintain a qualification/demo suite including:

1.  Arithmetic benchmark.
2.  Loop benchmark.
3.  Sieve or similar computation.
4.  Recursive example where appropriate.
5.  Graphics benchmark.
6.  Turtle/geometry-style drawing demo.
7.  Sprite animation.
8.  AY sound/music demo.
9.  Interactive application.
10. Multi-definition program created with the full-screen editor.
11. Cassette save/load example.
12. Optional-package example.

Programs should help measure both performance and usability.

## Phase 18 --- Documentation

Produce:

-   User guide.
-   Forth word reference.
-   Platform word reference.
-   Full-screen editor guide.
-   Source-unit workflow.
-   Package developer guide.
-   Memory map.
-   Dictionary layout.
-   Stack conventions.
-   Inner-interpreter architecture.
-   Platform ABI.
-   Build instructions.
-   Emulator/debugger workflow.
-   Hardware qualification report.
-   V1 vs V2 benchmark report.

## Phase 19 --- Release Qualification

A Leap-Forth V2 release is ready when:

-   It runs on an original 48K TS2068.
-   Interactive Forth remains immediate and reliable.
-   The V1 execution architecture has been preserved or replaced only
    with measured justification.
-   Core benchmarks are at least competitive with V1.
-   V2 platform services provide clear functional benefit.
-   Full-screen editing works as an optional development mode.
-   Command-line Forth remains the normal interactive environment.
-   Graphics, sprites, sound, storage, and selected package facilities
    are qualified.
-   ROM and RAM use are documented.
-   Editor redraw/flicker regression tests pass.
-   Real cassette tests pass.
-   Real hardware qualification passes.
-   Known limitations are documented.

## Project Guardrails

Throughout the project:

-   Do not run Forth through the Leap BASIC bytecode VM merely for
    architectural uniformity.
-   Do not replace the Forth inner interpreter without benchmark
    evidence.
-   Do not remove the interactive Forth command line.
-   Do not make the full-screen editor mandatory for ordinary Forth use.
-   Do not introduce V2 services into hot paths when unused.
-   Do not duplicate mature platform code without a measured reason.
-   Do not sacrifice dictionary/application RAM casually.
-   Do not require expanded RAM.
-   Do not claim performance improvements without measurements.
-   Do not claim hardware qualification from simulator/emulator results
    alone.
-   Preserve the editor redraw/flicker safeguards and their regression
    coverage.
-   Stop for user input only when a decision changes hardware
    requirements, fundamental Forth semantics, compatibility, or
    involves an unresolved major speed/ROM/RAM tradeoff.

## Primary Metrics

Record after every major phase:

  Metric                       V1 Baseline   V2 Current   Delta
  -------------------------- ------------- ------------ -------
  HOME ROM used/free                   TBD          TBD     TBD
  EXROM used/free                      TBD          TBD     TBD
  Forth core size                      TBD          TBD     TBD
  Platform code size                   TBD          TBD     TBD
  Dictionary overhead/word             TBD          TBD     TBD
  Free dictionary RAM                  TBD          TBD     TBD
  Data-stack allowance                 TBD          TBD     TBD
  Return-stack allowance               TBD          TBD     TBD
  Editor workspace                     TBD          TBD     TBD
  Source workspace                     TBD          TBD     TBD
  NEXT cycles/time                     TBD          TBD     TBD
  Colon-call overhead                  TBD          TBD     TBD
  Dictionary lookup                    TBD          TBD     TBD
  Representative benchmark             TBD          TBD     TBD

## Long-Term Architectural Goal

Leap-Forth V2 should help establish a language-independent 2068-Leap
platform without forcing different languages into a common execution
model.

The desired relationship is:

    2068-Leap BASIC V2
        BASIC compiler/VM
                |
                |
    2068-Leap Pascal
        Pascal compiler/VM
                |
                +---- shared Leap platform ABI ---- TS2068 hardware
                |
    2068-Leap Forth V2
        Forth compiler/NEXT

The languages should share mature hardware and operating services while
retaining execution architectures appropriate to each language.

For Forth specifically, success means gaining the best parts of the V2
platform without losing the speed, compactness, interactivity, and
simplicity of Leap-Forth V1.
