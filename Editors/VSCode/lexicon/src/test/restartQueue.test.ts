import * as assert from "assert";
import { describe, it } from "node:test";
import { AsyncSerialQueue } from "../restartQueue";

describe("AsyncSerialQueue", () => {
	it("runs queued operations one at a time", async () => {
		const queue = new AsyncSerialQueue();
		const first = deferred<void>();
		const firstStarted = deferred<void>();
		const events: string[] = [];

		const firstRun = queue.enqueue(async () => {
			events.push("first:start");
			firstStarted.resolve();
			await first.promise;
			events.push("first:end");
		});
		const secondRun = queue.enqueue(async () => {
			events.push("second:start");
		});

		await firstStarted.promise;
		assert.deepStrictEqual(events, ["first:start"]);

		first.resolve();
		await Promise.all([firstRun, secondRun]);

		assert.deepStrictEqual(events, ["first:start", "first:end", "second:start"]);
	});

	it("keeps running later operations after a failed operation", async () => {
		const queue = new AsyncSerialQueue();
		const events: string[] = [];

		await assert.rejects(queue.enqueue(async () => {
			events.push("first");
			throw new Error("expected");
		}));
		await queue.enqueue(async () => {
			events.push("second");
		});

		assert.deepStrictEqual(events, ["first", "second"]);
	});
});

function deferred<Value>(): {
	promise: Promise<Value>;
	resolve: (value: Value | PromiseLike<Value>) => void;
	reject: (reason?: unknown) => void;
} {
	let resolve!: (value: Value | PromiseLike<Value>) => void;
	let reject!: (reason?: unknown) => void;
	const promise = new Promise<Value>((resolvePromise, rejectPromise) => {
		resolve = resolvePromise;
		reject = rejectPromise;
	});
	return { promise, resolve, reject };
}
