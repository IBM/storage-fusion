// PluginRoot entry point for Scalprum dynamic plugin loader.
// The NamespaceNameFieldExtension is exposed via its own dedicated module
// (see scalprum.exposedModules in package.json) to avoid circular
// initialization between the PluginRoot and NamespaceNameFieldExtension chunks.
export {};
