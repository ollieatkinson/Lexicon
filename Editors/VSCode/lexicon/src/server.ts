import * as fs from "fs";
import * as os from "os";
import * as path from "path";

export interface ServerBinaryConfiguration {
	path?: string;
	arguments: string[];
	env: Record<string, string>;
}

export interface WorkspaceFolder {
	uri: {
		fsPath: string;
	};
}

type Exists = (file: string) => boolean;

export function resolveServerCommand(
	configuration: ServerBinaryConfiguration,
	workspaceFolders: readonly WorkspaceFolder[] | undefined,
	workspaceTrusted: boolean,
	pathValue = process.env.PATH ?? "",
	exists: Exists = isExecutable
): string | undefined {
	if (!workspaceTrusted) {
		return undefined;
	}
	const configured = configuredServerCommand(configuration.path, workspaceFolders, exists);
	if (configured !== undefined) {
		return configured;
	}
	for (const candidate of workspaceServerCandidates(workspaceFolders)) {
		if (exists(candidate)) {
			return candidate;
		}
	}
	return findOnPath("lexicon-lsp", pathValue, exists);
}

export function configuredServerCommand(
	value: string | undefined,
	workspaceFolders: readonly WorkspaceFolder[] | undefined,
	exists: Exists = isExecutable
): string | undefined {
	const trimmed = value?.trim();
	if (!trimmed) {
		return undefined;
	}
	if (path.isAbsolute(trimmed)) {
		return trimmed;
	}
	for (const folder of workspaceFolders ?? []) {
		const candidate = path.join(folder.uri.fsPath, trimmed);
		if (exists(candidate)) {
			return candidate;
		}
	}
	return trimmed;
}

export function workspaceServerCandidates(
	workspaceFolders: readonly WorkspaceFolder[] | undefined
): string[] {
	return (workspaceFolders ?? []).flatMap((folder) => [
		path.join(folder.uri.fsPath, ".build", "release", executableName("lexicon-lsp")),
		path.join(folder.uri.fsPath, ".build", "debug", executableName("lexicon-lsp")),
	]);
}

export function findOnPath(
	command: string,
	pathValue = process.env.PATH ?? "",
	exists: Exists = isExecutable
): string | undefined {
	for (const directory of pathValue.split(path.delimiter).filter(Boolean)) {
		for (const name of executableNames(command)) {
			const candidate = path.join(directory, name);
			if (exists(candidate)) {
				return candidate;
			}
		}
	}
	return undefined;
}

function executableName(command: string): string {
	return os.platform() === "win32" ? `${command}.exe` : command;
}

function executableNames(command: string): string[] {
	if (os.platform() !== "win32" || path.extname(command) !== "") {
		return [command];
	}
	return [".exe", ".cmd", ".bat", ""].map((extension) => `${command}${extension}`);
}

function isExecutable(file: string): boolean {
	try {
		fs.accessSync(file, os.platform() === "win32" ? fs.constants.F_OK : fs.constants.X_OK);
		return true;
	} catch {
		return false;
	}
}
