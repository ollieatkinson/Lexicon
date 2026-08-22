export class AsyncSerialQueue {
	private tail: Promise<void> = Promise.resolve();

	enqueue(operation: () => Promise<void>): Promise<void> {
		const next = this.tail.catch(() => undefined).then(operation);
		this.tail = next.catch(() => undefined);
		return next;
	}
}
