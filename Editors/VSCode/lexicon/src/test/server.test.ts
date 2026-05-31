import * as assert from "assert";
import * as path from "path";
import { describe, it } from "node:test";
import {
	configuredServerCommand,
	findOnPath,
	resolveServerCommand,
	workspaceServerCandidates,
} from "../server";

const workspace = { uri: { fsPath: "/workspace" } };

describe("server command resolution", () => {
	it("uses an absolute configured server path", () => {
		const command = configuredServerCommand("/tools/lexicon-lsp", [workspace], () => false);
		assert.strictEqual(command, "/tools/lexicon-lsp");
	});

	it("resolves a relative configured server path from the workspace", () => {
		const expected = path.join("/workspace", "bin", "lexicon-lsp");
		const command = configuredServerCommand("bin/lexicon-lsp", [workspace], (file) => file === expected);
		assert.strictEqual(command, expected);
	});

	it("falls back to workspace debug and release products", () => {
		const candidates = workspaceServerCandidates([workspace]);
		assert.deepStrictEqual(candidates, [
			path.join("/workspace", ".build", "release", process.platform === "win32" ? "lexicon-lsp.exe" : "lexicon-lsp"),
			path.join("/workspace", ".build", "debug", process.platform === "win32" ? "lexicon-lsp.exe" : "lexicon-lsp"),
		]);
	});

	it("finds lexicon-lsp on PATH", () => {
		const separator = path.delimiter;
		const pathValue = [`/first`, `/second`].join(separator);
		const command = findOnPath("lexicon-lsp", pathValue, (file) => file === path.join("/second", executableName("lexicon-lsp")));
		assert.strictEqual(command, path.join("/second", executableName("lexicon-lsp")));
	});

	it("resolves configured, workspace, then PATH commands in order", () => {
		const workspaceCommand = path.join("/workspace", ".build", "debug", executableName("lexicon-lsp"));
		const command = resolveServerCommand(
			{ arguments: [], env: {} },
			[workspace],
			"/path",
			(file) => file === workspaceCommand
		);
		assert.strictEqual(command, workspaceCommand);
	});
});

function executableName(command: string): string {
	return process.platform === "win32" ? `${command}.exe` : command;
}
