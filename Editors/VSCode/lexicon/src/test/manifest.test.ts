import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import { describe, it } from "node:test";

describe("extension manifest", () => {
	const manifest = JSON.parse(
		fs.readFileSync(path.resolve(__dirname, "..", "..", "package.json"), "utf8")
	);

	it("activates for root and nested Lexicon LSP configuration files", () => {
		const activationEvents = new Set(manifest.activationEvents);
		for (const name of ["lexicon-lsp.json", ".lexicon-lsp.json", "lexicon.conf", ".lexicon.conf"]) {
			assert.ok(activationEvents.has(`workspaceContains:${name}`), `root ${name} activation is declared`);
			assert.ok(activationEvents.has(`workspaceContains:**/${name}`), `nested ${name} activation is declared`);
		}
	});

	it("declares limited untrusted workspace support and restricts launch settings", () => {
		const untrustedWorkspaces = manifest.capabilities?.untrustedWorkspaces;
		assert.strictEqual(untrustedWorkspaces?.supported, "limited");
		assert.deepStrictEqual(
			new Set(untrustedWorkspaces?.restrictedConfigurations),
			new Set([
				"lexicon.lsp.binary.path",
				"lexicon.lsp.binary.arguments",
				"lexicon.lsp.binary.env",
			])
		);

		const restartCommand = manifest.contributes.commands.find(
			(command: { command: string }) => command.command === "lexicon.restartLanguageServer"
		);
		assert.strictEqual(restartCommand?.enablement, "isWorkspaceTrusted");
	});
});
