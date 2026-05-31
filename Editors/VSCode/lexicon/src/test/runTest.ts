import * as fs from "fs/promises";
import * as os from "os";
import * as path from "path";
import { runTests } from "@vscode/test-electron";

async function main(): Promise<void> {
	const extensionDevelopmentPath = path.resolve(__dirname, "..", "..");
	const extensionTestsPath = path.resolve(__dirname, "e2e");
	const repositoryRoot = path.resolve(extensionDevelopmentPath, "..", "..", "..");
	const lspPath = path.join(
		repositoryRoot,
		".build",
		"debug",
		process.platform === "win32" ? "lexicon-lsp.exe" : "lexicon-lsp"
	);
	const workspacePath = await createWorkspace(lspPath);
	const userDataPath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-user-"));
	const extensionsPath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-extensions-"));
	await runTests({
		extensionDevelopmentPath,
		extensionTestsPath,
		launchArgs: [
			workspacePath,
			"--user-data-dir",
			userDataPath,
			"--extensions-dir",
			extensionsPath,
			"--disable-workspace-trust",
			"--disable-extensions",
		],
	});
}

async function createWorkspace(lspPath: string): Promise<string> {
	const workspacePath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-"));
	await fs.mkdir(path.join(workspacePath, ".vscode"), { recursive: true });
	await fs.writeFile(
		path.join(workspacePath, ".vscode", "settings.json"),
		JSON.stringify({ "lexicon.lsp.binary.path": lspPath }, null, 2)
	);
	await fs.writeFile(
		path.join(workspacePath, "lexicon-lsp.json"),
		JSON.stringify({ lexicon: "demo.lexicon" }, null, 2)
	);
	await fs.writeFile(
		path.join(workspacePath, "demo.lexicon"),
		[
			"test:",
			"\ttype:",
			"\t\teven:",
			"\t\t\tbad:",
			"\t\t\tno:",
			"",
		].join("\n")
	);
	await fs.writeFile(
		path.join(workspacePath, "scratch.lexicon"),
		[
			"usage:",
			"\titem:",
			"\t+ test.type.even.",
			"",
		].join("\n")
	);
	await fs.writeFile(
		path.join(workspacePath, "notes.txt"),
		[
			"value = l(\"test.type.even.\")",
			"",
		].join("\n")
	);
	return workspacePath;
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});
