import { test } from "node:test";
import assert from "node:assert/strict";
import { createFavoriteStorage } from "./favoriteStorage";

test("a failed favorites read never writes defaults; a later tap retries the read", async () => {
  let readFailure = true;
  let value = JSON.stringify(["saved", 5]);
  const writes: string[] = [];
  const storage = createFavoriteStorage({
    getItem: async () => {
      if (readFailure) throw new Error("read failed");
      return value;
    },
    setItem: async (_, next) => { writes.push(next); value = next; },
  });
  await assert.rejects(storage.load("owner"), /read failed/);
  await assert.rejects(storage.toggle("owner", ["new"]), /read failed/);
  assert.deepEqual(writes, []);
  readFailure = false;
  assert.deepEqual(await storage.toggle("owner", ["new", "new"]), ["saved", "new"]);
  assert.deepEqual(JSON.parse(value), ["saved", "new"]);
  assert.deepEqual(await storage.toggle("owner", ["saved", "new"]), []);
});

test("rapid toggles and a remount observe writes in order for the same storage key", async () => {
  const values = new Map<string, string>();
  let release!: () => void;
  const paused = new Promise<void>(resolve => { release = resolve; });
  const storage = createFavoriteStorage({
    getItem: async key => values.get(key) ?? null,
    setItem: async (key, value) => {
      if (key === "alice") await paused;
      values.set(key, value);
    },
  });
  const first = storage.toggle("alice", ["x"]);
  const second = storage.toggle("alice", ["y"]);
  const third = storage.toggle("alice", ["x"]);
  const remount = storage.load("alice");
  assert.deepEqual(await storage.toggle("bob", ["z"]), ["z"]);
  assert.equal(values.has("alice"), false);
  release();
  assert.deepEqual(await first, ["x"]);
  assert.deepEqual(await second, ["x", "y"]);
  assert.deepEqual(await third, ["y"]);
  assert.deepEqual(await remount, ["y"]);
});

test("a failed favorites write does not commit or block a retry", async () => {
  let firstWrite = true;
  let value = '["existing"]';
  const storage = createFavoriteStorage({
    getItem: async () => value,
    setItem: async (_, next) => {
      if (firstWrite) { firstWrite = false; throw new Error("write failed"); }
      value = next;
    },
  });
  const failed = storage.toggle("owner", ["new"]);
  const retry = storage.toggle("owner", ["new"]);
  await assert.rejects(failed, /write failed/);
  assert.deepEqual(await retry, ["existing", "new"]);
  assert.deepEqual(JSON.parse(value), ["existing", "new"]);
});
