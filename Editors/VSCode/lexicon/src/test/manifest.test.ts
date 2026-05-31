import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import { describe, it } from "node:test";

describe("extension manifest", () => {
	it("activates for root and nested Lexicon LSP configuration files", () => {
		const manifest = JSON.parse(
			fs.readFileSync(path.resolve(__dirname, "..", "..", "package.json"), "utf8")
		);
		const activationEvents = new Set(manifest.activationEvents);
		for (const name of ["lexicon-lsp.json", ".lexicon-lsp.json", "lexicon.conf", ".lexicon.conf"]) {
			assert.ok(activationEvents.has(`workspaceContains:${name}`), `root ${name} activation is declared`);
			assert.ok(activationEvents.has(`workspaceContains:**/${name}`), `nested ${name} activation is declared`);
		}
	});
});
