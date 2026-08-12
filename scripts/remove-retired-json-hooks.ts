#!/usr/bin/env bun

import {
  chmodSync,
  lstatSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";
import { randomUUID } from "node:crypto";

type JsonObject = Record<string, unknown>;

function die(message: string): never {
  process.stderr.write(`retired JSON hook cleanup: ${message}\n`);
  process.exit(1);
}

function usage(): never {
  process.stderr.write(
    "Usage: remove-retired-json-hooks.ts [--bundle NAME] [--delete-if-empty] CONFIG STEM...\n",
  );
  process.exit(64);
}

let bundle: string | null = null;
let deleteIfEmpty = false;
const positional: string[] = [];
for (let index = 2; index < process.argv.length; index += 1) {
  const argument = process.argv[index];
  if (argument === "--bundle") {
    const value = process.argv[index + 1];
    if (!value) usage();
    bundle = value;
    index += 1;
  } else if (argument === "--delete-if-empty") {
    deleteIfEmpty = true;
  } else if (argument.startsWith("--")) {
    usage();
  } else {
    positional.push(argument);
  }
}
if (positional.length < 2) usage();

const [configPath, ...scriptStems] = positional;
for (const stem of scriptStems) {
  if (!/^[A-Za-z0-9][A-Za-z0-9-]*$/.test(stem)) {
    die(`unsafe managed script stem: ${stem}`);
  }
}

let metadata;
try {
  metadata = lstatSync(configPath);
} catch (error) {
  die(`could not inspect ${configPath}: ${String(error)}`);
}
if (!metadata.isFile() || metadata.isSymbolicLink()) {
  die(`refusing to edit unsafe hook configuration: ${configPath}`);
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function decodedPowerShellCommand(command: string): string | null {
  const match = command.match(/\s-EncodedCommand\s+(\S+)/i);
  if (!match) return null;
  try {
    return Buffer.from(match[1], "base64").toString("utf16le");
  } catch {
    return null;
  }
}

const needles = scriptStems.flatMap((stem) =>
  ["cmd", "ps1", "sh"].map((extension) =>
    `agent-hooks/${stem}.${extension}`,
  ),
);
function isManagedCommand(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const decoded = decodedPowerShellCommand(value);
  const searchable = decoded ? `${value}\n${decoded}` : value;
  const normalized = searchable.replaceAll("\\", "/");
  return needles.some((needle) => normalized.includes(needle));
}

let config: JsonObject;
try {
  const raw = readFileSync(configPath, "utf8").replace(/^\uFEFF/, "");
  const parsed = Bun.JSONC.parse(raw) as unknown;
  if (!isObject(parsed)) die(`${configPath} root is not an object`);
  config = parsed;
} catch (error) {
  die(`${configPath} is not valid JSON/JSONC: ${String(error)}`);
}

let changed = false;
function cleanDefinition(value: unknown): unknown | null {
  if (!isObject(value)) return value;

  const next: JsonObject = { ...value };
  for (const key of ["command", "bash", "powershell"] as const) {
    if (isManagedCommand(next[key])) {
      delete next[key];
      changed = true;
    }
  }

  if (Array.isArray(value.hooks)) {
    const filtered = value.hooks.filter(
      (hook) => !(isObject(hook) && isManagedCommand(hook.command)),
    );
    if (filtered.length !== value.hooks.length) {
      changed = true;
      if (filtered.length > 0) next.hooks = filtered;
      else delete next.hooks;
    }
  }

  const stillHasCommand =
    ["command", "bash", "powershell"].some(
      (key) => typeof next[key] === "string",
    ) ||
    (Array.isArray(next.hooks) && next.hooks.length > 0);
  return stillHasCommand ? next : null;
}

const hookContainer = bundle === null ? config.hooks : config[bundle];
if (isObject(hookContainer)) {
  const nextContainer: JsonObject = { ...hookContainer };
  for (const [eventName, definitions] of Object.entries(nextContainer)) {
    if (!Array.isArray(definitions)) continue;
    const cleaned = definitions
      .map(cleanDefinition)
      .filter((definition) => definition !== null);
    if (cleaned.length !== definitions.length) changed = true;
    if (cleaned.length > 0) nextContainer[eventName] = cleaned;
    else if (definitions.length > 0) delete nextContainer[eventName];
  }
  if (changed) {
    if (bundle === null) config.hooks = nextContainer;
    else if (Object.keys(nextContainer).length > 0) config[bundle] = nextContainer;
    else delete config[bundle];
  }
}

if (!changed) {
  process.stdout.write("unchanged\n");
  process.exit(0);
}

const hooks = config.hooks;
const onlyDedicatedKeys = Object.keys(config).every(
  (key) => key === "hooks" || key === "version",
);
if (
  deleteIfEmpty &&
  onlyDedicatedKeys &&
  isObject(hooks) &&
  Object.keys(hooks).length === 0
) {
  unlinkSync(configPath);
  process.stdout.write("deleted\n");
  process.exit(0);
}

const temporary = join(
  dirname(configPath),
  `.${basename(configPath)}.agentstart-${randomUUID()}.tmp`,
);
try {
  writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`, "utf8");
  chmodSync(temporary, statSync(configPath).mode & 0o777);
  renameSync(temporary, configPath);
} finally {
  rmSync(temporary, { force: true });
}
process.stdout.write("changed\n");
