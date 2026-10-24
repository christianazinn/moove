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
  ]) assert.equal(isBuiltInFixture({ name, category }), true, name);
});

test("things that only mention a fixture are items", () => {
  for (const [name, category] of [
    ["shower caddy", "decor"],
    ["toilet paper, 12 rolls", "decor"],
    ["bath mat", "decor"],
    ["oil-filled radiator heater", "appliance"],
    ["chrome wall-mounted bathroom towel rack shelf", "storage"],
    ["cream fabric shower curtain with rod", "decor"],
    ["black mesh office chair", "chair"],
    ["queen bed", "bed"],
  ]) assert.equal(isBuiltInFixture({ name, category }), false, name);
});
