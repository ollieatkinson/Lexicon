import * as vscode from "vscode";
import {
	LanguageClient,
	LanguageClientOptions,
	ServerOptions,
	TransportKind,
} from "vscode-languageclient/node";
import {
	ServerBinaryConfiguration,
	resolveServerCommand,
} from "./server";

let client: LanguageClient | undefined;
let outputChannel: vscode.OutputChannel | undefined;
let configurationWatcher: vscode.FileSystemWatcher | undefined;
let restartTimer: NodeJS.Timeout | undefined;

const configurationFileNames = [
	"lexicon-lsp.json",
	".lexicon-lsp.json",
	"lexicon.conf",
	".lexicon.conf",
];

export async function activate(context: vscode.ExtensionContext): Promise<void> {
	outputChannel = vscode.window.createOutputChannel("Lexicon LSP");
	context.subscriptions.push(outputChannel);
	context.subscriptions.push(vscode.commands.registerCommand("lexicon.restartLanguageServer", restartLanguageServer));
	context.subscriptions.push(vscode.commands.registerCommand("lexicon.showOutput", () => outputChannel?.show()));
	configurationWatcher = vscode.workspace.createFileSystemWatcher(configurationGlob());
	configurationWatcher.onDidCreate(scheduleLanguageServerRestart, undefined, context.subscriptions);
	configurationWatcher.onDidChange(scheduleLanguageServerRestart, undefined, context.subscriptions);
	configurationWatcher.onDidDelete(scheduleLanguageServerRestart, undefined, context.subscriptions);
	context.subscriptions.push(configurationWatcher);
	context.subscriptions.push(vscode.workspace.onDidChangeConfiguration((event) => {
		if (event.affectsConfiguration("lexicon.lsp.binary")) {
			void restartLanguageServer();
		}
	}));
	await startLanguageServer();
}

export async function deactivate(): Promise<void> {
	if (restartTimer !== undefined) {
		clearTimeout(restartTimer);
		restartTimer = undefined;
	}
	await stopLanguageServer();
}

function scheduleLanguageServerRestart(): void {
	if (restartTimer !== undefined) {
		clearTimeout(restartTimer);
	}
	restartTimer = setTimeout(() => {
		restartTimer = undefined;
		void restartLanguageServer();
	}, 250);
}

async function restartLanguageServer(): Promise<void> {
	await stopLanguageServer();
	await startLanguageServer();
}

async function startLanguageServer(): Promise<void> {
	const binary = binaryConfiguration();
	const command = resolveServerCommand(binary, vscode.workspace.workspaceFolders);
	if (command === undefined) {
		const message = "Install lexicon-lsp, build it in this workspace, or configure lexicon.lsp.binary.path.";
		outputChannel?.appendLine(message);
		await vscode.window.showWarningMessage(`Lexicon LSP was not found. ${message}`);
		return;
	}

	const serverOptions: ServerOptions = {
		command,
		args: binary.arguments,
		transport: TransportKind.stdio,
		options: {
			cwd: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath,
			env: {
				...process.env,
				...binary.env,
			},
		},
	};
	const clientOptions: LanguageClientOptions = {
		documentSelector: [
			{ scheme: "file" },
		],
		outputChannel,
	};

	client = new LanguageClient(
		"lexicon-lsp",
		"Lexicon LSP",
		serverOptions,
		clientOptions
	);
	await client.start();
}

async function stopLanguageServer(): Promise<void> {
	if (client === undefined) {
		return;
	}
	const runningClient = client;
	client = undefined;
	await runningClient.stop();
}

function binaryConfiguration(): ServerBinaryConfiguration {
	const configuration = vscode.workspace.getConfiguration("lexicon.lsp.binary");
	return {
		path: configuration.get("path"),
		arguments: configuration.get("arguments", []),
		env: configuration.get("env", {}),
	};
}

function configurationGlob(): string {
	return `**/{${configurationFileNames.join(",")}}`;
}
