import { spawn } from "child_process";
import * as fs from "fs/promises";
import * as os from "os";
import * as path from "path";
import { downloadAndUnzipVSCode, runTests } from "@vscode/test-electron";

async function main(): Promise<void> {
	const extensionDevelopmentPath = path.resolve(__dirname, "..", "..");
	const repositoryRoot = path.resolve(extensionDevelopmentPath, "..", "..", "..");
	const lspPath = path.join(
		repositoryRoot,
		".build",
		"debug",
		process.platform === "win32" ? "lexicon-lsp.exe" : "lexicon-lsp"
	);
	await runTrustedWorkspaceTests(extensionDevelopmentPath, lspPath);
	await runUntrustedWorkspaceTests(extensionDevelopmentPath);
}

async function runTrustedWorkspaceTests(
	extensionDevelopmentPath: string,
	lspPath: string
): Promise<void> {
	const workspacePath = await createTrustedWorkspace(lspPath);
	const userDataPath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-user-"));
	const extensionsPath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-extensions-"));
	await runTests({
		extensionDevelopmentPath,
		extensionTestsPath: path.resolve(__dirname, "e2e"),
		version: "1.100.0",
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

async function runUntrustedWorkspaceTests(extensionDevelopmentPath: string): Promise<void> {
	const workspacePath = await createUntrustedWorkspace();
	const userDataPath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-untrusted-user-"));
	const extensionsPath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-untrusted-extensions-"));
	const vscodeExecutablePath = await downloadAndUnzipVSCode({
		version: "1.100.0",
	});
	await runVSCodeWithoutDisablingWorkspaceTrust(vscodeExecutablePath, [
		workspacePath,
		"--no-sandbox",
		"--disable-gpu-sandbox",
		"--disable-updates",
		"--skip-welcome",
		"--skip-release-notes",
		"--no-cached-data",
		`--extensionTestsPath=${path.resolve(__dirname, "untrusted.e2e")}`,
		`--extensionDevelopmentPath=${extensionDevelopmentPath}`,
		"--user-data-dir",
		userDataPath,
		"--extensions-dir",
		extensionsPath,
		"--disable-extensions",
	]);
}

async function runVSCodeWithoutDisablingWorkspaceTrust(
	executablePath: string,
	args: string[]
): Promise<void> {
	await new Promise<void>((resolve, reject) => {
		const child = spawn(executablePath, args, { stdio: "inherit" });
		child.once("error", reject);
		child.once("exit", (code, signal) => {
			if (code === 0) {
				resolve();
				return;
			}
			reject(new Error(
				signal === null
					? `VS Code extension tests exited with code ${code}`
					: `VS Code extension tests exited due to signal ${signal}`
			));
		});
	});
}

async function createTrustedWorkspace(lspPath: string): Promise<string> {
	const workspacePath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-"));
	await fs.mkdir(path.join(workspacePath, ".vscode"), { recursive: true });
	await fs.mkdir(path.join(workspacePath, "app"), { recursive: true });
	await fs.writeFile(
		path.join(workspacePath, ".vscode", "settings.json"),
		JSON.stringify({ "lexicon.lsp.binary.path": lspPath }, null, 2)
	);
	await fs.writeFile(
		path.join(workspacePath, "app", ".lexicon.conf"),
		JSON.stringify({ lexicon: "demo.lexicon" }, null, 2)
	);
	await fs.writeFile(
		path.join(workspacePath, "app", "demo.lexicon"),
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
		path.join(workspacePath, "app", "replacement.lexicon"),
		[
			"test:",
			"\ttype:",
			"\t\teven:",
			"\t\t\tgood:",
			"\t\t\tyes:",
			"",
		].join("\n")
	);
	await fs.writeFile(
		path.join(workspacePath, "app", "scratch.lexicon"),
		[
			"usage:",
			"\titem:",
			"\t+ test.type.even.",
			"",
		].join("\n")
	);
	await fs.writeFile(
		path.join(workspacePath, "app", "notes.txt"),
		[
			"value = l(\"test.type.even.\")",
			"",
		].join("\n")
	);
	return workspacePath;
}

async function createUntrustedWorkspace(): Promise<string> {
	const workspacePath = await fs.mkdtemp(path.join(os.tmpdir(), "lexicon-vscode-untrusted-"));
	const executable = process.platform === "win32" ? "lexicon-lsp.cmd" : "lexicon-lsp";
	const configuredRelativePath = path.join("bin", executable);
	const configuredPath = path.join(workspacePath, configuredRelativePath);
	const workspaceBuildPath = path.join(workspacePath, ".build", "debug", executable);
	const markerPath = path.join(workspacePath, ".server-launched");

	await fs.mkdir(path.join(workspacePath, ".vscode"), { recursive: true });
	await fs.mkdir(path.dirname(configuredPath), { recursive: true });
	await fs.mkdir(path.dirname(workspaceBuildPath), { recursive: true });
	await fs.writeFile(
		path.join(workspacePath, ".vscode", "settings.json"),
		JSON.stringify({
			"lexicon.lsp.binary.path": configuredRelativePath,
			"lexicon.lsp.binary.arguments": ["--workspace-controlled"],
			"lexicon.lsp.binary.env": { LEXICON_WORKSPACE_CONTROLLED: "true" },
		}, null, 2)
	);
	await fs.writeFile(
		path.join(workspacePath, "lexicon.conf"),
		JSON.stringify({ lexicon: "demo.lexicon" }, null, 2)
	);
	await fs.writeFile(path.join(workspacePath, "demo.lexicon"), "root:\n");
	await writeLaunchMarkerExecutable(configuredPath, markerPath);
	await writeLaunchMarkerExecutable(workspaceBuildPath, markerPath);
	return workspacePath;
}

async function writeLaunchMarkerExecutable(
	executablePath: string,
	markerPath: string
): Promise<void> {
	const source = process.platform === "win32"
		? `@echo launched>\"${markerPath}\"\r\n`
		: `#!/usr/bin/env node\nrequire("fs").writeFileSync(${JSON.stringify(markerPath)}, "launched");\n`;
	await fs.writeFile(executablePath, source);
	if (process.platform !== "win32") {
		await fs.chmod(executablePath, 0o755);
	}
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});
