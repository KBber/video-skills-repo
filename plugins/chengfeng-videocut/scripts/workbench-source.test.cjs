"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { importSnapshot, verify } = require("./import-workbench-skill.cjs");
const ID = "chengfeng-videocut-workbench";
test("fixed source rebuild, namespacing, source bytes, and fail-closed conflicts", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "videocut-source-test-"));
  const repo = path.join(temp, "source");
  const output = path.join(temp, "plugin");
  const git = args => execFileSync("git", ["-C", repo, ...args], { encoding: "utf8" }).trim();
  const source = path.join(repo, ".agents", "skills", ID);
  try {
    fs.mkdirSync(path.join(source, "agents"), { recursive: true });
    fs.writeFileSync(path.join(repo, "package.json"), JSON.stringify({ version: "0.1.0-beta.1" }));
    fs.writeFileSync(path.join(source, "SKILL.md"), "Synthetic test method, not a released Skill.\n");
    fs.writeFileSync(path.join(source, "agents/openai.yaml"), `interface:\n  default_prompt: "Use $${ID} now"\n`);
    git(["init", "-q"]);
    git(["config", "user.email", "test@example.invalid"]);
    git(["config", "user.name", "Snapshot Test"]);
    git(["remote", "add", "origin", `https://github.com/Agentchengfeng/${ID}.git`]);
    git(["add", "."]);
    git(["commit", "-qm", "synthetic fixture"]);
    const commit = git(["rev-parse", "HEAD"]);
    assert.throws(() => importSnapshot(repo, "main", output), /40-hex/);
    const lock = importSnapshot(repo, commit, output);
    assert.equal(lock.minimumRuntimeVersion, "0.5.9");
    assert.equal(lock.files["SKILL.md"].sourceSha256, lock.files["SKILL.md"].snapshotSha256);
    assert.notEqual(lock.files["agents/openai.yaml"].sourceSha256, lock.files["agents/openai.yaml"].snapshotSha256);
    assert.match(fs.readFileSync(path.join(output, "skills", ID, "agents/openai.yaml"), "utf8"), /\$chengfeng-videocut:chengfeng-videocut-workbench/);
    assert.deepEqual(importSnapshot(repo, commit, output), lock);
    fs.writeFileSync(path.join(output, "skills", ID, "SKILL.md"), "local change");
    assert.throws(() => verify(output), /digest mismatch/);
    assert.throws(() => importSnapshot(repo, commit, output), /digest mismatch/);
    git(["remote", "set-url", "origin", "https://example.invalid/other"]);
    assert.throws(() => importSnapshot(repo, commit, output), /origin/);
  } finally { fs.rmSync(temp, { recursive: true, force: true }); }
});
test("released snapshot and compatibility instructions are complete", () => {
  const root = path.resolve(__dirname, "..");
  const lock = verify(root); // Missing fixed source is a failure, never a skip.
  assert.equal(lock.version, "0.1.0-beta.1");
  const skill = fs.readFileSync(path.join(root, "skills", ID, "SKILL.md"), "utf8");
  const connection = fs.readFileSync(path.join(root, "skills", ID, "references/connection.md"), "utf8");
  assert.match(skill + connection, /0\.5\.9/);
  assert.match(connection, /capability/);
  assert.match(connection, /停止|停写/);
  assert.match(connection, /不通过 npx/);
  const runtime = JSON.parse(fs.readFileSync(path.join(root, "runtime-requirements.json"), "utf8"));
  assert.equal(runtime.releaseVersion, "0.4.11", "Skill release must not imply a Runtime release");
  assert.equal(runtime.minimumRuntimeVersion, "0.4.10", "Keep the existing six-entry contract");
});
