#!/usr/bin/env node
"use strict"

const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const source = fs.readFileSync(new URL("../Model.js", `file://${__filename}`), "utf8")
const model = vm.runInNewContext(source + `
  ({
    normalizeAudioOutputs: normalizeAudioOutputs,
    effectiveAudioOutput: effectiveAudioOutput,
    audioOutputWarning: audioOutputWarning
  })
`)

const raw = [
  { name: "auto", description: "Autoselect device" },
  { name: "alsa/default", description: "Raw ALSA (ignore)" },
  { name: "pipewire/office", description: "Office speakers" },
  { name: "pipewire/homepod_bridge", description: "HomePods" }
]
const outputs = model.normalizeAudioOutputs(raw)
assert.deepEqual(Array.from(outputs, item => item.name), [
  "auto", "pipewire/office", "pipewire/homepod_bridge"
])

// Keep the preference while unavailable, route only Dromify to auto, then
// restore the preferred output after both presence and readiness return.
const preferred = "pipewire/homepod_bridge"
assert.equal(model.effectiveAudioOutput(preferred, outputs, false), "auto")
assert.match(model.audioOutputWarning(preferred, outputs, false), /HomePods are unavailable/)
assert.equal(preferred, "pipewire/homepod_bridge")
assert.equal(model.effectiveAudioOutput(preferred, outputs, true), preferred)
assert.equal(model.audioOutputWarning(preferred, outputs, true), "")
assert.equal(model.effectiveAudioOutput(preferred, outputs.filter(item => item.name !== preferred), true), "auto")

// Choosing System default remains mpv's "auto", irrespective of devices or
// bridge state; this policy never changes the system-wide default sink.
assert.equal(model.effectiveAudioOutput("auto", outputs, true), "auto")
assert.equal(model.effectiveAudioOutput("auto", outputs, false), "auto")

console.log("audio-output-policy: ok")
