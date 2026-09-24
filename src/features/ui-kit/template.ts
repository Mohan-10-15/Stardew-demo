/**
 * Shared pure string-template helper for i18n tables. Templates use named
 * `{token}` placeholders filled by the provided record. Unknown tokens are kept
 * verbatim so a missing entry never renders an empty string silently.
 */
export function replaceTokens(template: string, tokens: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (_match, name: string) => {
    const value = tokens[name];
    return value !== undefined ? value : `{${name}}`;
  });
}