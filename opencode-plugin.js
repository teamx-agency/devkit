/**
 * TeamX DevKit — OpenCode Plugin Entry Point
 *
 * This file is the npm entry point for OpenCode consumers.
 *
 * Usage in .opencode/opencode.json:
 *   { "plugin": ["teamx-devkit/opencode-plugin"] }
 *
 * Or if published under @teamx scope:
 *   { "plugin": ["@teamx/devkit/opencode-plugin"] }
 *
 * The plugin self-contains all gate enforcement, state tracking,
 * and session restoration logic. No additional configuration needed
 * beyond having the TeamX MCP server configured.
 */

export { DevKitPlugin } from './configs/opencode/plugins/devkit.js'
