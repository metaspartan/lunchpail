# Third-party notices

## Cua / Lume Metal capability shim

`Guest/MetalShim/LunchpailMetalCapabilities.m` is adapted from the Lume Metal
capability shim in [trycua/cua](https://github.com/trycua/cua/tree/main/libs/lume/metal-capability-shim),
retrieved from commit `9bd4221e523efa7da67bb0516918f1956849833a` on 2026-08-11.

Copyright 2026 Cua AI, Inc. Licensed under the MIT License. The complete
license text is in `Guest/MetalShim/LICENSE`.

Lunchpail changes the environment-variable namespace, tightens numeric bounds,
and keeps the original fail-closed, process-scoped behavior.
