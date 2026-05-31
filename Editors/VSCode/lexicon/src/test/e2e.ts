import * as assert from "assert";
import * as vscode from "vscode";

export async function run(): Promise<void> {
	await assertExtensionActivatedByWorkspaceConfiguration();
	await assertCompletions("app/scratch.lexicon", "\t+ test.type.even.", ["bad", "no"]);
	await assertCompletions("app/notes.txt", "value = l(\"test.type.even.", ["bad", "no"]);
	await replaceWorkspaceConfiguration();
	await assertCompletions("app/notes.txt", "value = l(\"test.type.even.", ["good", "yes"], ["bad", "no"]);
}

async function assertExtensionActivatedByWorkspaceConfiguration(): Promise<void> {
	const extension = vscode.extensions.getExtension("ollieatkinson.lexicon");
	assert.ok(extension, "Lexicon extension is registered");
	for (let attempt = 0; attempt < 40; attempt += 1) {
		if (extension.isActive) {
			return;
		}
		await delay(250);
	}
	assert.ok(extension.isActive, "Lexicon extension is activated by nested workspace configuration");
}

async function assertCompletions(
	fileName: string,
	lineText: string,
	expectedLabels: string[],
	rejectedLabels: string[] = [],
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
	const labels = await pollCompletionLabels(uri, new vscode.Position(line, character), expectedLabels, rejectedLabels);
	for (const expected of expectedLabels) {
		assert.ok(labels.includes(expected), `${fileName} completion labels include ${expected}; got ${labels.join(", ")}`);
	}
	for (const rejected of rejectedLabels) {
		assert.ok(!labels.includes(rejected), `${fileName} completion labels do not include ${rejected}; got ${labels.join(", ")}`);
	}
}

async function pollCompletionLabels(
	uri: vscode.Uri,
	position: vscode.Position,
	expectedLabels: string[],
	rejectedLabels: string[]
): Promise<string[]> {
	let lastLabels: string[] = [];
	for (let attempt = 0; attempt < 40; attempt += 1) {
		const completions = await vscode.commands.executeCommand<vscode.CompletionList>(
			"vscode.executeCompletionItemProvider",
			uri,
			position,
			"."
		);
		const labels = completions?.items.map((item) => String(item.label)) ?? [];
		lastLabels = labels;
		if (
			expectedLabels.every((label) => labels.includes(label))
			&& rejectedLabels.every((label) => !labels.includes(label))
		) {
			return labels;
		}
		await delay(250);
	}
	return lastLabels;
}

async function replaceWorkspaceConfiguration(): Promise<void> {
	const workspace = vscode.workspace.workspaceFolders?.[0];
	assert.ok(workspace, "workspace folder is available");
	await vscode.workspace.fs.writeFile(
		vscode.Uri.joinPath(workspace.uri, "app", ".lexicon.conf"),
		new TextEncoder().encode(JSON.stringify({ lexicon: "replacement.lexicon" }, null, 2))
	);
}

function delay(milliseconds: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
