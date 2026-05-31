use zed_extension_api::{
    self as zed, settings::LspSettings, Command, LanguageServerId, Result, Worktree,
};

struct LexiconExtension;

impl zed::Extension for LexiconExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Command> {
        let settings = LspSettings::for_worktree("lexicon-lsp", worktree).unwrap_or_default();
        let (path, args, env) = settings
            .binary
            .map(|binary| {
                (
                    binary.path,
                    binary.arguments.unwrap_or_default(),
                    binary.env.unwrap_or_default().into_iter().collect(),
                )
            })
            .unwrap_or_else(|| (None, Vec::new(), Vec::new()));
        let command = path
            .or_else(|| worktree.which("lexicon-lsp"))
            .ok_or_else(|| {
                "Install lexicon-lsp or configure lsp.lexicon-lsp.binary.path".to_string()
            })?;

        Ok(Command { command, args, env })
    }
}

zed::register_extension!(LexiconExtension);
