import { test } from "node:test";
import assert from "node:assert/strict";
import { isBuiltInFixture } from "../src/builtins.js";

// Rio's hotel bathroom (Oct 24) priced a toilet at $48, a tub at $64 and a radiator at $32.
test("fixtures that stay with the building", () => {
  for (const [name, category] of [
    ["white two-piece elongated toilet", "appliance"],
    ["white alcove bathtub with apron front", "appliance"],
    ["white wall-mounted porcelain bathroom sink with chrome faucet", "appliance"],
    ["gray cast iron column radiator", "other"],
    ["sink", "sink"],
    ["Fireplace", "fireplace"],
    ["Stairs", "stairs"],
    // accessory words after "with" describe the fixture, they don't make it an accessory
    ["white built-in alcove bathtub with shower curtain", "appliance"],
    ["bathtub with shower head", "appliance"],
    ["stainless kitchen sink with dish rack", "appliance"],
    ["pedestal sink, towel bar", "appliance"],
  ]) assert.equal(isBuiltInFixture({ name, category }), true, name);
});

test("things that only mention a fixture are items", () => {
  for (const [name, category] of [
    ["shower caddy", "decor"],
    ["toilet paper, 12 rolls", "decor"],
    ["bath mat", "decor"],
    ["oil-filled radiator heater", "appliance"],
    ["cream fabric shower curtain with rod", "decor"],
    ["toilet brush and holder", "decor"],
    ["shower curtain with bathtub print", "decor"],
    ["black mesh office chair", "chair"],
    ["queen bed", "bed"],
  ]) assert.equal(isBuiltInFixture({ name, category }), false, name);
});

test("doors, ceiling fans and wall-mounted hotel fixtures stay with the building (Rio, Oct 24)", () => {
  for (const [name, category] of [
    ["white paneled interior door with brass knob", "storage"],
    ["brown wood-blade ceiling fan with frosted glass light kit", "fan"],
    ["chrome wall-mounted bathroom towel rack shelf", "storage"],
    ["white wall-mounted hair dryer", "appliance"],
    ["white plantation window shutters", "decor"],
    ["vertical blinds", "decor"],
    ["recessed light", "lamp"],
  ]) assert.equal(isBuiltInFixture({ name, category }), true, name);
  for (const [name, category] of [
    ["door mat", "decor"],
    ["window fan", "fan"],
    ["window AC unit", "appliance"],
    ["over-the-door hooks", "storage"],
    ["wall-mounted flat screen TV", "tv"],
    ["freestanding chrome towel rack", "storage"],
    ["box fan", "fan"],
  ]) assert.equal(isBuiltInFixture({ name, category }), false, name);
});
