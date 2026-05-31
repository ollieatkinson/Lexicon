import * as assert from "assert";
import * as vscode from "vscode";

export async function run(): Promise<void> {
	await activateExtension();
	await assertCompletions("scratch.lexicon", "\t+ test.type.even.", ["bad", "no"]);
	await assertCompletions("notes.txt", "value = l(\"test.type.even.", ["bad", "no"]);
}

async function activateExtension(): Promise<void> {
	const extension = vscode.extensions.getExtension("ollieatkinson.lexicon");
	assert.ok(extension, "Lexicon extension is registered");
	await extension.activate();
}

async function assertCompletions(
	fileName: string,
	lineText: string,
	expectedLabels: string[],
	languageId?: string
): Promise<void> {
	const workspace = vscode.workspace.workspaceFolders?.[0];
	assert.ok(workspace, "workspace folder is available");
	const uri = vscode.Uri.joinPath(workspace.uri, fileName);
	let document = await vscode.workspace.openTextDocument(uri);
	if (languageId !== undefined && document.languageId !== languageId) {
		document = await vscode.languages.setTextDocumentLanguage(document, languageId);
	}
	await vscode.window.showTextDocument(document);
	const line = document.getText().split(/\r?\n/).findIndex((value) => value.includes(lineText));
	assert.notStrictEqual(line, -1, `${fileName} contains completion line`);
	const character = document.lineAt(line).text.indexOf(lineText) + lineText.length;
	const labels = await pollCompletionLabels(uri, new vscode.Position(line, character));
	for (const expected of expectedLabels) {
		assert.ok(labels.includes(expected), `${fileName} completion labels include ${expected}; got ${labels.join(", ")}`);
	}
}

async function pollCompletionLabels(uri: vscode.Uri, position: vscode.Position): Promise<string[]> {
	for (let attempt = 0; attempt < 30; attempt += 1) {
		const completions = await vscode.commands.executeCommand<vscode.CompletionList>(
			"vscode.executeCompletionItemProvider",
			uri,
			position,
			"."
		);
		const labels = completions?.items.map((item) => String(item.label)) ?? [];
		if (labels.length > 0) {
			return labels;
		}
		await delay(250);
	}
	return [];
}

function delay(milliseconds: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
