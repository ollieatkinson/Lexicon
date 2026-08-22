import * as assert from "assert";
import * as vscode from "vscode";

export async function run(): Promise<void> {
	assert.strictEqual(vscode.workspace.isTrusted, false, "workspace opens in Restricted Mode");

	const extension = vscode.extensions.getExtension("ollieatkinson.lexicon");
	if (extension === undefined) {
		assert.fail("Lexicon extension is registered");
	}
	await extension.activate();
	assert.strictEqual(extension.isActive, true, "limited extension support remains active");

	const configuration = vscode.workspace.getConfiguration("lexicon.lsp.binary");
	assert.strictEqual(configuration.get("path", ""), "");
	assert.deepStrictEqual(configuration.get("arguments", []), []);
	assert.deepStrictEqual(configuration.get("env", {}), {});

	await vscode.commands.executeCommand("lexicon.restartLanguageServer");
	await delay(1_000);

	const workspace = vscode.workspace.workspaceFolders?.[0];
	if (workspace === undefined) {
		assert.fail("workspace folder is available");
	}
	await assertFileDoesNotExist(vscode.Uri.joinPath(workspace.uri, ".server-launched"));
}

async function assertFileDoesNotExist(uri: vscode.Uri): Promise<void> {
	try {
		await vscode.workspace.fs.stat(uri);
		assert.fail("untrusted workspace executable was launched");
	} catch (error) {
		if (error instanceof vscode.FileSystemError && error.code === "FileNotFound") {
			return;
		}
		throw error;
	}
}

function delay(milliseconds: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
