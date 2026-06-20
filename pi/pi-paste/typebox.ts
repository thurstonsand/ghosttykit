import type { Static, TSchema } from "typebox";
import { Value } from "typebox/value";

export function parseTypeBoxValue<T extends TSchema>(
  schema: T,
  value: unknown,
  context: string,
): Static<T> {
  if (Value.Check(schema, value)) {
    return value as Static<T>;
  }

  throw new Error(formatTypeBoxError(schema, value, context));
}

function formatTypeBoxError(schema: TSchema, value: unknown, context: string): string {
  const firstError = Value.Errors(schema, value)[0];
  if (!firstError) {
    return `${context}: invalid value.`;
  }

  const path = firstError.instancePath.length > 0 ? firstError.instancePath : "/";
  return `${context}: ${path} ${firstError.message}`;
}
